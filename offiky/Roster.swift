import AppKit
import Combine
import SpriteKit
import SwiftUI

/// 참가자 목록과 미니맵. 좌표는 모두가 공유하므로 누가 어디 있는지 그릴 수 있다.
struct RosterView: View {
    @State private var rows: [Row] = []
    @State private var bounds: (min: CGFloat, max: CGFloat) = (0, 0)

    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    struct Row: Identifiable {
        let id: String
        let name: String
        let x: CGFloat
        let look: Look
        let isMe: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("참가자 \(rows.count)명").font(.headline)

            map
                .frame(height: 46)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        line(row)
                        if row.id != rows.last?.id { Divider() }
                    }
                }
            }

            Text("이름을 누르면 그 자리로 이동한다")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320, height: 380)
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
    }

    private var map: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(height: 1)
                    .padding(.bottom, 8)

                ForEach(rows) { row in
                    thumbnail(row.look, size: 20)
                        .offset(x: offset(row.x, width: geometry.size.width) - 10)
                        .padding(.bottom, 9)
                        .opacity(row.isMe ? 1 : 0.75)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func line(_ row: Row) -> some View {
        Button {
            World.shared.teleport(to: row.x)
        } label: {
            HStack(spacing: 8) {
                thumbnail(row.look, size: 22)
                Text(row.name).lineLimit(1)
                if row.isMe {
                    Text("나").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(row.x))").font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .disabled(row.isMe)
    }

    /// 띠 좌표를 막대 안의 위치로 옮긴다
    private func offset(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let span = bounds.max - bounds.min
        guard span > 0 else { return width / 2 }
        return (x - bounds.min) / span * width
    }

    private func thumbnail(_ look: Look, size: CGFloat) -> some View {
        let sheet = Characters.sheet(look)
        let textures = sheet.frames[.idle] ?? []
        let scale = size / max(sheet.size.width, sheet.size.height)
        return Group {
            if let cg = textures.first?.cgImage() as CGImage? {
                Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: sheet.size.width,
                                                                 height: sheet.size.height)))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: sheet.size.width * scale, height: sheet.size.height * scale)
            }
        }
    }

    private func refresh() {
        rows = World.shared.roster().map {
            Row(id: $0.id, name: $0.name, x: $0.x, look: $0.look, isMe: $0.isMe)
        }
        let strip = OverlayController.shared.strip
        bounds = (strip.minX, strip.maxX)
    }
}

private var rosterWindow: NSWindow?

func openRoster() {
    if let window = rosterWindow {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 380),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "참가자"
    window.contentView = NSHostingView(rootView: RosterView())
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    rosterWindow = window
}
