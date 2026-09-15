import SwiftUI

@main
struct offikyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var hidden = false

    var body: some Scene {
        MenuBarExtra("offiky", systemImage: "person.2.fill") {
            let roster = Session.shared.roster
            Text("접속자 \(roster.count)명")
            ForEach(roster, id: \.id) { peer in
                Text(peer.name)
            }
            Divider()
            let recent = Array(ChatLog.shared.recent.suffix(50).reversed())
            if recent.isEmpty {
                Text("최근 메시지 없음")
            } else {
                ForEach(Array(recent.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
            Divider()
            Button("채팅 열기  ⌥Space") { ChatPanel.shared.show() }
            Button("내 캐릭터 편집…") { openSpriteEditor() }
            Button("내 이름 변경…") { changeName() }
            Toggle("캐릭터 숨기기", isOn: $hidden)
                .onChange(of: hidden) { _, value in
                    OverlayController.shared.setHidden(value)
                }
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
    }

    private func changeName() {
        let alert = NSAlert()
        alert.messageText = "내 이름"
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = World.shared.me.displayName
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = sanitizeName(field.stringValue)
        World.shared.me.displayName = name
        UserDefaults.standard.set(name, forKey: "name")
        Session.shared.sendProfile()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        OverlayController.shared.start()
        Session.shared.start()
        Mesh.shared.start()
        ChatPanel.shared.install()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { _ in Mesh.shared.stop() }
        center.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { _ in Mesh.shared.start() }
    }
}
