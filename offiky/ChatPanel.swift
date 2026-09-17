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

/// 채팅과 조작 안내는 같은 자리에 번갈아 뜬다. 크기가 다르면 바뀔 때 눈에 띈다
let panelSize = CGSize(width: 620, height: 52)

/// borderless 윈도우는 기본적으로 키 윈도우가 되지 않아 입력을 받지 못한다.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct ChatInputView: View {
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft, prompt: Text("엔터로 보내기").foregroundStyle(.secondary))
            .textFieldStyle(.plain)
            .font(.system(size: 17))
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .focused($focused)
            .onAppear { DispatchQueue.main.async { focused = true } }
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

@Observable final class ChatPanel {
    static let shared = ChatPanel()

    private var panel: KeyPanel?
    private var hotKey: HotKey?
    private var presenting = false
    private var previousApp: NSRunningApplication?

    private init() {}

    /// 다른 앱이 같은 조합을 먼저 잡고 있으면 등록에 실패한다.
    /// 알리지 않으면 사용자는 앱이 고장 난 줄 안다.
    private(set) var hotKeyWorks = true

    func install() {
        // 왼엄지가 ⌥ 로, 왼검지는 이미 F 에 있다. 손가락이 홈 포지션을 떠나지 않는다.
        // ⌥Space 는 Alfred 기본 단축키라 피한다.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_F),
                        modifiers: UInt32(optionKey)) { [weak self] in
            self?.toggle()
        }
        hotKeyWorks = hotKey?.registered ?? false
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let size = panelSize
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
            ) { [weak self] _ in
                guard let self, !self.presenting else { return }
                self.hide(restoringFocus: false)
            }
            self.panel = created
            return created
        }()

        // 매번 새 뷰를 넣어 입력란을 비우고 포커스를 다시 잡는다
        presenting = true
        // 우리 앱이 이미 앞에 있으면 직전 값을 유지한다. 덮어쓰면 복귀 대상이 자기 자신이 된다.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        panel.contentView = NSHostingView(rootView: ChatInputView())
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.presenting = false }
    }

    /// Esc·전송으로 닫을 때는 띄우기 직전의 앱으로 포커스를 되돌린다.
    /// 다른 앱을 클릭해 닫힌 경우에는 그 앱이 이미 앞에 있으므로 되돌리지 않는다.
    func hide(restoringFocus: Bool = true) {
        let target = previousApp
        previousApp = nil
        panel?.orderOut(nil)
        guard restoringFocus, let target else { return }
        // macOS 14 부터 다른 앱을 그냥 activate 하면 시스템이 무시한다
        NSApp.yieldActivation(to: target)
        target.activate()
    }
}
