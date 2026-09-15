import AppKit
import SpriteKit

final class OverlayController {
    static let shared = OverlayController()

    private(set) var windows: [NSWindow] = []
    private(set) var scenes: [SKScene] = []

    private init() {}

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
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
            view.preferredFramesPerSecond = 12
            let scene = SKScene(size: frame.size)
            scene.backgroundColor = .clear
            scene.scaleMode = .resizeFill
            view.presentScene(scene)

            window.contentView = view
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()

            windows.append(window)
            scenes.append(scene)
        }
    }
}
