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

/// 조작 안내 창 크기. 채팅 입력란도 같은 높이를 쓴다
let panelSize = CGSize(width: 680, height: 48)

/// 시스템 HUD 와 같은 모서리
private let panelShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

/// 재질·테두리·모서리를 한 군데서 정한다. 두 창이 같은 것을 쓴다
extension View {
    func panelSurface() -> some View {
        background(.regularMaterial)
            .clipShape(panelShape)
            .overlay(panelShape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

/// borderless 윈도우는 기본적으로 키 윈도우가 되지 않아 입력을 받지 못한다.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// 지금 데스크톱에 표시한 뒤 모든 데스크톱에 속하게 한다. 모니터 연결을 해제하면 숨겨 둔 창이 그 모니터의 데스크톱에만 속해, 그대로 표시하면 그 데스크톱으로 전환된다
    override func makeKeyAndOrderFront(_ sender: Any?) {
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.makeKeyAndOrderFront(sender)
        // 같은 실행 루프에서 되돌리면 되돌린 설정으로 표시되어 전환된다
        DispatchQueue.main.async { self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] }
    }

    /// 조작 안내가 쓰는 창. 다른 곳을 클릭하면 `onResign` 을 호출한다
    static func floating(onResign: @escaping () -> Void) -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { _ in onResign() }
        return panel
    }
}

/// 마우스가 있는 화면. 화면 구성이 바뀌는 순간에는 0개로 보고되어 nil 이다
func screenUnderMouse() -> NSScreen? {
    NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
}

/// AppKit 이 저장한 "x y w h 화면x 화면y 화면w 화면h" 에서 창 frame 만 읽는다
func savedChatFrame(_ value: String? = UserDefaults.standard.string(forKey: "NSWindow Frame ChatFrame")) -> CGRect? {
    let n = (value ?? "").split(separator: " ").compactMap { Double($0) }
    guard n.count >= 4 else { return nil }
    return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
}

/// 채팅 입력란과 조작 안내가 같은 높이에 뜬다
func panelOrigin(on screen: NSScreen, width: CGFloat) -> CGPoint {
    CGPoint(x: screen.visibleFrame.midX - width / 2,
            y: screen.visibleFrame.minY + screen.visibleFrame.height * 0.22)
}

/// 띄우기 직전의 앱을 기억했다가 닫을 때 포커스를 되돌린다
struct FocusReturn {
    private var app: NSRunningApplication?

    /// 우리 앱이 이미 앞에 있으면 직전 값을 유지한다. 덮어쓰면 복귀 대상이 자기 자신이 된다
    mutating func remember() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            app = front
        }
    }

    /// 다른 앱을 클릭해 닫힌 경우에는 그 앱이 이미 앞에 있으므로 `restoring` 을 false 로 호출한다
    mutating func restore(_ restoring: Bool) {
        let target = app
        app = nil
        guard restoring, let target else { return }
        // macOS 14 부터 다른 앱을 그냥 activate 하면 시스템이 무시한다
        NSApp.yieldActivation(to: target)
        target.activate()
    }
}

/// 채널에 있는 동안만 들고 있는 채팅 기록. 디스크에 쓰지 않는다
@Observable final class ChatLog {
    static let shared = ChatLog()

    struct Entry: Identifiable {
        let id = UUID()
        /// 말한 시점의 이름. 뒤에 이름을 바꿔도 그때 부르던 이름으로 남는다
        let name: String
        let text: String
        let at: Date
        let isMe: Bool
        /// 채널·동료 소식. 이름 없이 회색 한 줄로 남는다
        var isSystem = false
    }

    /// 최신이 앞이다. 입력란 바로 아래가 방금 한 말이 된다
    private(set) var entries: [Entry] = []

    private init() {}

    func add(name: String, text: String, isMe: Bool) {
        insert(Entry(name: name, text: text, at: Date(), isMe: isMe))
    }

    func note(_ text: String) {
        insert(Entry(name: "", text: text, at: Date(), isMe: false, isSystem: true))
    }

