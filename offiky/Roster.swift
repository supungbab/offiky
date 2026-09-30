import SwiftUI

struct RosterRow: Identifiable {
    let id: String
    let name: String
    let look: Look
    let isMe: Bool
}

/// 누가 접속해 있는지 보여준다. 위치는 화면에서 직접 보면 된다.
struct RosterView: View {
    @State private var rows: [RosterRow] = []

    var body: some View {
        // 인원수는 이 창을 연 메뉴 항목에 이미 있다. 여기에 또 적지 않는다
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
                    }
                    .padding(.vertical, 5)
                    if row.id != rows.last?.id { Divider() }
                }
            }
        }
        .padding(16)
        .frame(width: 260, height: 320)
        // Timer 구독은 창을 숨겨도 유지된다. task 는 창이 사라질 때 취소된다
        .task {
            while !Task.isCancelled {
                rows = World.shared.roster()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private let rosterPanel = Panel()

func openRoster() {
    rosterPanel.show(title: "참가자", content: RosterView())
}
