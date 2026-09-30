import AppKit
import SpriteKit

@Observable final class OverlayController {
    static let shared = OverlayController()

    private(set) var windows: [NSWindow] = []
    private(set) var scenes: [SKScene] = []
    private var links: [CADisplayLink] = []
    private(set) var strip = FloorStrip(visibleFrames: [], main: nil)
    private var handle: NSWindow?
    private var handleMovedAt: TimeInterval = 0
    /// 내 화면에서만 숨긴다. 좌표는 계속 보내므로 동료 화면에는 그대로 보인다
    private(set) var isHidden = false

    private init() {}

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// 씬 update 는 화면이 깨어난 뒤 SpriteKit 시계가 앞서 있는 동안 몇 분씩 건너뛰어진다
    @objc private func displayFrame(_ link: CADisplayLink) {
        World.shared.tick(now: ProcessInfo.processInfo.systemUptime)
    }

    /// 오버레이가 표시 전용이라 내 캐릭터 위에 겹쳐 두고 드래그를 받는다.
    /// 클릭만 받으면 되므로 캐릭터를 매 프레임 따라갈 이유가 없다. 창을 옮길 때마다
    /// 윈도우 서버와 왕복이 생겨서, 60fps 로 부르면 그것만으로 CPU 의 3할을 쓴다.
    /// 12Hz 면 가장 빠른 대시(90pt/s)에서도 7.5pt 뒤처지는데 핸들이 40pt 라 덮고 남는다.
    /// 드래그 중에는 눌린 창이 커서를 계속 따라가므로 뒤처져도 끊기지 않는다.
    func moveHandle(toGlobal point: CGPoint, now: TimeInterval) {
        guard now - handleMovedAt >= 1.0 / 12 else { return }
        handleMovedAt = now
        let size = CGSize(width: spriteDisplaySize, height: spriteDisplaySize)
        if handle == nil {
            let window = NSWindow(contentRect: CGRect(origin: point, size: size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.contentView = DragHandleView()
            if !isHidden { window.orderFrontRegardless() }
            handle = window
        }
        let origin = CGPoint(x: point.x - spriteDisplaySize / 2,
                             y: point.y - spriteDisplaySize / 2)
        guard handle?.frame.origin != origin else { return }
        handle?.setFrameOrigin(origin)
    }

    func toggleHidden() {
        isHidden.toggle()
        if isHidden { Control.shared.stop() }
        for window in windows + [handle].compactMap({ $0 }) {
            if isHidden { window.orderOut(nil) } else { window.orderFrontRegardless() }
        }
    }

    @objc private func screensChanged() { rebuild() }

    /// 절전 전환 중 0개로 보고되는 목록으로 창을 지우면 되살릴 계기가 남지 않는다
    func rebuild(frames: [CGRect] = NSScreen.screens.map(\.visibleFrame)) {
        guard !frames.isEmpty else { return }
        let built = FloorStrip(visibleFrames: frames, main: frames.first)
        // 깨어날 때 연달아 호출될 때마다 SKView 를 해제하면 SpriteKit display link 큐가 해제된 뷰를 release 해 크래시한다
        guard built.frames != strip.frames || windows.isEmpty else { return }
        for window in windows {
            (window.contentView as? SKView)?.isPaused = true
            (window.contentView as? SKView)?.presentScene(nil)
            window.orderOut(nil)
        }
        windows.removeAll()
        scenes.removeAll()
        links.forEach { $0.invalidate() }
        links.removeAll()

        for frame in built.frames {
            let window = NSWindow(contentRect: frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true   // 표시 전용. 드래그는 별도 윈도우가 받는다

            let view = SKView(frame: CGRect(origin: .zero, size: frame.size))
            view.allowsTransparency = true
            view.preferredFramesPerSecond = 30
            let scene = SKScene(size: frame.size)
            scene.backgroundColor = .clear
            scene.scaleMode = .resizeFill
            view.presentScene(scene)

            window.contentView = view
            window.setFrame(frame, display: true)
            if !isHidden { window.orderFrontRegardless() }

            let link = view.displayLink(target: self, selector: #selector(displayFrame))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)

            windows.append(window)
            scenes.append(scene)
            links.append(link)
        }

        strip = built
        World.shared.attach(scenes: scenes, strip: strip)
    }
}

final class DragHandleView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 완전히 비어 있으면 hit-test 대상이 되지 않는다.
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.01).setFill()
        dirtyRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        World.shared.me.beginDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        guard World.shared.me.isDragging else { return }
        World.shared.updateDrag(toGlobal: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard World.shared.me.isDragging else { return }
        World.shared.me.endDrag()
    }
}
