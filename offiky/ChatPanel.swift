import AppKit
import Carbon.HIToolbox
import SwiftUI

final class HotKey {
    private static var registry: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?
    private(set) var registered = false

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        let id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.registry[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F464659), id: id)
        registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref) == noErr
    }

    deinit { if let ref { UnregisterEventHotKey(ref) } }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotKey.registry[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

final class ChatLog {
    static let shared = ChatLog()
    private(set) var recent: [String] = []

    func append(_ line: String) {
        recent.append(line)
        if recent.count > 50 { recent.removeFirst(recent.count - 50) }
    }
}

/// borderless 윈도우는 기본적으로 키 윈도우가 되지 않아 입력을 받지 못한다.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct ChatInputView: View {
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft, prompt: Text("메시지").foregroundStyle(.secondary))
            .textFieldStyle(.plain)
            .font(.system(size: 17))
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit {
                Session.shared.sendSay(draft)
                draft = ""
                ChatPanel.shared.hide()
            }
            .onExitCommand {
                draft = ""
                ChatPanel.shared.hide()
            }
    }
}

final class ChatPanel {
    static let shared = ChatPanel()

    private var panel: KeyPanel?
    private var hotKey: HotKey?

    private init() {}

    func install() {
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.toggle()
        }
        Session.shared.onChat = { name, body in
            ChatLog.shared.append("\(name): \(body)")
        }
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let size = CGSize(width: 520, height: 52)
        // 화면 가운데 아래
        let origin = CGPoint(x: screen.visibleFrame.midX - size.width / 2,
                             y: screen.visibleFrame.minY + screen.visibleFrame.height * 0.22)

        let panel = self.panel ?? {
            let created = KeyPanel(contentRect: CGRect(origin: origin, size: size),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            created.level = .modalPanel
            created.hidesOnDeactivate = false
            created.isReleasedWhenClosed = false
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            // 스포트라이트처럼 다른 곳을 클릭하면 사라진다
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: created, queue: .main
            ) { [weak self] _ in self?.hide() }
            self.panel = created
            return created
        }()

        // 매번 새 뷰를 넣어 입력란을 비우고 포커스를 다시 잡는다
        panel.contentView = NSHostingView(rootView: ChatInputView())
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() { panel?.orderOut(nil) }
}
