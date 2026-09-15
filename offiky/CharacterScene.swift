import AppKit
import SpriteKit

final class CharacterNode: SKNode {
    let id: String
    let isLocal: Bool
    var displayName: String

    var x: CGFloat = 0
    var y: CGFloat = 0
    var anchorX: CGFloat = 0

    var isDragging = false

    private let image = SKSpriteNode()
    private let shadow = SKSpriteNode(texture: CharacterNode.shadowTexture)
    private let label = SKLabelNode(fontNamed: "Helvetica")
    private var nameBackground: SKShapeNode?
    private var renderedName: String?

    private var verticalSpeed: CGFloat = 0
    private var walkTarget: CGFloat = 0
    private var nextWalkAt: TimeInterval = 0
    private var nextJumpAt: TimeInterval = 0
    private var isWalking = false
    /// 이동 방향. +1 오른쪽, -1 왼쪽
    private var facing: CGFloat = -1

    private var bobPhase: CGFloat = 0
    private var walkPhase: TimeInterval = 0
    private var wasAirborne = false

    private var fromX: CGFloat = 0, fromY: CGFloat = 0
    private var toX: CGFloat = 0, toY: CGFloat = 0
    private var interpolatedFor: TimeInterval = 0
    private static let interpolationDuration: TimeInterval = 0.5
    static let gravity: CGFloat = 1100
    static let jumpApex: CGFloat = 48

    init(id: String, name: String, isLocal: Bool) {
        self.id = id
        self.displayName = name
        self.isLocal = isLocal
        super.init()

        shadow.size = CGSize(width: spriteDisplaySize,
                             height: spriteDisplaySize * 5 / 16)
        shadow.zPosition = -2
        addChild(shadow)

        image.size = CGSize(width: spriteDisplaySize, height: spriteDisplaySize)
        addChild(image)

        label.fontSize = 10
        label.fontColor = .white
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: 0, y: spriteDisplaySize / 2 + 2)
        addChild(label)

        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    private var frames: [SKTexture] = []

    func apply(_ sprites: [Sprite]) {
        frames = sprites.compactMap { sprite in
            guard let cg = sprite.cgImage() else { return nil }
            let texture = SKTexture(cgImage: cg)
            texture.filteringMode = .nearest
            return texture
        }
        image.texture = frames.first
    }

    func setRemoteTarget(x newX: CGFloat, y newY: CGFloat) {
        fromX = x; fromY = y
        toX = newX; toY = newY
        interpolatedFor = 0
    }

    func update(dt: TimeInterval, now: TimeInterval, strip: FloorStrip) {
        if isLocal {
            simulate(dt: dt, now: now, strip: strip)
        } else {
            interpolate(dt: dt)
        }
        detectLanding()
        bobPhase += CGFloat(dt) * (isWalking ? 9 : 2)

        if frames.count > 1 {
            walkPhase += isWalking ? dt : 0
            image.texture = frames[Int(walkPhase * 6) % frames.count]
        }
    }

    private func simulate(dt: TimeInterval, now: TimeInterval, strip: FloorStrip) {
        if isDragging { isWalking = false; return }

        if y > 0 || verticalSpeed != 0 {
            // 정수 적분은 12fps 에서 정점이 목표의 절반으로 줄어든다
            let step = CGFloat(dt)
            y += verticalSpeed * step - 0.5 * CharacterNode.gravity * step * step
            verticalSpeed -= CharacterNode.gravity * step
            if y <= 0 { y = 0; verticalSpeed = 0 }
            isWalking = false
            return
        }

        if nextJumpAt == 0 { nextJumpAt = now + Double.random(in: 30...90) }
        if now >= nextJumpAt {
            nextJumpAt = now + Double.random(in: 30...90)
            verticalSpeed = (2 * CharacterNode.gravity * CharacterNode.jumpApex).squareRoot()
            return
        }

        if now >= nextWalkAt {
            nextWalkAt = now + Double.random(in: 3...9)
            walkTarget = strip.clampToWall(anchorX + CGFloat.random(in: -150...150))
        }
        let delta = walkTarget - x
        if abs(delta) < 1 {
            isWalking = false
        } else {
            isWalking = true
            facing = delta > 0 ? 1 : -1
            x = strip.clampToWall(x + facing * 20 * CGFloat(dt))
        }
    }

