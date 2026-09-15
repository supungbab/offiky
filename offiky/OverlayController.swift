import AppKit
import SpriteKit

final class OverlayController {
    static let shared = OverlayController()

    private(set) var windows: [NSWindow] = []
    private(set) var scenes: [CharacterScene] = []
    private(set) var strip = FloorStrip(visibleFrames: [])
    private var timer: Timer?
    private var handle: NSWindow?

    private init() {}

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { _ in
            World.shared.tick(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    func setHidden(_ hidden: Bool) {
        windows.forEach { $0.setIsVisible(!hidden) }
        handle?.setIsVisible(!hidden)
    }

    /// 오버레이가 표시 전용이라 내 캐릭터 위에 겹쳐 두고 드래그를 받는다.
    func moveHandle(toGlobal point: CGPoint) {
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
        handle?.setFrameOrigin(CGPoint(x: point.x - spriteDisplaySize / 2,
                                       y: point.y - spriteDisplaySize / 2))
    }

    @objc private func screensChanged() { rebuild() }

    func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        scenes.removeAll()

        let frames = NSScreen.screens
            .map(\.visibleFrame)
            .sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }

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
            view.preferredFramesPerSecond = 24
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

        strip = FloorStrip(visibleFrames: frames)
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
