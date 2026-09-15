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
    var forceName = false

    private let image = SKSpriteNode()
    private let label = SKLabelNode(fontNamed: "Helvetica")

    private var verticalSpeed: CGFloat = 0
    private var walkTarget: CGFloat = 0
    private var nextWalkAt: TimeInterval = 0
    private var nextJumpAt: TimeInterval = 0
    private var isWalking = false

    private var bobPhase: CGFloat = 0
    private var wasAirborne = false

    private var fromX: CGFloat = 0, fromY: CGFloat = 0
    private var toX: CGFloat = 0, toY: CGFloat = 0
    private var interpolatedFor: TimeInterval = 0
    private static let interpolationDuration: TimeInterval = 0.5

    init(id: String, name: String, isLocal: Bool) {
        self.id = id
        self.displayName = name
        self.isLocal = isLocal
        super.init()

        image.size = CGSize(width: spriteDisplaySize, height: spriteDisplaySize)
        addChild(image)

        label.fontSize = 10
        label.fontColor = .white
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: 0, y: spriteDisplaySize / 2 + 2)
        label.isHidden = true
        addChild(label)

        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(sprite: Sprite) {
        guard let cg = sprite.cgImage() else { return }
        let texture = SKTexture(cgImage: cg)
        texture.filteringMode = .nearest
        image.texture = texture
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
    }

    private func simulate(dt: TimeInterval, now: TimeInterval, strip: FloorStrip) {
        if isDragging { isWalking = false; return }

        if y > 0 || verticalSpeed != 0 {
            verticalSpeed += -2400 * CGFloat(dt)
            y += verticalSpeed * CGFloat(dt)
            if y <= 0 { y = 0; verticalSpeed = 0 }
            isWalking = false
            return
        }

        if nextJumpAt == 0 { nextJumpAt = now + Double.random(in: 30...90) }
        if now >= nextJumpAt {
            nextJumpAt = now + Double.random(in: 30...90)
            verticalSpeed = (2 * 2400 * 24).squareRoot()
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
            x = strip.clampToWall(x + (delta > 0 ? 1 : -1) * 20 * CGFloat(dt))
        }
    }

    private func interpolate(dt: TimeInterval) {
        interpolatedFor = min(CharacterNode.interpolationDuration, interpolatedFor + dt)
        let t = CGFloat(interpolatedFor / CharacterNode.interpolationDuration)
        x = fromX + (toX - fromX) * t
        y = fromY + (toY - fromY) * t
        isWalking = abs(toX - fromX) > 1
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
    func render(placement: Placement, showName: Bool) {
        let bob: CGFloat = sin(bobPhase) > 0 ? 1 : 0
        position = CGPoint(x: placement.point.x, y: placement.point.y + bob)
        zPosition = x + CGFloat(stableHash(id) % 997) / 1000
        label.text = displayName
        label.isHidden = !showName
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
        let rgb = Palette.rgb[Palette.dustIndex]
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

    let myID = UUID().uuidString

    private(set) var me: CharacterNode
    private(set) var peers: [String: CharacterNode] = [:]
    private(set) var strip = FloorStrip(visibleFrames: [])

    private var scenes: [CharacterScene] = []
    private var lastTick: TimeInterval = 0

    private init() {
        let stored = UserDefaults.standard.string(forKey: "name") ?? NSFullUserName()
        me = CharacterNode(id: myID, name: sanitizeName(stored), isLocal: true)
        me.apply(sprite: World.storedSprite(for: myID))
    }

    static func storedSprite(for id: String) -> Sprite {
        if let encoded = UserDefaults.standard.string(forKey: "sprite"),
           let sprite = Sprite(encoded: encoded) {
            return sprite
        }
        return Sprite.standard(for: id)
    }

    func attach(scenes: [CharacterScene], strip: FloorStrip) {
        self.scenes = scenes
        self.strip = strip

        if UserDefaults.standard.object(forKey: "anchorX") == nil {
            UserDefaults.standard.set(Double(stableHash(myID) % 1200), forKey: "anchorX")
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

        let cursor = NSEvent.mouseLocation
        var nearestID: String?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for (node, placement) in visible {
            let frame = strip.frames[placement.screenIndex]
            let global = CGPoint(x: frame.minX + placement.point.x,
                                 y: frame.minY + placement.point.y)
            let distance = hypot(global.x - cursor.x, global.y - cursor.y)
            if distance <= 60, distance < nearestDistance {
                nearestDistance = distance
                nearestID = node.id
            }
        }

        for (node, placement) in visible {
            node.render(placement: placement,
                        showName: node.id == nearestID || node.forceName)
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
    func addPeer(id: String, name: String, sprite encoded: String) {
        let sprite = Sprite(encoded: encoded) ?? Sprite.standard(for: id)
        if let existing = peers[id] {
            existing.displayName = name
            existing.apply(sprite: sprite)
            return
        }
        let node = CharacterNode(id: id, name: name, isLocal: false)
        node.apply(sprite: sprite)
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
        node?.forceName = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { node?.forceName = false }
    }
}