    func joined(_ name: String) {
        // 잠깐 끊겼다 돌아온 것이면 나갔다는 줄을 지우고 끝낸다
        if let index = entries.firstIndex(where: {
            $0.isSystem && $0.text == ChatLog.goneText(name)
        }), Date().timeIntervalSince(entries[index].at) < 60 {
            entries.remove(at: index)
            return
        }
        note("\(name) 님이 들어왔습니다")
    }

    func gone(_ name: String) { note(ChatLog.goneText(name)) }

    func clear() {
        entries.removeAll()
    }

    private static func goneText(_ name: String) -> String { "\(name) 님이 나갔습니다" }

    private func insert(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > Limits.maxChatLog { entries.removeLast() }
    }
}

/// 카카오톡처럼 세로로 긴 창. 처음에는 이 크기로 뜨고 더 줄일 수 없다
private let chatMinSize = CGSize(width: 300, height: 400)

private struct ChatHistoryView: View {
    /// 맨 아래에 보이는 말. 직접 스크롤할 때만 갱신되고 scrollTo 로 이동해서는 갱신되지 않는다
    @State private var bottom: UUID?
    @State private var following = true
    private static let end = "end"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        // 입력란이 아래라 최신이 아래여야 한다. 저장은 최신이 앞이다
                        ForEach(ChatLog.shared.entries.reversed()) { entry in
                            if entry.isSystem {
                                Text(entry.text).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                                    .frame(maxWidth: .infinity)
                            } else {
                                bubbleRow(entry)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .font(.system(size: 12))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 마지막 말이 아니라 여기로 이동해야 아래 여백까지 보인다
                    Color.clear.frame(height: 0).id(Self.end)
                }
            }
            .defaultScrollAnchor(.bottom)
            .scrollPosition(id: $bottom, anchor: .bottom)
            .onChange(of: bottom) { following = bottom == ChatLog.shared.entries.first?.id }
            // defaultScrollAnchor 는 한 번 스크롤하면 따라가지 않는다. 맨 아래에 있었거나 내가 보냈으면 새 말로 이동한다
            .onChange(of: ChatLog.shared.entries.first?.id) { _, new in
                guard new != nil, following || ChatLog.shared.entries.first?.isMe == true else { return }
                following = true
                proxy.scrollTo(Self.end, anchor: .bottom)
            }
        }
        .frame(minHeight: 60, maxHeight: .infinity)
        .overlay {
            if ChatLog.shared.entries.isEmpty {
                Text("지난 대화가 없습니다").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
    }

    /// 내 말은 오른쪽 강조색 말풍선, 동료 말은 이름 아래 왼쪽 말풍선
    private func bubbleRow(_ entry: ChatLog.Entry) -> some View {
        let time = Text(entry.at.formatted(date: .omitted, time: .shortened))
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.tertiary)
        let bubble = Text(entry.text)
            .textSelection(.enabled)
            .foregroundStyle(entry.isMe ? Color.white : Color.primary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(entry.isMe ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        return HStack(alignment: .bottom, spacing: 4) {
            if entry.isMe {
                Spacer(minLength: 60)
                time
                bubble
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name).font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(alignment: .bottom, spacing: 4) { bubble; time }
                }
                Spacer(minLength: 60)
            }
        }
    }
}

