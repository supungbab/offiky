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
    /// W 로 연 물건 선택 창에서 선택된 번호. 닫혀 있으면 nil
    private(set) var picking: Int?

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
        picking = nil
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
        if let selected = picking {
            switch code {
            case kVK_Escape: closePicker()
            case kVK_ANSI_W, kVK_Return, kVK_ANSI_KeypadEnter: if !event.isARepeat { pick(selected) }
            case kVK_LeftArrow: picking = PropPicker.move(selected, dx: -1)
            case kVK_RightArrow: picking = PropPicker.move(selected, dx: 1)
            case kVK_UpArrow: picking = PropPicker.move(selected, dy: -1)
            case kVK_DownArrow: picking = PropPicker.move(selected, dy: 1)
            default: break
            }
            return
        }
        switch code {
        case kVK_Escape:
            stop()
        case kVK_UpArrow:
            if !event.isARepeat { World.shared.me.jump() }
        case kVK_ANSI_W:
            if !event.isARepeat { openPicker() }
        case kVK_ANSI_B:
            if !event.isARepeat { World.shared.me.toggleRide() }
        case kVK_ANSI_Z:
            if !event.isARepeat { World.shared.me.cycleWeapon() }
        case kVK_ANSI_X:
            if World.shared.me.isFishing { if !event.isARepeat { World.shared.strike() } } else { World.shared.fire() }
        case kVK_ANSI_C:
            if !event.isARepeat { World.shared.me.toggleDance() }
        case kVK_ANSI_F:
            if !event.isARepeat { World.shared.me.toggleFishing(now: ProcessInfo.processInfo.systemUptime) }
        case kVK_Space:
            World.shared.me.isThrusting = true
        case kVK_DownArrow:
            World.shared.me.isBowing = true
        case kVK_LeftArrow, kVK_RightArrow:
            guard !event.isARepeat else { return }
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

    /// 고르는 동안 방향키는 칸을 옮기므로 걷던 것을 멈춘다
    private func openPicker() {
        guard World.shared.me.canWork else { return }
        pressed.removeAll()
        dashing = false
        World.shared.me.hold(0, dash: false)
        picking = World.shared.me.prop
        fitPanel()
    }

    func pick(_ prop: Int) {
        World.shared.me.startWorking(as: prop)
        closePicker()
    }

    private func closePicker() {
        picking = nil
        fitPanel()
    }

    /// 아래 변은 그대로 두고 위로 늘린다
    private func fitPanel() {
        guard let panel, let screen = panel.screen else { return }
        let size = picking == nil ? hintSize : pickerSize
        panel.setFrame(CGRect(origin: panelOrigin(on: screen, width: size.width), size: size), display: true)
    }
}

/// 안내를 두 줄로 나눠 채팅창과 같은 폭에 넣는다
private let hintSize = CGSize(width: panelSize.width, height: 64)
private let pickerSize = NSHostingView(rootView: PropPicker(selected: 0)).fittingSize

/// 처리하지 않은 키는 경고음이 나므로 방향키 외에도 모두 받는다
private final class KeyCatcher: NSHostingView<HintView> {
    required init(rootView: HintView) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { Control.shared.keyDown(event) }
}

struct HintView: View {
    var body: some View {
        if let selected = Control.shared.picking { PropPicker(selected: selected) } else { hints }
    }

    /// 윗줄은 움직임, 아랫줄은 하는 일이다. 같은 간격으로 늘어놓으면 순서대로 다 읽어야 해서 묶는다
    private var hints: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                HStack(spacing: 10) { item("← →", "이동"); item("←← →→", "대시") }
                HStack(spacing: 10) {
                    item("↑", "점프"); item("↑↑", "2단 점프"); item("space", "제트팩"); item("↓", "웅크리기·낙하산")
                }
            }
            HStack(spacing: 16) {
                HStack(spacing: 10) { item("z", "무기 바꾸기"); item("x", "공격·챔질"); item("c", "춤"); item("f", "낚시") }
                HStack(spacing: 10) { item("⇧↓", "1초 똥"); item("w", "WORK"); item("b", "오토바이") }
                item("esc", "끝내기")
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panelSurface()
    }
}

/// 묶음마다 새 줄에서 시작한다. 물건은 실제 화면과 같은 2배로 그린다
struct PropPicker: View {
    let selected: Int

    static let columns = 12
    static let sections: [(title: String, rows: [[Int]])] = {
        var start = 0
        return Characters.propGroups.map { group in
            let indices = Array(start..<start + group.names.count)
            start += group.names.count
            return (group.title, stride(from: 0, to: indices.count, by: columns).map {
                Array(indices[$0..<min($0 + columns, indices.count)])
            })
        }
    }()
    static let rows = sections.flatMap(\.rows)

    /// 좌우는 번호 순으로 줄을 넘어가고, 위아래는 같은 칸이 없으면 그 줄의 끝으로 간다
    static func move(_ selected: Int, dx: Int = 0, dy: Int = 0) -> Int {
        guard let row = rows.firstIndex(where: { $0.contains(selected) }) else { return 0 }
        if dx != 0 { return min(max(selected + dx, 0), Characters.props.count - 1) }
        let target = rows[min(max(row + dy, 0), rows.count - 1)]
        return target[min(selected - rows[row][0], target.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.sections, id: \.title) { section in
                Text(section.title).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(section.rows, id: \.self) { row in
                    HStack(spacing: 6) { ForEach(row, id: \.self, content: cell) }
                }
            }
            HStack(spacing: 10) { item("← → ↑ ↓", "고르기"); item("w · return", "정하기"); item("esc", "닫기") }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .font(.system(size: 11))
        .padding(16)
        .frame(width: hintSize.width)
        .frame(maxHeight: .infinity)
        .panelSurface()
    }

    private func cell(_ index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8).inset(by: -3)
        return Button { Control.shared.pick(index) } label: {
            Image(Characters.propNames[index]).interpolation(.none).resizable().frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(index == selected ? Color.accentColor.opacity(0.2) : .clear, in: shape)
        .overlay { if index == selected { shape.strokeBorder(Color.accentColor, lineWidth: 2) } }
    }
}

/// 키캡에 고정폭 글꼴을 쓰면 코드처럼 보인다
private func item(_ key: String, _ label: String) -> some View {
    HStack(spacing: 5) {
        Text(key).fixedSize().padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        Text(label).fixedSize().foregroundStyle(.secondary)
    }
}