    private func interpolate(dt: TimeInterval) {
        interpolatedFor = min(CharacterNode.interpolationDuration, interpolatedFor + dt)
        let t = CGFloat(interpolatedFor / CharacterNode.interpolationDuration)
        x = fromX + (toX - fromX) * t
        y = fromY + (toY - fromY) * t
        isWalking = abs(toX - fromX) > 1
        if isWalking { facing = toX > fromX ? 1 : -1 }
    }

    private func detectLanding() {
        let airborne = y > 0
        if wasAirborne && !airborne {
            if isLocal { World.shared.commitAnchor() }
            (scene as? CharacterScene)?.spawnDust(at: position, speed: abs(verticalSpeed))
            image.run(.sequence([
                .scaleY(to: 0.85, duration: 0.05),
                .scaleY(to: 1.0, duration: 0.08),
            ]))
        }
        wasAirborne = airborne
    }

    /// bob 은 position 에만 더한다. y 에 섞으면 걸음마다 착지 먼지가 인다.
    func render(placement: Placement) {
        let bob: CGFloat = sin(bobPhase) > 0 ? 2 : 0
        position = CGPoint(x: placement.point.x, y: placement.point.y + bob)

        // 그림자는 캐릭터를 따라 뜨지 않고 바닥에 남는다
        let lift = y + bob
        shadow.position = CGPoint(x: 0, y: -lift - spriteDisplaySize / 2 + 3)
        let height = min(1, y / 120)
        shadow.setScale(1 - 0.45 * height)
        shadow.alpha = 0.3 * (1 - 0.75 * height)
        zPosition = x + CGFloat(stableHash(id) % 997) / 1000
        // 기본 캐릭터는 왼쪽을 보고 그려져 있다
        image.xScale = -facing
        updateNameLabel()
    }

    static let shadowTexture: SKTexture = {
        let rows = [
            "....########....",
            ".##############.",
            "################",
            ".##############.",
            "....########....",
        ]
        let width = 16, height = rows.count
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() where character == "#" {
                pixels[(y * width + x) * 4 + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }()

    /// 이름이 바뀔 때만 배경을 다시 만든다
    private func updateNameLabel() {
        guard renderedName != displayName else { return }
        renderedName = displayName
        label.text = displayName

        nameBackground?.removeFromParent()
        let size = CGSize(width: label.frame.width + 8, height: label.frame.height + 4)
        let background = SKShapeNode(rectOf: size, cornerRadius: 3)
        background.fillColor = NSColor(white: 0, alpha: 0.55)
        background.strokeColor = .clear
        background.zPosition = -1
        background.position = CGPoint(x: 0, y: label.position.y + label.frame.height / 2)
        addChild(background)
        nameBackground = background
    }
}

extension CharacterNode {
    func showBubble(text: String) {
        childNode(withName: "bubble")?.removeFromParent()

        let label = SKLabelNode(fontNamed: "Helvetica")
        label.text = text
        label.fontSize = 11
        label.fontColor = .black
        label.numberOfLines = 3
        label.preferredMaxLayoutWidth = 200
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        let padding: CGFloat = 6
        let size = CGSize(width: min(200, label.frame.width) + padding * 2,
                          height: max(label.frame.height, 12) + padding * 2)
        let bubble = SKShapeNode(rectOf: size, cornerRadius: 4)
        bubble.name = "bubble"
        bubble.fillColor = .white
        bubble.strokeColor = .black
        bubble.lineWidth = 1
        bubble.zPosition = 1
        bubble.position = CGPoint(x: 0, y: spriteDisplaySize / 2 + 16 + size.height / 2)
        bubble.addChild(label)
        addChild(bubble)

        bubble.run(.sequence([.wait(forDuration: 5), .removeFromParent()]))
    }

    func clampBubble(sceneWidth: CGFloat) {
        guard let bubble = childNode(withName: "bubble") as? SKShapeNode else { return }
        let half = bubble.frame.width / 2
        if position.x - half < 0 {
            bubble.position.x = half - position.x
        } else if position.x + half > sceneWidth {
            bubble.position.x = sceneWidth - half - position.x
        } else {
            bubble.position.x = 0
        }
    }
}

final class CharacterScene: SKScene {

    func spawnDust(at point: CGPoint, speed: CGFloat) {
        let count = min(6, max(4, Int(speed / 400)))
        let rgb = Palette.dust
        let color = NSColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)

        for _ in 0..<count {
            let dot = SKSpriteNode(color: color, size: CGSize(width: 2, height: 2))
            dot.position = CGPoint(x: point.x, y: point.y - spriteDisplaySize / 2)
            dot.alpha = 0.7
            dot.zPosition = 10_000
            addChild(dot)
            dot.run(.sequence([
                .group([
                    .moveBy(x: CGFloat.random(in: -16...16), y: CGFloat.random(in: 2...8),
                            duration: 0.3),
                    .fadeOut(withDuration: 0.3),
                ]),
                .removeFromParent(),
            ]))
        }
    }
}

final class World {
    static let shared = World()

