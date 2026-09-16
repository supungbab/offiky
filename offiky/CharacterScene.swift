import AppKit
import SpriteKit

final class CharacterNode: SKNode {
    let id: String
    let isLocal: Bool
    var displayName: String

    var x: CGFloat = 0
    var y: CGFloat = 0

    var isDragging = false
    /// 캐릭터 설정 창이 열려 있는 동안. 색을 고르는 사이에 걸어가 버리면 볼 수가 없다
    var isPosing = false

    private let image = SKSpriteNode()
    private let shadow = SKSpriteNode()
    private let label = SKLabelNode(fontNamed: "Helvetica")
    private var nameBackground: SKShapeNode?
    private var renderedName: String?

    private var verticalSpeed: CGFloat = 0
    enum Motion {
        case idle, walk, dash
        var speed: CGFloat { self == .dash ? 90 : 20 }
        var span: ClosedRange<CGFloat> { self == .dash ? 200...420 : 80...250 }
    }

    private var motion: Motion = .idle
    private var motionEnd: TimeInterval = 0
    private var segmentTarget: CGFloat = 0
    private var nextJumpAt: TimeInterval = 0
    private var airSpeed: CGFloat = 0
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
    private var bubbleUntil: TimeInterval = 0
    private var wasAirborne = false
    private var peakY: CGFloat = 0
    private var shadowStep = -1

    private var samples: [(t: TimeInterval, x: CGFloat, y: CGFloat)] = []
    /// 받은 표본 두 개 사이를 재생하려면 늘 이만큼 과거를 그려야 한다.
    /// 스냅샷 간격의 두 배라 한 번 늦게 와도 끊기지 않는다
    static let renderDelay: TimeInterval = 0.2
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

    private(set) var look = Look.neutral

    func apply(_ look: Look) {
        self.look = look
        sheet = Characters.sheet(look)
        image.size = CGSize(width: sheet.size.width * 2, height: sheet.size.height * 2)
        image.texture = sheet.frames[.idle]?.first
    }

    /// 점프는 세 가지다. 제자리·걷기·대시 순으로 높고 멀리 뛴다.
    private func startJump() {
        let apex: CGFloat
        if motion == .dash {
            apex = 72
            airSpeed = facing * 140
        } else if isWalking {
            apex = 52
            airSpeed = facing * 75
        } else {
            apex = CharacterNode.jumpApex
            airSpeed = 0
        }
        verticalSpeed = (2 * CharacterNode.gravity * apex).squareRoot()
    }

    /// 집어 드는 순간 진행 중이던 모든 운동을 지운다.
    /// 남겨두면 놓는 순간 이전 속도로 튀어 나가거나 하던 대시를 이어서 한다.
    /// 이동한 것으로 세지 않는다. 그러면 대시 동작이 나오고 피격 판정까지 걸린다.
    func teleport(to newX: CGFloat) {
        x = newX
        previousX = newX
        y = 0
        verticalSpeed = 0
        airSpeed = 0
        peakY = 0
        wasAirborne = false
        motion = .idle
        motionEnd = 0
        segmentTarget = newX
        isWalking = false
    }

    func beginDrag() {
        isDragging = true
        verticalSpeed = 0
        airSpeed = 0
        motion = .idle
        motionEnd = 0
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
        motion = .idle
        airSpeed = 0
    }

    func setRemoteTarget(x newX: CGFloat, y newY: CGFloat, at now: TimeInterval) {
        // 걷거나 뛰어서는 한 주기에 나올 수 없는 간격이면 순간이동이다.
        // 이어 붙이면 보간이 초고속 이동으로 해석해 대시 판정과 피격이 난다.
        if let last = samples.last, abs(newX - last.x) > 400 {
            samples.removeAll()
            x = newX
            y = newY
            previousX = newX
            peakY = 0
            wasAirborne = newY > 0
        }
        samples.append((now, newX, newY))
        if samples.count > 8 { samples.removeFirst(samples.count - 8) }
    }

    func update(dt: TimeInterval, now: TimeInterval, strip: FloorStrip) {
        if isLocal {
            simulate(dt: dt, now: now, strip: strip)
        } else {
            interpolate(now: now)
        }
        peakY = max(peakY, y)
        detectLanding(now: now)
        expireBubble(now: now)

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
            motion = .idle
            motionEnd = now + 0.6
            return
        }

        if y > 0 || verticalSpeed != 0 {
            let step = CGFloat(dt)
            y += verticalSpeed * step - 0.5 * CharacterNode.gravity * step * step
            verticalSpeed -= CharacterNode.gravity * step
            if airSpeed != 0 { x = strip.clamp(x + airSpeed * step) }
            if y <= 0 {
                y = 0
                verticalSpeed = 0
                airSpeed = 0
                // 점프한 만큼 나아갔으니 착지 지점에서 가던 방향으로 새 구간을 고른다.
                // 예전 목표로 되돌아가면 뒤돌아 걷는다
                if motion != .idle {
                    chooseNext(from: motion, now: now, strip: strip, keepFacing: true)
                }
            }
            isWalking = false
            return
        }

