import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 방향키로 캐릭터를 조종한다. 켜는 동안만 키를 받는다.
@Observable final class Control {
    static let shared = Control()

    private var panel: KeyPanel?
    private var hotKey: HotKey?
    private var focus = FocusReturn()
    /// 눌려 있는 방향키. 마지막에 누른 쪽으로 간다
    private var pressed: [Int] = []
    private var lastTap: (code: Int, at: TimeInterval) = (0, 0)
    private var dashing = false

    private(set) var isOn = false
    private(set) var hotKeyWorks = true

    private init() {}

    /// 같은 조합을 다른 앱이 먼저 잡고 있으면 등록에 실패한다
    func install() {
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_D),
                        modifiers: UInt32(optionKey)) { [weak self] in
            self?.toggle()
        }
        hotKeyWorks = hotKey?.registered ?? false
        // ⌘ 를 누른 채 뗀 키는 AppKit 이 창에 keyUp 을 보내지 않는다
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            self.keyUp(event)
            return nil
        }
    }

    func toggle() { isOn ? stop() : start() }

    func start() {
        guard !OverlayController.shared.isHidden, let screen = screenUnderMouse() else { return }
        // 다른 곳을 클릭하면 조종을 끝낸다
        let panel = self.panel ?? KeyPanel.floating { [weak self] in
            self?.stop(restoringFocus: false)
        }
        if self.panel == nil {
            panel.contentView = KeyCatcher(rootView: HintView())
            self.panel = panel
        }

        focus.remember()
        isOn = true
        panel.setFrame(CGRect(origin: panelOrigin(on: screen, width: hintSize.width),
                              size: hintSize), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
    }

    func stop(restoringFocus: Bool = true) {
        guard isOn else { return }
        isOn = false
        pressed.removeAll()
        dashing = false
        World.shared.me.isBowing = false
        World.shared.me.isThrusting = false
        World.shared.me.hold(0, dash: false)
        panel?.orderOut(nil)
        focus.restore(restoringFocus)
    }

    /// 같은 방향을 빠르게 두 번 누르면 대시한다
    static let doubleTapWindow: TimeInterval = 0.3

    fileprivate func keyDown(_ event: NSEvent) {
        let code = Int(event.keyCode)
        switch code {
        case kVK_Escape:
            stop()
        case kVK_UpArrow:
            if !event.isARepeat { World.shared.me.jump() }
        case kVK_ANSI_W:
            World.shared.me.startWorking()
        case kVK_Space:
            World.shared.me.isThrusting = true
        case kVK_DownArrow:
            World.shared.me.isBowing = true
        case kVK_LeftArrow, kVK_RightArrow:
            guard !event.isARepeat else { return }
            if World.shared.me.isWorking {
                World.shared.me.cycleProp(code == kVK_LeftArrow ? -1 : 1)
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            dashing = code == lastTap.code && now - lastTap.at < Control.doubleTapWindow
            lastTap = (code, now)
            pressed.removeAll { $0 == code }
            pressed.append(code)
            apply()
        default:
            break
        }
    }

    fileprivate func keyUp(_ event: NSEvent) {
        let code = Int(event.keyCode)
        if code == kVK_DownArrow { World.shared.me.isBowing = false; return }
        if code == kVK_Space { World.shared.me.isThrusting = false; return }
        guard code == kVK_LeftArrow || code == kVK_RightArrow else { return }
        pressed.removeAll { $0 == code }
        if pressed.isEmpty { dashing = false }
        apply()
    }

    private func apply() {
        guard let code = pressed.last else {
            World.shared.me.hold(0, dash: false)
            return
        }
        World.shared.me.hold(code == kVK_LeftArrow ? -1 : 1, dash: dashing)
    }
}

/// 안내 항목이 아홉 개라 채팅창보다 넓다
private let hintSize = CGSize(width: 760, height: panelSize.height)

/// 처리하지 않은 키는 경고음이 나므로 방향키 외에도 모두 받는다
private final class KeyCatcher: NSHostingView<HintView> {
    required init(rootView: HintView) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { Control.shared.keyDown(event) }
}

struct HintView: View {
    /// 이동·점프·그 외로 묶는다. 같은 간격의 아홉 개는 순서대로 다 읽어야 한다
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) { item("← →", "이동"); item("←← →→", "대시") }
            HStack(spacing: 10) { item("↑", "점프"); item("↑↑", "2단 점프"); item("space", "제트팩") }
            HStack(spacing: 10) {
                item("↓", "웅크리기·낙하산"); item("⇧↓", "1초 똥"); item("w", "WORK"); item("esc", "끝내기")
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panelSurface()
    }

    /// 키캡에 고정폭 글꼴을 쓰면 코드처럼 보인다
    private func item(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).fixedSize().padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            Text(label).fixedSize().foregroundStyle(.secondary)
        }
    }
}
