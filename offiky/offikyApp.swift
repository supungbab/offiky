import OSLog
import SwiftUI

@main
struct offikyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Button("Offiky 정보…") { openAbout() }
            // 항목은 하나만 두고 받는 방법은 대화상자에서 고르게 한다
            Button(UpdateChecker.shared.newVersion.map { "새 버전 \($0) 받기…" }
                   ?? "업데이트 확인…") {
                UpdateChecker.shared.checkAndTell()
            }
            Divider()
            Button("채팅 열기  ⌥F") { ChatPanel.shared.show() }
            if !ChatPanel.shared.hotKeyWorks {
                Text("⌥F 를 다른 앱이 쓰고 있습니다")
            }
            Button(Control.shared.isOn ? "조종 끝내기  esc" : "캐릭터 조종  ⌥D") {
                Control.shared.toggle()
            }
            if !Control.shared.hotKeyWorks {
                Text("⌥D 를 다른 앱이 쓰고 있습니다")
            }
            Divider()
            // 방 만들기는 들어가 있을 때 내밀지 않는다. 이름 고치기로 읽힌다
            if let room = Presence.shared.room {
                // 내가 나가면 남은 사람들이 잠깐 끊기므로 맡고 있다는 것이 보여야 한다
                Text(Presence.shared.amHost ? "방 · 호스트 · \(room)" : "방 · \(room)")
                // 누가 있는지는 방 이야기다. 방에 없으면 나뿐이라 내밀 것이 없다
                Button("참가자 \(Presence.shared.count)명…") { openRoster() }
                Button("방 나가기") { World.leaveRoom() }
                // 여기까지가 지금 방 이야기다. 다른 방은 그다음이라 두 경우 모두 맨 아래에 온다
                roomList
            } else {
                Text("방에 없습니다 — 나만 보입니다")
                Button("방 만들기…") { createRoom() }
                roomList
            }
            Divider()
            Button("내 캐릭터…") { openCharacterPicker() }
            Button("내 이름 변경…") { changeName() }
            if Presence.shared.otherVersions > 0 {
                Divider()
                Text("버전이 다른 동료 \(Presence.shared.otherVersions)명은 보이지 않습니다")
                Text("모두 같은 버전을 설치해야 합니다")
            }
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        } label: {
            // 배포본과 함께 떠 있을 때 열어 보지 않고 구분되어야 한다
            #if DEBUG
            Image(systemName: "hammer.fill")
            #else
            Image("MenuBarIcon")
            #endif
        }
    }

    /// 들어가 있어도 다른 방으로 바로 옮길 수 있어야 한다. 나갔다 다시 들어오게 하지 않는다.
    /// 이름은 한 가지로 둔다 — 방 만들기 안내문이 이 이름을 그대로 부른다
    private var roomList: some View {
        Menu("방 참여하기") {
            if Presence.shared.rooms.isEmpty {
                Text("보이는 방이 없습니다")
            }
            ForEach(Presence.shared.rooms) { room in
                let here = room.id == World.myRoom
                let full = room.count >= Limits.maxRoomMembers
                let mark = here ? " · 현재 방" : full ? " · 정원" : ""
                Button("\(room.label)  \(room.count)명\(mark)") {
                    World.join(room: room.id, name: room.name)
                }
                .disabled(here || full)
            }
        }
    }

    /// 방은 만들 때마다 새로 생긴다. 이름이 같아도 다른 방이다.
    /// 방에 없을 때만 메뉴에 나온다
    private func createRoom() {
        let alert = NSAlert()
        alert.messageText = "방 만들기"
        alert.informativeText = "동료는 메뉴의 방 참여하기에서 이 방을 고르면 됩니다."
        alert.addButton(withTitle: "만들기")
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 220, height: 24))
        // 지금 방 이름을 채워 두면 이름만 고치는 창으로 보인다. 실제로는 새 방이다
        field.placeholderString = "방 이름"
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = sanitizeRoom(field.stringValue)
        guard !name.isEmpty else { return }
        World.join(room: newRoomID(), name: name)
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

/// 방에 다 찼다고 호스트가 알려 왔다. 이미 방에서 나온 뒤다
func tellRoomIsFull() {
    let alert = NSAlert()
    alert.messageText = "방이 가득 찼습니다"
    alert.informativeText = "한 방에는 \(Limits.maxRoomMembers)명까지 들어갈 수 있습니다."
    alert.addButton(withTitle: "확인")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}

#if DEBUG
/// 잠금·절전 뒤 어느 층이 멈추는지 보려고 둔다. 배포본에는 들어가지 않는다
private let watch = Logger(subsystem: "offiky", category: "watch")
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        OverlayController.shared.start()
        Session.shared.start()
        // 테스트 호스트로 켜지면 망에 나가지 않는다. 실제 방에 참가자로 뜨고 호스트 판정까지 바뀐다
        if NSClassFromString("XCTestCase") == nil { Net.shared.start() }
        ChatPanel.shared.install()
        Control.shared.install()
        Task { await UpdateChecker.shared.check() }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { await UpdateChecker.shared.check() }
        }

        #if DEBUG
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let overlay = OverlayController.shared
            let age = ProcessInfo.processInfo.systemUptime - World.shared.lastTick
            watch.info("me=\(World.shared.myID, privacy: .public) host=\(Session.shared.hostPeer ?? "-", privacy: .public) amHost=\(Presence.shared.amHost) screens=\(NSScreen.screens.count) windows=\(overlay.windows.count) visible=\(overlay.windows.filter(\.isVisible).count) scenes=\(overlay.scenes.count) tickAge=\(age, format: .fixed(precision: 1)) peers=\(World.shared.peers.count) count=\(Presence.shared.count)")
        }
        #endif

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { _ in Net.shared.stop() }
        center.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { _ in
            Net.shared.start()
            OverlayController.shared.rebuild()
        }
    }
}
