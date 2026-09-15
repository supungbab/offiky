import AppKit
import Combine
import SwiftUI

final class ChatLog: ObservableObject {
    static let shared = ChatLog()
    @Published private(set) var recent: [Line] = []

    struct Line: Identifiable {
        let id = UUID()
        let name: String
        let body: String
    }

    func append(name: String, body: String) {
        recent.append(Line(name: name, body: body))
        if recent.count > 50 { recent.removeFirst(recent.count - 50) }
    }
}

struct ChatView: View {
    @ObservedObject private var log = ChatLog.shared
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(log.recent) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(line.name)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(line.body)
                                    .font(.callout)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: log.recent.count) { _, _ in
                    if let last = log.recent.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            TextField("메시지", text: $draft)
                .textFieldStyle(.plain)
                .padding(10)
                .onSubmit {
                    Session.shared.sendSay(draft)
                    draft = ""
                }
        }
        .frame(minWidth: 240, minHeight: 160)
    }
}

final class ChatPanel {
    static let shared = ChatPanel()

    private var panel: NSPanel?

    private init() {}

    func install() {
        Session.shared.onChat = { name, body in
            ChatLog.shared.append(name: name, body: body)
        }
        show()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 220),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "offiky"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ChatView())
        panel.setFrameAutosaveName("chat")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX - 320,
                                         y: screen.visibleFrame.minY + 60))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// 닫기 버튼은 숨기기다. 메뉴에서 다시 연다.
    func hide() { panel?.orderOut(nil) }

    func toggle() { isVisible ? hide() : show() }
}
