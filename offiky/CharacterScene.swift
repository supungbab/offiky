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
    private let shadow = SKSpriteNode()
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
    private var airSpeed: CGFloat = 0
    private var walkSpeed: CGFloat { dashTarget == nil ? 20 : 90 }
    private var isWalking = false
    /// 이동 방향. +1 오른쪽, -1 왼쪽
    private var facing: CGFloat = -1
    var facingSign: CGFloat { facing }

    func face(_ direction: CGFloat) {
        guard direction != 0 else { return }
        facing = direction > 0 ? 1 : -1
    }

    private var walkPhase: TimeInterval = 0
    private var previousX: CGFloat = 0
    private(set) var lastAnimation: Animation = .idle
    /// 부딪히면 다칠 만큼 앞으로 나아가는 중인지. 표시용 동작이 아니라 실제 속도로 판정한다.
    private(set) var isCharging = false
    var hurtUntil: TimeInterval = 0
    private var wasAirborne = false
    private var peakY: CGFloat = 0
    private var shadowStep = -1

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

        shadowStep = -1
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

    private var sheet = Characters.Sheet(size: .zero, bodyWidth: 16, frames: [:])

    func apply(_ look: Look) {
        sheet = Characters.sheet(look)
        image.size = CGSize(width: sheet.size.width * 2, height: sheet.size.height * 2)
        image.texture = sheet.frames[.idle]?.first
    }

    /// 점프는 세 가지다. 제자리·걷기·대시 순으로 높고 멀리 뛴다.
    private func startJump() {
        let apex: CGFloat
        if dashTarget != nil {
            apex = 72
            airSpeed = dashDirection * 140
        } else if isWalking {
            apex = 52
            airSpeed = facing * 45
        } else {
            apex = CharacterNode.jumpApex
            airSpeed = 0
        }
        verticalSpeed = (2 * CharacterNode.gravity * apex).squareRoot()
    }

    /// 집어 드는 순간 진행 중이던 모든 운동을 지운다.
    /// 남겨두면 놓는 순간 이전 속도로 튀어 나가거나 하던 대시를 이어서 한다.
    func beginDrag() {
        isDragging = true
        verticalSpeed = 0
        airSpeed = 0
        dashTarget = nil
        hurtUntil = 0
        walkPhase = 0
        isWalking = false
    }

    /// 높이에 따라 그림자를 줄인다. 연속 배율로 줄이면 픽셀 크기가 들쭉날쭉해지므로
    /// 단계마다 그 크기의 타원을 따로 만든다.
    static let shadowSteps: [CGFloat] = [1, 0.85, 0.7, 0.55]

    private func applyShadow(step: Int) {
        guard step != shadowStep else { return }
        shadowStep = step
        let base = Characters.shadowSize(bodyWidth: sheet.bodyWidth)
        let factor = CharacterNode.shadowSteps[step]
        let size = (width: max(4, Int((CGFloat(base.width) * factor).rounded())),
                    height: max(3, Int((CGFloat(base.height) * factor).rounded())))
        shadow.texture = Characters.shadowTexture(size)
        shadow.size = CGSize(width: CGFloat(size.width) * 2,
                             height: CGFloat(size.height) * 2)
    }

    func takeHit(now: TimeInterval) {
        hurtUntil = now + 0.6
        walkPhase = 0
        dashTarget = nil
        airSpeed = 0
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
        peakY = max(peakY, y)
        detectLanding(now: now)

        let moved = x - previousX
        previousX = x
        // 바닥에 있을 때만 방향을 갱신한다. 들려 있거나 공중에 있는 동안은 유지한다
        if !isDragging, y <= 0, abs(moved) > 0.1 { face(moved) }
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
        // 공중에서는 앞으로 나아가는 점프만, 바닥에서는 대시만 해당한다
        isCharging = !isDragging && now >= hurtUntil && (y > 0 ? speed > 35 : speed > 70)
    }

    private func simulate(dt: TimeInterval, now: TimeInterval, strip: FloorStrip) {
        if isDragging { isWalking = false; return }
        if now < hurtUntil {
            isWalking = false
            dashTarget = nil
            return
        }

        if y > 0 || verticalSpeed != 0 {
            let step = CGFloat(dt)
            y += verticalSpeed * step - 0.5 * CharacterNode.gravity * step * step
            verticalSpeed -= CharacterNode.gravity * step
            if airSpeed != 0 { x = strip.clamp(x + airSpeed * step) }
            if y <= 0 { y = 0; verticalSpeed = 0; airSpeed = 0 }
            isWalking = false
            return
        }

        if nextJumpAt == 0 { nextJumpAt = now + Double.random(in: 30...90) }
        if now >= nextJumpAt {
            nextJumpAt = now + Double.random(in: 30...90)
            startJump()
            return
        }

        // 아주 가끔 멀리까지 빠르게 달린다
        if nextDashAt == 0 { nextDashAt = now + Double.random(in: 25...70) }
        if dashTarget == nil, now >= nextDashAt {
            nextDashAt = now + Double.random(in: 25...70)
            // 남은 공간이 넓은 쪽으로 달린다. 방향은 끝날 때까지 바꾸지 않는다
            dashDirection = x < strip.length / 2 ? 1 : -1
            dashTarget = strip.clamp(x + dashDirection * CGFloat.random(in: 220...420))
            if Bool.random() { nextJumpAt = now + Double.random(in: 0.4...1.1) }
        }
        if let target = dashTarget {
            x = strip.clamp(x + dashDirection * walkSpeed * CGFloat(dt))
            let reached = dashDirection > 0 ? x >= target : x <= target
            if reached {
                dashTarget = nil
                // 급정거하지 않고 같은 방향으로 조금 더 걸어 나간다
                walkTarget = strip.clamp(x + dashDirection * CGFloat.random(in: 30...80))
                anchorX = walkTarget
                nextWalkAt = now + Double.random(in: 3...7)
            }
            isWalking = true
            return
        }

        if now >= nextWalkAt {
            nextWalkAt = now + Double.random(in: 3...9)
            walkTarget = strip.clamp(anchorX + CGFloat.random(in: -150...150))
        }
        let delta = walkTarget - x
        if abs(delta) < 1 {
            isWalking = false
        } else {
            isWalking = true
            x = strip.clamp(x + (delta > 0 ? 1 : -1) * walkSpeed * CGFloat(dt))
        }
    }

    private func interpolate(dt: TimeInterval) {
        interpolatedFor = min(CharacterNode.interpolationDuration, interpolatedFor + dt)
        let t = CGFloat(interpolatedFor / CharacterNode.interpolationDuration)
        x = fromX + (toX - fromX) * t
        y = fromY + (toY - fromY) * t
        isWalking = abs(toX - fromX) > 1
    }

    /// 낙하 속도는 프레임 간 높이 변화로 구한다. verticalSpeed 는 착지 직전에
    /// 0으로 초기화되고, 원격 캐릭터에는 아예 없다.
    /// 착지 속도는 최고 높이에서 구한다. 자유낙하는 v = sqrt(2gh) 이므로
    /// 프레임 타이밍과 무관하고 원격 캐릭터에도 그대로 적용된다.
    /// 마지막 프레임의 높이로 계산하면 착지 직전 프레임이 어디에 걸리느냐에 따라
    /// 같은 높이에서 떨어져도 결과가 널뛴다.
    private func detectLanding(now: TimeInterval) {
        // 드래그 중에는 착지가 아니다. 커서를 바닥으로 내리면 낙하로 오인한다
        guard !isDragging else {
            wasAirborne = y > 0
            return
        }
        let airborne = y > 0
        if wasAirborne && !airborne {
            let impact = (2 * CharacterNode.gravity * peakY).squareRoot()
            if self === World.shared.me { World.shared.commitAnchor() }
            // 점프 정점(48pt)에서 떨어지면 약 320pt/s 다. 그보다 높은 데서
            // 떨어졌을 때만 피격한다
            if impact > 500 { takeHit(now: now) }
        }
        if !airborne { peakY = 0 }
        wasAirborne = airborne
    }

    func render(placement: Placement) {
        // 픽셀 한 칸이 2pt 이므로 표시 위치를 2pt 격자에 맞춘다.
        // 소수점 위치에 그리면 프레임마다 픽셀 폭이 달라져 몸이 일렁인다.
        // 물리 좌표는 소수점 그대로 두어야 이동이 끊기지 않는다.
        position = CGPoint(x: (placement.point.x / 2).rounded() * 2,
                           y: (placement.point.y / 2).rounded() * 2)

        // 그림자는 캐릭터를 따라 뜨지 않고 바닥에 남는다
        // 발 위치보다 2pt 아래에 두어 캐릭터가 그림자를 밟고 선 것처럼 보이게 한다
        shadow.position = CGPoint(x: 0, y: -y - spriteDisplaySize / 2 - 2)
        let lift = min(1, y / 120)
        applyShadow(step: min(CharacterNode.shadowSteps.count - 1,
                              Int(lift * CGFloat(CharacterNode.shadowSteps.count))))
        shadow.alpha = 0.3 * (1 - 0.75 * lift)
        zPosition = x + CGFloat(stableHash(id) % 997) / 1000
        // 스프라이트는 오른쪽을 보고 그려져 있다
        image.xScale = facing
        updateNameLabel()
    }

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

