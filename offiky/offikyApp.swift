import SwiftUI

@main
struct offikyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var hidden = false
    #if DEBUG
    @State private var showCoords = false
    #endif

    var body: some Scene {
        MenuBarExtra {
            Text("offiky \(appVersion)")
            Divider()
            Button("채팅 열기  ⌥T") { ChatPanel.shared.show() }
            Button("참가자 \(World.shared.roster().count)명…") { openRoster() }
            Button("내 캐릭터…") { openCharacterPicker() }
            Button("내 이름 변경…") { changeName() }
            Toggle("캐릭터 숨기기", isOn: binding($hidden) {
                OverlayController.shared.setHidden($0)
            })
            if Mesh.shared.otherVersionCount > 0 {
                Divider()
                Text("버전이 다른 동료 \(Mesh.shared.otherVersionCount)명은 보이지 않습니다")
                Text("모두 같은 버전을 설치해야 합니다")
            }
            #if DEBUG
            Divider()
            Toggle("테스트: 좌표 표시", isOn: binding($showCoords) {
                World.shared.showCoordinates($0)
            })
            Button("테스트: 50마리 풀기") { World.shared.spawnTestPeers(50) }
            Button("테스트 캐릭터 제거") { World.shared.removeTestPeers() }
            #endif
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        } label: {
            Image("MenuBarIcon")
        }
    }

    /// 버전이 다르면 서로 보이지 않으므로 동료끼리 대조할 수 있어야 한다
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return build == short ? short : "\(short) (\(build))"
    }

    /// 메뉴가 닫혀 있으면 뷰가 갱신되지 않아 onChange 가 다음 열 때까지 미뤄진다.
    /// setter 에서 바로 실행한다.
    private func binding(_ source: Binding<Bool>,
                         perform: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { source.wrappedValue },
                set: { source.wrappedValue = $0; perform($0) })
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
