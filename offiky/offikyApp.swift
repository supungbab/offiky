import SwiftUI

@main
struct offikyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var hidden = false

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
            Button("참가자 \(Presence.shared.count)명…") { openRoster() }
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
        Control.shared.install()
        Task { await UpdateChecker.shared.check() }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { await UpdateChecker.shared.check() }
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { _ in Mesh.shared.stop() }
        center.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { _ in Mesh.shared.start() }
    }
}
