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
    @AppStorage("chatOpacity") private var opacity: Double = 0.9
    @State private var draft = ""
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(log.recent) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(line.name)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Text(line.body)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                        }
                    }
                    .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                }
                .onChange(of: log.recent.count) { _, _ in
                    if let last = log.recent.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            TextField("메시지", text: $draft)
                .textFieldStyle(.plain)
                .font(.caption)
                .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                .onSubmit {
                    Session.shared.sendSay(draft)
                    draft = ""
                }
            if hovering {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $opacity, in: 0.2...1.0)
                        .controlSize(.mini)
                }
                .padding(EdgeInsets(top: 3, leading: 8, bottom: 4, trailing: 8))
            }
        }
        .frame(minWidth: 160, minHeight: 90)
        .onHover { hovering = $0 }
        .onChange(of: opacity) { _, value in ChatPanel.shared.setOpacity(value) }
        .onAppear { ChatPanel.shared.setOpacity(opacity) }
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
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 130),
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
            panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX - 220,
                                         y: screen.visibleFrame.minY + 60))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// 닫기 버튼은 숨기기다. 메뉴에서 다시 연다.
    func hide() { panel?.orderOut(nil) }

    func setOpacity(_ value: Double) { panel?.alphaValue = CGFloat(value) }

    func toggle() { isVisible ? hide() : show() }
}
