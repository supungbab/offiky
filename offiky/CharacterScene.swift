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
    private var nextDashAt: TimeInterval = 0
    private var dashTarget: CGFloat?
    private var dashDirection: CGFloat = 1
    private var walkSpeed: CGFloat { dashTarget == nil ? 20 : 90 }
    private var isWalking = false
    /// 이동 방향. +1 오른쪽, -1 왼쪽
    private var facing: CGFloat = -1
    var facingSign: CGFloat { facing }

    func face(_ direction: CGFloat) {
        guard direction != 0 else { return }
        facing = direction > 0 ? 1 : -1
    }

    private var bobPhase: CGFloat = 0
    private var walkPhase: TimeInterval = 0
    private var previousX: CGFloat = 0
    private(set) var lastAnimation: Animation = .idle
    var hurtUntil: TimeInterval = 0
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

        image.anchorPoint = CGPoint(x: 0.5, y: 0)
        image.position = CGPoint(x: 0, y: -spriteDisplaySize / 2)
        addChild(image)

        label.fontSize = 10
        label.fontColor = .white
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: 0, y: spriteDisplaySize / 2 + 2)
        addChild(label)

        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    private var sheet = Characters.Sheet(size: .zero, frames: [:])

    func apply(_ look: Look) {
        sheet = Characters.sheet(look)
        image.size = CGSize(width: sheet.size.width * 2, height: sheet.size.height * 2)
        image.texture = sheet.frames[.idle]?.first
    }

    func takeHit(now: TimeInterval) {
        hurtUntil = now + 0.6
        walkPhase = 0
        dashTarget = nil
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
        detectLanding(now: now)
        bobPhase += CGFloat(dt) * (isWalking ? 9 : 2)

        let moved = x - previousX
        previousX = x
        if abs(moved) > 0.1 { face(moved) }
        let speed = abs(moved) / CGFloat(max(dt, 0.001))

        let animation: Animation
        if isDragging { animation = .idle }          // 들려 있는 동안은 가만히 서 있는다
        else if now < hurtUntil { animation = .hurt }
        else if y > 0 { animation = .jump }
        else if speed > 70 { animation = .dash }
        else if isWalking { animation = .walk }
        else { animation = .idle }

        if !isDragging { walkPhase += dt }
        if let textures = sheet.frames[animation], !textures.isEmpty {
            let index = isDragging ? 0 : Int(walkPhase * animation.fps) % textures.count
            image.texture = textures[index]
        }
        lastAnimation = animation
    }

    private func simulate(dt: TimeInterval, now: TimeInterval, strip: FloorStrip) {
        if isDragging { isWalking = false; return }
        if now < hurtUntil {
            isWalking = false
            dashTarget = nil
            return
        }

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

        // 아주 가끔 멀리까지 빠르게 달린다
        if nextDashAt == 0 { nextDashAt = now + Double.random(in: 25...70) }
        if dashTarget == nil, now >= nextDashAt {
            nextDashAt = now + Double.random(in: 25...70)
            let distance = CGFloat.random(in: 220...420)
            // 방향은 시작할 때 정하고 끝날 때까지 바꾸지 않는다
            var direction: CGFloat = Bool.random() ? 1 : -1
            if abs(strip.clampToWall(x + direction * distance) - x) < 60 { direction *= -1 }
            let target = strip.clampToWall(x + direction * distance)
            if abs(target - x) >= 60 {
                dashDirection = direction
                dashTarget = target
            }
        }
        if let target = dashTarget {
            let next = strip.clampToWall(x + dashDirection * walkSpeed * CGFloat(dt))
            let reached = dashDirection > 0 ? next >= target : next <= target
            let blocked = abs(next - x) < 0.01
            x = next
            if blocked {
                // 대시로 벽에 부딪히면 피격
                takeHit(now: now)
                anchorX = x
                walkTarget = x
            } else if reached {
                dashTarget = nil
                anchorX = x
                walkTarget = x
                nextWalkAt = now + Double.random(in: 1...3)
                isWalking = false
            } else {
                isWalking = true
            }
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
            let step: CGFloat = delta > 0 ? 1 : -1
            let next = strip.clampToWall(x + step * walkSpeed * CGFloat(dt))
            if abs(next - x) < 0.01 {
                // 벽에 닿았다. 방향만 바꾼다
                walkTarget = strip.clampToWall(x - step * CGFloat.random(in: 60...150))
            }
            x = next
        }
    }

    private func interpolate(dt: TimeInterval) {
        interpolatedFor = min(CharacterNode.interpolationDuration, interpolatedFor + dt)
        let t = CGFloat(interpolatedFor / CharacterNode.interpolationDuration)
        x = fromX + (toX - fromX) * t
        y = fromY + (toY - fromY) * t
        isWalking = abs(toX - fromX) > 1
    }

    private func detectLanding(now: TimeInterval) {
        let airborne = y > 0
        if wasAirborne && !airborne {
            if self === World.shared.me { World.shared.commitAnchor() }
            (scene as? CharacterScene)?.spawnDust(at: position, speed: abs(verticalSpeed), now: now)
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
        // 스프라이트는 오른쪽을 보고 그려져 있다
        image.xScale = facing
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
    static let dustName = "dust"

    /// 액션에 기대지 않고 시간으로 치운다. 씬 렌더링이 멈추면 fadeOut 이 중간에
    /// 얼어붙어 점이 그대로 남는다.
    func sweepDust(now: TimeInterval) {
        for node in children where node.name == CharacterScene.dustName {
            guard let born = node.userData?["born"] as? TimeInterval else {
                node.removeFromParent(); continue
            }
            if now - born > 1 { node.removeFromParent() }
        }
    }


    func spawnDust(at point: CGPoint, speed: CGFloat, now: TimeInterval) {
        let count = min(6, max(4, Int(speed / 400)))
        let rgb: UInt32 = 0xAB5236
        let color = NSColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)

        for _ in 0..<count {
            let dot = SKSpriteNode(color: color, size: CGSize(width: 2, height: 2))
            dot.name = CharacterScene.dustName
            dot.userData = ["born": now]
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
        me.apply(World.myLook)
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
            shared.me.apply(newValue)
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
                let next = strip.clampToWall(accumulated + point.x - frame.minX)
                if abs(next - me.x) > 0.1 { me.face(next - me.x) }
                me.x = next
                me.y = max(0, point.y - frame.minY - spriteDisplaySize / 2)
                return
            }
            accumulated += frame.width
        }
    }

    /// 대시로 달리는 캐릭터끼리 정면으로 부딪히면 둘 다 피격 동작을 재생한다.
    /// 좌표는 모두가 공유하므로 각자 같은 판정을 내린다. 평소에는 서로 통과한다.
    private func resolveDashCollisions(now: TimeInterval) {
        let dashing = ([me] + Array(peers.values)).filter { $0.lastAnimation == .dash }
        guard dashing.count > 1 else { return }
        for (i, a) in dashing.enumerated() {
            for b in dashing.dropFirst(i + 1) {
                guard now >= a.hurtUntil, now >= b.hurtUntil,
                      abs(a.x - b.x) < 22,
                      a.facingSign != b.facingSign,
                      (b.x - a.x) * a.facingSign > 0
                else { continue }
                a.takeHit(now: now)
                b.takeHit(now: now)
            }
        }
    }

    func commitAnchor() {
        me.anchorX = me.x
        UserDefaults.standard.set(Double(me.x), forKey: "anchorX")
    }

    func tick(now: TimeInterval) {
        guard !scenes.isEmpty else { return }
        let dt = lastTick == 0 ? 1.0 / 24 : min(0.25, now - lastTick)
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

        resolveDashCollisions(now: now)
        scenes.forEach { $0.sweepDust(now: now) }

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
        node.apply(look.sanitized)
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


// MARK: - 테스트

extension World {
    /// 네트워크 없이 로컬에서 각자 움직이는 캐릭터를 푼다. 메뉴바에서 호출한다.
    func spawnTestPeers(_ count: Int) {
        removeTestPeers()
        let length = max(strip.length, 1)
        for i in 0..<count {
            let id = "test-\(i)"
            let node = CharacterNode(id: id, name: "테스트\(i + 1)", isLocal: true)
            node.apply(Look(design: i % Characters.count,
                            hue: Double.random(in: -0.5...0.5),
                            saturation: Double.random(in: 0.6...1.4),
                            brightness: Double.random(in: 0.8...1.2)))
            node.x = strip.clampToWall(length * CGFloat(i + 1) / CGFloat(count + 1))
            node.anchorX = node.x
            peers[id] = node
        }
    }

    func removeTestPeers() {
        for (id, node) in peers where id.hasPrefix("test-") {
            node.removeFromParent()
            peers[id] = nil
        }
    }

    var testPeerCount: Int { peers.keys.filter { $0.hasPrefix("test-") }.count }
}
