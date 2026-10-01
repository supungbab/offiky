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
            if Presence.shared.otherVersions > 0 {
                Text("버전이 다른 동료 \(Presence.shared.otherVersions)명은 보이지 않습니다")
                Text("모두 최신 버전으로 업데이트하면 보입니다")
            }
            Divider()
            Button("채팅 열기  ⌥F") { ChatPanel.shared.show() }
            if !ChatPanel.shared.hotKeyWorks {
                Text("⌥F 를 다른 앱이 쓰고 있습니다")
            }
            Button(Control.shared.isOn ? "조종 끝내기  esc" : "캐릭터 조종  ⌥D") {
                Control.shared.toggle()
            }
            .disabled(OverlayController.shared.isHidden)
            if !Control.shared.hotKeyWorks {
                Text("⌥D 를 다른 앱이 쓰고 있습니다")
            }
            Divider()
            channelList
            Button("참가자 \(Presence.shared.count)명…") { openRoster() }
            Divider()
            Button("내 캐릭터…") { openCharacterPicker() }
            Button("내 이름 변경…") { changeName() }
            Divider()
            Button(OverlayController.shared.isHidden ? "캐릭터 보이기" : "캐릭터 숨기기") {
                OverlayController.shared.toggleHidden()
            }
            Button("종료") { NSApplication.shared.terminate(nil) }
        } label: {
            // 배포본과 함께 떠 있을 때 열어 보지 않고 구분되어야 한다
            #if DEBUG
            Image(systemName: "hammer.fill")
            #else
            // 새 버전이 있으면 아이콘에 빨간 점이 붙는다. 메뉴를 열지 않아도 보인다
            if let icon = Characters.menuBarIcon(hasUpdate: UpdateChecker.shared.newVersion != nil) {
                Image(nsImage: icon)
            } else {
                Image("MenuBarIcon")
            }
            #endif
        }
    }

    private var channelList: some View {
        Menu("\(Presence.shared.channel)채널") {
            ForEach(1...Limits.channels, id: \.self) { channel in
                let here = channel == Presence.shared.channel
                // 현재 채널은 참가자 메뉴와 같은 숫자를 쓴다. 광고 수는 연결된 수와 다를 수 있다
                let count = here ? Presence.shared.count : Presence.shared.channelCounts[channel, default: 0]
                let full = !here && count >= Limits.maxChannelMembers
                let mark = here ? " · 현재" : full ? " · 정원" : ""
                Button("\(channel)채널\(count > 0 ? "  \(count)명" : "")\(mark)") {
                    World.join(channel: channel)
                }
                .disabled(here || full)
            }
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

#if DEBUG
/// 잠금·절전 뒤 어느 층이 멈추는지 보려고 둔다. 배포본에는 들어가지 않는다
private let watch = Logger(subsystem: "offiky", category: "watch")

/// `-bot YES` 로 활성화하면 사람처럼 걷고 서고 뛴다. 두 인스턴스로 원격 캐릭터를 눈으로 비교할 때 쓴다
private final class Bot {
    static let shared = Bot()
    private var until: TimeInterval = 0

    func start() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func step() {
        let me = World.shared.me
        let now = ProcessInfo.processInfo.systemUptime
        let strip = World.shared.strip
        // 끝에 닿으면 돌아선다
        if me.x < 80 { me.hold(1, dash: false); until = now + .random(in: 1...3) }
        if me.x > strip.length - 80 { me.hold(-1, dash: false); until = now + .random(in: 1...3) }
        guard now >= until else { return }
        me.isBowing = false
        let direction: CGFloat = Bool.random() ? 1 : -1
        switch Int.random(in: 0..<10) {
        case 0...3: me.hold(direction, dash: false); until = now + .random(in: 0.8...3)
        case 4...5: me.hold(0, dash: false); until = now + .random(in: 0.5...2.5)
        case 6:     me.hold(direction, dash: true); until = now + .random(in: 0.4...1.2)
        case 7:     me.jump(); if Bool.random() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { me.jump() } }
                    until = now + .random(in: 0.6...1.2)
        case 8:     me.hold(0, dash: false); me.isBowing = true; until = now + .random(in: 0.5...1.5)
        default:    me.hold(-me.facing, dash: false); until = now + .random(in: 0.3...1)
        }
    }
}
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// App Nap 이 타이머를 늦추면 생존 신호가 끊겨 동료 화면에서 내가 사라진 것으로 판정된다
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "좌표 생존 신호")
        OverlayController.shared.start()
        Session.shared.start()
        // 테스트 호스트로 켜지면 망에 나가지 않는다. 실제 채널에 참가자로 뜬다
        if NSClassFromString("XCTestCase") == nil { Net.shared.start() }
        ChatPanel.shared.install()
        Control.shared.install()
        Task { await UpdateChecker.shared.check() }
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { await UpdateChecker.shared.check() }
        }
        let sweep = Timer(timeInterval: 0.25, repeats: true) { _ in
            World.shared.sweepPeers(now: ProcessInfo.processInfo.systemUptime)
        }
        RunLoop.main.add(sweep, forMode: .common)

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "bot") { Bot.shared.start() }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let overlay = OverlayController.shared
            let age = ProcessInfo.processInfo.systemUptime - World.shared.lastTick
            watch.info("me=\(World.shared.myID, privacy: .public) screens=\(NSScreen.screens.count) windows=\(overlay.windows.count) visible=\(overlay.windows.filter(\.isVisible).count) scenes=\(overlay.scenes.count) tickAge=\(age, format: .fixed(precision: 1)) peers=\(World.shared.peers.count) count=\(Presence.shared.count)")
        }
        #endif

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { _ in Net.shared.stop() }
        center.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { _ in
            Net.shared.start()
            OverlayController.shared.rebuild()
            // 밤새 나온 버전을 맥을 열자마자 알린다. 깨어난 직후에는 Wi-Fi 가 아직 연결되지 않았다
            Task {
                try? await Task.sleep(for: .seconds(10))
                await UpdateChecker.shared.check()
            }
        }
    }
}
