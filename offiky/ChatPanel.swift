import AppKit
import Carbon.HIToolbox

final class HotKey {
    private static var registry: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        let id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.registry[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F464659), id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
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

final class ChatPanel: NSObject, NSTextFieldDelegate {
    static let shared = ChatPanel()

    private var panel: NSPanel?
    private var hotKey: HotKey?

    func install() {
        hotKey = HotKey(keyCode: UInt32(kVK_Space),
                        modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.toggle()
        }
        Session.shared.onChat = { name, body in
            ChatLog.shared.append("\(name): \(body)")
        }
    }

    func toggle() {
        if panel != nil { close(); return }

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let size = CGSize(width: 420, height: 44)
        let origin = CGPoint(x: screen.frame.midX - size.width / 2,
                             y: screen.frame.midY - size.height / 2)

        let panel = NSPanel(contentRect: CGRect(origin: origin, size: size),
                            styleMask: [.titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false

        let field = NSTextField(frame: CGRect(x: 12, y: 9, width: size.width - 24, height: 26))
        field.placeholderString = "한 줄 입력하고 Enter"
        field.delegate = self
        field.focusRingType = .none
        panel.contentView?.addSubview(field)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(field)
        self.panel = panel
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            Session.shared.sendSay(textView.string)
            close()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }
}