        if isPosing {
            isWalking = false
            motion = .idle
            motionEnd = now
            return
        }

        if nextJumpAt == 0 { nextJumpAt = now + Double.random(in: 30...90) }
        if now >= nextJumpAt {
            nextJumpAt = now + Double.random(in: 30...90)
            startJump()
            return
        }

        switch motion {
        case .idle:
            isWalking = false
            if now >= motionEnd { chooseNext(from: .idle, now: now, strip: strip) }
        case .walk, .dash:
            // 목표에 닿아도 멈추지 않고 남은 걸음을 다음 구간에서 이어 간다.
            // 거리로만 판정하면 뛸 때 목표를 넘나들며 제자리에서 떤다
            var budget = motion.speed * CGFloat(dt)
            var hops = 0
            while motion != .idle, budget > 0, hops < 4 {
                let delta = segmentTarget - x
                if abs(delta) > budget {
                    x = strip.clamp(x + (delta > 0 ? 1 : -1) * budget)
                    break
                }
                x = strip.clamp(segmentTarget)
                budget -= abs(delta)
                hops += 1
                chooseNext(from: motion, now: now, strip: strip)
            }
            isWalking = motion != .idle
        }
    }

    /// 상태 전이표. 방향을 먼저 정하고 다음 상태를 고른다.
    private func chooseNext(from: Motion, now: TimeInterval, strip: FloorStrip,
                           keepFacing: Bool = false) {
        let roll = Double.random(in: 0...1)
        var next: Motion
        switch from {
        case .idle: next = roll < 0.7 ? .walk : .dash            // 걷기 70 / 뛰기 30
        case .walk: next = roll < 0.7 ? .walk : (roll < 0.85 ? .dash : .idle)
        case .dash: next = roll < 0.7 ? .walk : (roll < 0.85 ? .dash : .idle)
        }
        if next == .idle {
            motion = .idle
            motionEnd = now + Double.random(in: 4...8)
            return
        }

        var direction: CGFloat
        switch from {
        case _ where keepFacing: direction = facing              // 착지 뒤에는 방향을 바꾸지 않는다
        case .idle: direction = Bool.random() ? 1 : -1           // 좌우 50:50
        case .walk: direction = Double.random(in: 0...1) < 0.8 ? facing : -facing
        case .dash: direction = Double.random(in: 0...1) < 0.9 ? facing : -facing
        }
        // 구간 최소 거리를 못 채우면 반대로 간다. 양쪽 다 좁으면 뛰지 않고 걷는다
        if room(direction, strip) < next.span.lowerBound,
           room(-direction, strip) < next.span.lowerBound, next == .dash {
            next = .walk
        }
        if room(direction, strip) < next.span.lowerBound { direction = -direction }

        motion = next
        segmentTarget = strip.clamp(x + direction * CGFloat.random(in: next.span))
        // 달리는 도중 절반은 점프한다
        if next == .dash, Bool.random() { nextJumpAt = now + Double.random(in: 0.4...1.1) }
    }

    private func room(_ direction: CGFloat, _ strip: FloorStrip) -> CGFloat {
        direction > 0 ? strip.maxX - x : x - strip.minX
    }

    /// 렌더 시각을 감싸는 두 표본 사이를 재생한다. 앞뒤를 다 쥐고 있으므로 추정하지 않는다.
    /// 표본이 끊기면 마지막 자리에 세워 둔다
    private func interpolate(now: TimeInterval) {
        guard let last = samples.last else { return }
        let renderAt = now - CharacterNode.renderDelay
        while samples.count > 2, samples[1].t <= renderAt { samples.removeFirst() }

        guard let a = samples.first, samples.count >= 2, a.t <= renderAt else {
            let first = samples[0]
            let stop = renderAt < first.t ? first : last
            x = stop.x; y = stop.y
            isWalking = false
            return
        }
        let b = samples[1]
        let span = b.t - a.t
        let ratio = span > 0 ? CGFloat(min(1, (renderAt - a.t) / span)) : 1
        x = a.x + (b.x - a.x) * ratio
        y = a.y + (b.y - a.y) * ratio
        isWalking = ratio < 1 && span > 0 && abs(b.x - a.x) / CGFloat(span) > 2
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
    func showBubble(text: String, now: TimeInterval) {
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
        bubbleUntil = now + 5
    }

    /// SKAction 으로 지우면 노드가 씬에서 빠져 있는 동안 시간이 흐르지 않아 말풍선이 남는다
    func expireBubble(now: TimeInterval) {
        guard bubbleUntil != 0, now >= bubbleUntil else { return }
        childNode(withName: "bubble")?.removeFromParent()
        bubbleUntil = 0
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

/// 갱신을 SpriteKit 의 렌더 루프에 맡긴다. 별도 타이머로 돌리면 두 시계가 어긋나
/// 어떤 프레임은 같은 그림을 두 번 그리고 어떤 프레임은 두 칸씩 건너뛴다.
final class CharacterScene: SKScene {
    override func update(_ currentTime: TimeInterval) {
        World.shared.tick(now: currentTime)
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
    private(set) var strip = FloorStrip(visibleFrames: [], main: nil)

    private var scenes: [CharacterScene] = []
    private var lastTick: TimeInterval = 0
    private var placed = false

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

    /// 화면 구성이 바뀌면 위치를 새 띠 안으로 당기기만 한다.
    /// 되돌리면 노트북을 열고 닫을 때마다 캐릭터가 순간이동한다.
    func attach(scenes: [CharacterScene], strip: FloorStrip) {
        // 화면 구성이 바뀌면 좌표계가 통째로 움직인다. 보이는 자리를 지키려면
        // 바뀌기 전의 화면 위치를 받아 두었다가 새 좌표계로 되돌려야 한다
        let wasOn = self.strip.frames.isEmpty ? nil : self.strip.place(x: me.x, y: me.y)
        let wasAt = wasOn.map { spot -> CGPoint in
            let frame = self.strip.frames[spot.screenIndex]
            return CGPoint(x: frame.minX + spot.point.x, y: frame.minY + spot.point.y)
        }

        self.scenes = scenes
        self.strip = strip
        // 화면이 하나도 없는 순간에는 건드리지 않는다. 띠 길이가 0이라 좌표가 전부 0이 된다
        guard !strip.frames.isEmpty else { return }

        if !placed {
            // 시작 위치는 바닥 아무 데나. 띠를 알아야 정할 수 있어 여기서 한 번만 한다
            placed = true
            me.teleport(to: strip.clamp(CGFloat.random(in: strip.minX...strip.maxX)))
        } else if let wasAt, let back = strip.locate(global: wasAt) {
            // 있던 화면이 남아 있으면 그 자리를 지킨다
            me.teleport(to: strip.clamp(back.x))
        } else if let wasOn {
            // 있던 화면이 사라졌다. 화면 안에서의 가로 위치를 지켜 주 화면으로 데려온다
            me.teleport(to: strip.onMain(offset: wasOn.point.x))
        }
        // 로컬에서 도는 캐릭터만 당긴다. 동료 좌표는 그쪽이 기준이다
        for node in peers.values.filter(\.isLocal) {
            node.x = strip.clamp(node.x)
        }
        me.x = strip.clamp(me.x)
        // 씬을 새로 만들었으므로 눈금도 다시 그린다
    }

    func beginDrag() { me.beginDrag() }

    func endDrag() { me.isDragging = false }

    /// 전역 커서 좌표를 띠 좌표로 바꾼다. 세로는 커서가 있는 화면의
    /// 바닥을 기준으로 잡는다.
    func updateDrag(toGlobal point: CGPoint) {
        guard let spot = strip.locate(global: point) else { return }
        me.x = strip.clamp(spot.x)
        me.y = spot.y
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

    func tick(now: TimeInterval) {
        guard !scenes.isEmpty else { return }
        // 화면마다 씬이 따로 부르므로 한 프레임에 여러 번 들어온다
        let elapsed = now - lastTick
        guard lastTick == 0 || elapsed >= 1.0 / 70 else { return }
        let dt = lastTick == 0 ? 1.0 / 60 : min(0.25, elapsed)
        lastTick = now

        let count = 1 + peers.count
        if Presence.shared.count != count { Presence.shared.count = count }

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
                    y: frame.minY + placement.point.y), now: now)
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

    /// 메뉴는 SwiftUI 가 관찰하는 값이 바뀔 때만 다시 그린다.
    /// 함수를 직접 부르면 앱을 켠 순간의 값이 그대로 굳는다.
    func roster() -> [(id: String, name: String, look: Look, isMe: Bool)] {
        let mine = (me.id, me.displayName, me.look, true)
        let others = peers.values
            .sorted { $0.displayName < $1.displayName }
            .map { ($0.id, $0.displayName, $0.look, false) }
        return [mine] + others
    }

    func removeAllPeers() {
        peers.values.forEach { $0.removeFromParent() }
        peers.removeAll()
    }

    func setPeerTarget(id: String, x: CGFloat, y: CGFloat) {
        peers[id]?.setRemoteTarget(x: x, y: y, at: ProcessInfo.processInfo.systemUptime)
    }

    func showBubble(id: String, text: String) {
        let node = id == myID ? me : peers[id]
        node?.showBubble(text: text, now: ProcessInfo.processInfo.systemUptime)
    }
}


/// 메뉴가 참가자 수를 따라 바뀌도록 관찰 가능한 값으로 들고 있는다
@Observable final class Presence {
    static let shared = Presence()
    var count = 1
    private init() {}
}