private struct ChatInputView: View {
    let titlebarHeight: CGFloat
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChatHistoryView()
            Divider()
            inputBar.frame(height: panelSize.height)
        }
        // sizingOptions 가 이 최소 크기를 창의 최소 크기로 적용한다
        .frame(minWidth: chatMinSize.width, minHeight: chatMinSize.height)
        // 본문은 제목 표시줄 아래에 배치되므로 조작 안내와 같은 재질·모서리를 그 높이만큼 위로 확장해 그린다
        .background {
            panelShape.fill(.regularMaterial)
                .overlay(panelShape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .padding(.top, -titlebarHeight)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("", text: $draft, prompt: Text("엔터로 보내기").foregroundStyle(.tertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                // 넘겨 적으면 전송할 때 조용히 사라진다. 여기서 막고 남은 길이를 보여 준다
                .onChange(of: draft) {
                    draft = clamped(draft, maxCount: Limits.maxChat,
                                    maxBytes: Limits.maxChatBytes)
                    if !draft.isEmpty { Session.shared.sendTyping() }
                }
                .onAppear { DispatchQueue.main.async { focused = true } }
                // 보내고도 열어 둔다. 대화가 이어질 때 ⌥F 를 다시 누르지 않아도 된다
                .onSubmit {
                    Session.shared.sendSay(draft)
                    draft = ""
                }
                .onExitCommand { ChatPanel.shared.hide() }
            Text("\(draft.count)/\(Limits.maxChat)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
    }
}

@Observable final class ChatPanel {
    static let shared = ChatPanel()

    private var window: NSWindow?
    private var hotKey: HotKey?
    private var focus = FocusReturn()

    private init() {}

    var opacity = UserDefaults.standard.object(forKey: "chatOpacity") as? Double ?? 1 {
        didSet {
            UserDefaults.standard.set(opacity, forKey: "chatOpacity")
            window?.alphaValue = opacity
        }
    }

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
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.redirect(event) ?? event
        }
    }

    /// 기록의 글을 선택하면 입력란이 포커스를 잃는다. 그때 누른 키는 입력란으로 보내고 Esc 는 창을 닫는다
    private func redirect(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, !event.modifierFlags.contains(.command),
              (window.firstResponder as? NSTextView)?.isEditable != true
        else { return event }
        if event.keyCode == UInt16(kVK_Escape) { hide(); return nil }
        focusField()
        return event
    }

    /// 포커스를 받으면 전체가 선택되어 입력한 글자가 쓰던 글을 덮어쓰므로 커서를 끝에 둔다
    private func focusField() {
        guard let window, let field = window.contentView.flatMap(editableField) else { return }
        window.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
    }

    private func editableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap(editableField).first
    }

    /// 맨 앞에서 입력 중이면 닫고, 닫혀 있거나 다른 창 뒤에 있으면 앞으로 가져온다
    func toggle() {
        if NSApp.isActive, window?.isKeyWindow == true { hide() } else { show() }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // 숨긴 사이 그 모니터 연결을 해제했으면 마우스가 있는 화면으로 옮긴다
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }),
           let screen = screenUnderMouse() {
            window.setFrameOrigin(panelOrigin(on: screen, width: window.frame.width))
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        focus.remember()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        focusField()
    }

    private func makeWindow() -> NSWindow {
        let origin = screenUnderMouse().map { panelOrigin(on: $0, width: chatMinSize.width) } ?? .zero
        let window = NSWindow(contentRect: CGRect(origin: origin, size: chatMinSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "채팅"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        // ⌥F 를 누른 데스크톱으로 창을 가져오고 전체 화면 앱 위에도 표시한다
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.alphaValue = opacity
        // safeAreaRegions 를 비워 창 전체에 그리면 hosting view 가 레이아웃마다 창을 제목 표시줄 높이만큼 키운다
        let hosting = NSHostingView(rootView: ChatInputView(titlebarHeight: window.frame.height - window.contentLayoutRect.height))
        hosting.sizingOptions = [.minSize]
        window.contentView = hosting
        // 카카오톡처럼 우측 상단에서 투명도를 정한다
        let slider = NSHostingView(rootView: Slider(value: Bindable(self).opacity, in: 0.3...1)
            .controlSize(.mini).frame(width: 80).padding(.horizontal, 12))
        slider.frame.size = slider.fittingSize
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = slider
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
        window.setFrameAutosaveName("ChatFrame")
        // setFrameUsingName 은 주 화면이 아닌 화면에 저장된 자리를 주 화면으로 옮기므로 직접 읽는다
        if let saved = savedChatFrame(), NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) {
            window.setFrame(saved, display: false)
        }
        return window
    }

    /// Esc·⌥F 로 닫으면 열기 직전의 앱으로 포커스를 되돌린다
    func hide() {
        window?.orderOut(nil)
        focus.restore(true)
    }
}
