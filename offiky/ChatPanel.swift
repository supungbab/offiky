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

/// 방에 있는 동안만 들고 있는 채팅 기록. 디스크에 쓰지 않는다
@Observable final class ChatLog {
    static let shared = ChatLog()

    struct Entry: Identifiable {
        let id = UUID()
        /// 말한 시점의 이름. 뒤에 이름을 바꿔도 그때 부르던 이름으로 남는다
        let name: String
        let text: String
        let at: Date
        let isMe: Bool
        /// 방·동료 소식. 이름 없이 회색 한 줄로 남는다
        var isSystem = false
    }

    /// 최신이 앞이다. 입력란 바로 아래가 방금 한 말이 된다
    private(set) var entries: [Entry] = []

    private init() {}

    /// 명단을 통째로 다시 받는 동안(호스트 교체·재연결)은 들어왔다고 적지 않는다
    private var regroupingUntil = Date.distantPast

    func add(name: String, text: String, isMe: Bool) {
        insert(Entry(name: name, text: text, at: Date(), isMe: isMe))
    }

    func note(_ text: String) {
        insert(Entry(name: "", text: text, at: Date(), isMe: false, isSystem: true))
    }

    func joined(_ name: String) {
        guard Date() >= regroupingUntil else { return }
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

    func regrouping() { regroupingUntil = Date().addingTimeInterval(10) }

    func clear() {
        entries.removeAll()
        regroupingUntil = .distantPast
    }

    private static func goneText(_ name: String) -> String { "\(name) 님이 나갔습니다" }

    private func insert(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > Limits.maxChatLog { entries.removeLast() }
    }
}

/// 기록 칸 높이. 한 줄짜리 셋쯤 보인다
private let historyHeight: CGFloat = 90

private struct ChatHistoryView: View {
    /// 한 줄로 이어 붙여야 긴 글이 시간·이름 아래로 자연스럽게 흐른다
    private func line(_ entry: ChatLog.Entry) -> Text {
        guard !entry.isSystem else { return Text(entry.text).foregroundStyle(.tertiary) }
        return Text(entry.name).fontWeight(.semibold)
        + Text(entry.isMe ? " (나)" : "").foregroundStyle(.tertiary)
        + Text(" : ").foregroundStyle(.tertiary)
        + Text(entry.text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ChatLog.shared.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        line(entry)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.at.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: historyHeight)
        .overlay {
            if ChatLog.shared.entries.isEmpty {
                Text("지난 대화가 없습니다").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }
}

private struct ChatInputView: View {
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            ChatHistoryView()
            inputBar.frame(height: panelSize.height)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("", text: $draft, prompt: Text("엔터로 보내기").foregroundStyle(.secondary))
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focused)
                // 넘겨 적으면 전송할 때 조용히 사라진다. 여기서 막고 남은 길이를 보여 준다
                .onChange(of: draft) {
                    draft = clamped(draft, maxCount: Limits.maxChat,
                                    maxBytes: Limits.maxChatBytes)
                }
                .onAppear { DispatchQueue.main.async { focused = true } }
                // 보내고도 열어 둔다. 대화가 이어질 때 ⌥F 를 다시 누르지 않아도 된다
                .onSubmit {
                    Session.shared.sendSay(draft)
                    draft = ""
                }
                .onExitCommand {
                    draft = ""
                    ChatPanel.shared.hide()
                }
            Text("\(draft.count)/\(Limits.maxChat)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.white.opacity(0.15), lineWidth: 1))
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
        // 화면 구성이 바뀌는 순간에는 화면이 0개로 보고된다. 띄울 곳이 없다
        guard let screen = NSScreen.screens
            .first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        else { return }
        // 입력란은 있던 자리에 두고 기록 칸이 그 위로 쌓인다
        let bar = screen.visibleFrame.minY + screen.visibleFrame.height * 0.22
        let room = screen.visibleFrame.maxY - bar - panelSize.height - 24
        let above = min(historyHeight + 8, max(0, room))
        let size = CGSize(width: panelSize.width, height: panelSize.height + above)
        let origin = CGPoint(x: screen.visibleFrame.midX - size.width / 2, y: bar)

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.presenting = false
            // 그 사이에 다른 곳을 클릭했으면 알림이 무시됐다. 여기서 확인한다
            if self.panel?.isKeyWindow == false { self.hide(restoringFocus: false) }
        }
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