    /// 이 실행에서만 유효하다. 호스트 선출 기준이자 seq 의 짝이다.
    let myID = UUID().uuidString

    /// 외형과 첫 위치를 정한다. myID 에 묶으면 실행할 때마다 색이 바뀐다.
    static let installID: String = {
        let key = "installID"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    private(set) var me: CharacterNode
    private(set) var peers: [String: CharacterNode] = [:]
    private(set) var strip = FloorStrip(visibleFrames: [])

    private var scenes: [CharacterScene] = []
    private var lastTick: TimeInterval = 0

    private init() {
        let stored = UserDefaults.standard.string(forKey: "name") ?? NSFullUserName()
        me = CharacterNode(id: myID, name: sanitizeName(stored), isLocal: true)
        me.apply(World.myLook.frames)
    }

    static var myLook: Look {
        get {
            guard let data = UserDefaults.standard.data(forKey: "look"),
                  let look = try? JSONDecoder().decode(Look.self, from: data)
            else { return .fallback(for: installID) }
            return look.sanitized
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "look")
            shared.me.apply(newValue.frames)
        }
    }

    func attach(scenes: [CharacterScene], strip: FloorStrip) {
        self.scenes = scenes
        self.strip = strip

        if UserDefaults.standard.object(forKey: "anchorX") == nil {
            UserDefaults.standard.set(Double(stableHash(World.installID) % 1200), forKey: "anchorX")
        }
        me.anchorX = strip.clampToWall(CGFloat(UserDefaults.standard.double(forKey: "anchorX")))
        me.x = me.anchorX
    }

    func beginDrag() { me.isDragging = true }

    func endDrag() { me.isDragging = false }

    /// 전역 커서 좌표를 띠 좌표로 바꾼다. 가로는 벽으로, 세로는 커서가 있는 화면의
    /// 바닥을 기준으로 잡는다.
    func updateDrag(toGlobal point: CGPoint) {
        var accumulated: CGFloat = 0
        for frame in strip.frames {
            if frame.contains(point) {
                me.x = strip.clampToWall(accumulated + point.x - frame.minX)
                me.y = max(0, point.y - frame.minY - spriteDisplaySize / 2)
                return
            }
            accumulated += frame.width
        }
    }

    func commitAnchor() {
        me.anchorX = me.x
        UserDefaults.standard.set(Double(me.x), forKey: "anchorX")
    }

    func tick(now: TimeInterval) {
        guard !scenes.isEmpty else { return }
        let dt = lastTick == 0 ? 1.0 / 12 : min(0.25, now - lastTick)
        lastTick = now

        var visible: [(node: CharacterNode, placement: Placement)] = []
        for node in [me] + Array(peers.values) {
            node.update(dt: dt, now: now, strip: strip)

            guard let placement = strip.place(x: node.x, y: node.y) else {
                node.removeFromParent()
                continue
            }
            let scene = scenes[placement.screenIndex]
            if node.parent !== scene {
                node.removeFromParent()
                scene.addChild(node)
            }
            visible.append((node, placement))
        }

        for (node, placement) in visible {
            node.render(placement: placement)
            node.clampBubble(sceneWidth: strip.frames[placement.screenIndex].width)
            if node === me {
                let frame = strip.frames[placement.screenIndex]
                OverlayController.shared.moveHandle(toGlobal: CGPoint(
                    x: frame.minX + placement.point.x,
                    y: frame.minY + placement.point.y))
            }
        }
    }
}

extension World {
    func addPeer(id: String, name: String, look: Look) {
        let node = peers[id] ?? CharacterNode(id: id, name: name, isLocal: false)
        node.displayName = name
        node.apply(look.sanitized.frames)
        peers[id] = node
    }

    func removePeer(id: String) {
        peers[id]?.removeFromParent()
        peers[id] = nil
    }

    func setPeerTarget(id: String, x: CGFloat, y: CGFloat) {
        peers[id]?.setRemoteTarget(x: x, y: y)
    }

    func showBubble(id: String, text: String) {
        let node = id == myID ? me : peers[id]
        node?.showBubble(text: text)
    }
}
