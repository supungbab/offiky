import AppKit
import Carbon.HIToolbox
import SwiftUI

enum Shortcut {
    static let defaultKeyCode = UInt32(kVK_ANSI_C)
    static let defaultModifiers = UInt32(controlKey | optionKey)

    static var keyCode: UInt32 {
        let stored = UserDefaults.standard.object(forKey: "hotKeyCode") as? Int
        return stored.map(UInt32.init) ?? defaultKeyCode
    }

    static var modifiers: UInt32 {
        let stored = UserDefaults.standard.object(forKey: "hotKeyModifiers") as? Int
        return stored.map(UInt32.init) ?? defaultModifiers
    }

    static func save(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: "hotKeyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "hotKeyModifiers")
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    static var description: String {
        var text = ""
        let mods = modifiers
        if mods & UInt32(controlKey) != 0 { text += "⌃" }
        if mods & UInt32(optionKey) != 0 { text += "⌥" }
        if mods & UInt32(shiftKey) != 0 { text += "⇧" }
        if mods & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName(keyCode)
    }

    private static let named: [UInt32: String] = [
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab", UInt32(kVK_Escape): "Esc",
    ]

    static func keyName(_ code: UInt32) -> String {
        if let name = named[code] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "키\(code)" }
        let layout = unsafeBitCast(raw, to: CFData.self)
        var dead: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = CFDataGetBytePtr(layout).withMemoryRebound(
            to: UCKeyboardLayout.self, capacity: 1
        ) { pointer in
            UCKeyTranslate(pointer, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                           &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "키\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

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

final class ChatPanel {
    static let shared = ChatPanel()

    private var panel: KeyPanel?
    private var hotKey: HotKey?
    private var presenting = false
    private var previousApp: NSRunningApplication?

    private init() {}

    func install() {
        reinstallHotKey()
    }

    func reinstallHotKey() {
        hotKey = HotKey(keyCode: Shortcut.keyCode,
                        modifiers: Shortcut.modifiers) { [weak self] in
            self?.toggle()
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



/// 다음에 누르는 조합을 새 단축키로 받는다
final class HotKeyRecorder {
    static let shared = HotKeyRecorder()

    private var panel: KeyPanel?
    private var monitor: Any?

    private init() {}

    func begin() {
        finish()
        let size = CGSize(width: 320, height: 96)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let panel = KeyPanel(
            contentRect: CGRect(x: screen.frame.midX - size.width / 2,
                                y: screen.frame.midY - size.height / 2,
                                width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .modalPanel
        panel.contentView = NSHostingView(rootView: RecorderView())
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) { self.finish(); return nil }
            let modifiers = Shortcut.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return nil }
            Shortcut.save(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            ChatPanel.shared.reinstallHotKey()
            self.finish()
            return nil
        }
    }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct RecorderView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("새 단축키를 누르세요")
                .font(.headline)
            Text("보조키를 하나 이상 포함해야 합니다. Esc 로 취소")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