final class CharacterScene: SKScene {}

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
        me.anchorX = strip.clamp(CGFloat(UserDefaults.standard.double(forKey: "anchorX")))
        me.x = me.anchorX
    }

    func beginDrag() { me.beginDrag() }

    func endDrag() { me.isDragging = false }

    /// 전역 커서 좌표를 띠 좌표로 바꾼다. 세로는 커서가 있는 화면의
    /// 바닥을 기준으로 잡는다.
    func updateDrag(toGlobal point: CGPoint) {
        var accumulated: CGFloat = 0
        for frame in strip.frames {
            if frame.contains(point) {
                me.x = strip.clamp(accumulated + point.x - frame.minX)
                me.y = max(0, point.y - frame.minY - floorOffset - spriteDisplaySize / 2)
                return
            }
            accumulated += frame.width
        }
    }

    /// 앞으로 빠르게 나아가는 캐릭터끼리 정면으로 부딪히면 둘 다 피격한다.
    /// 지상 대시, 걷기 점프, 대시 점프가 모두 해당한다.
    /// 좌표는 모두가 공유하므로 각자 같은 판정을 내린다. 평소에는 서로 통과한다.
    private func resolveCollisions(now: TimeInterval) {
        let charging = ([me] + Array(peers.values)).filter(\.isCharging)
        guard charging.count > 1 else { return }
        for (i, a) in charging.enumerated() {
            for b in charging.dropFirst(i + 1) {
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

        resolveCollisions(now: now)

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
            node.x = strip.clamp(length * CGFloat(i + 1) / CGFloat(count + 1))
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


