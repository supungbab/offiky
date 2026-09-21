import AppKit
import Combine
import SpriteKit
import SwiftUI

/// 누가 접속해 있는지와 누가 중계를 맡았는지 보여준다. 위치는 화면에서 직접 보면 된다.
struct RosterView: View {
    @State private var rows: [Row] = []

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct Row: Identifiable {
        let id: String
        let name: String
        let look: Look
        let isMe: Bool
        let isHost: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("참가자 \(rows.count)명").font(.headline)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            thumbnail(row.look, size: 22)
                            Text(row.name).lineLimit(1)
                            if row.isMe {
                                Text("나").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            // 이 사람이 나가면 다른 사람이 이어받으며 잠깐 끊긴다
                            if row.isHost {
                                Text("호스트")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        .padding(.vertical, 5)
                        if row.id != rows.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 260, height: 320)
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
    }

    private func thumbnail(_ look: Look, size: CGFloat) -> some View {
        Group {
            if let image = Characters.thumbnail(look) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }

    private func refresh() {
        rows = World.shared.roster().map {
            Row(id: $0.id, name: $0.name, look: $0.look, isMe: $0.isMe, isHost: $0.isHost)
        }
    }
}

private var rosterWindow: NSWindow?

func openRoster() {
    if let window = rosterWindow {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 260, height: 320),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "참가자"
    window.contentView = NSHostingView(rootView: RosterView())
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    rosterWindow = window
}
