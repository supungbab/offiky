import AppKit
import SpriteKit

final class OverlayController {
    static let shared = OverlayController()

    private(set) var windows: [NSWindow] = []
    private(set) var scenes: [CharacterScene] = []
    private(set) var strip = FloorStrip(visibleFrames: [], main: nil)
    private var handle: NSWindow?
    private var handleMovedAt: TimeInterval = 0

    private init() {}

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
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
            window.orderFrontRegardless()
            handle = window
        }
        let origin = CGPoint(x: point.x - spriteDisplaySize / 2,
                             y: point.y - spriteDisplaySize / 2)
        guard handle?.frame.origin != origin else { return }
        handle?.setFrameOrigin(origin)
    }

    @objc private func screensChanged() { rebuild() }

    func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        scenes.removeAll()

        let screens = NSScreen.screens
        let built = FloorStrip(visibleFrames: screens.map(\.visibleFrame),
                               main: screens.first?.visibleFrame)
        let frames = built.frames

        for frame in frames {
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
            let scene = CharacterScene(size: frame.size)
            scene.backgroundColor = .clear
            scene.scaleMode = .resizeFill
            view.presentScene(scene)

            window.contentView = view
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()

            windows.append(window)
            scenes.append(scene)
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
        World.shared.beginDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        guard World.shared.me.isDragging else { return }
        World.shared.updateDrag(toGlobal: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard World.shared.me.isDragging else { return }
        World.shared.endDrag()
    }
}
