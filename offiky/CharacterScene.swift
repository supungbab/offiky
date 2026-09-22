import AppKit
import SpriteKit

final class CharacterNode: SKNode {
    let id: String
    let isLocal: Bool
    var displayName: String
    private let depthBias: CGFloat

    var x: CGFloat = 0
    var y: CGFloat = 0

    var isDragging = false

    private let image = SKSpriteNode()
    private let shadow = SKSpriteNode()
    private let label = SKLabelNode(fontNamed: "Helvetica")
    private var nameBackground: SKShapeNode?
    private var bubbleNode: SKShapeNode?
    private var renderedName: String?

    private var verticalSpeed: CGFloat = 0
    private var isWalking = false

    /// 조종 입력. -1 왼쪽, +1 오른쪽, 0 정지
    private(set) var holding: CGFloat = 0
    /// 고개를 숙이고 있는지. 웅크림 자세를 그대로 쓴다
    var isBowing = false
    private(set) var isDashing = false
    /// 세 속도 모두 30fps 에서 한 프레임에 정수 픽셀만큼 간다. 표시 위치가 2pt
    /// 격자에 맞춰지므로, 나누어떨어지지 않으면 한 칸씩 더 갔다 덜 갔다 한다
    static let walkSpeed: CGFloat = 60
    static let dashSpeed: CGFloat = 180
    /// 웅크린 채로 기어갈 때. 걷기보다 느리다
    static let crawlSpeed: CGFloat = 30
    /// 기어갈 때는 달리기 그림을 쓰되 천천히 넘긴다.
    /// 걷기가 한 장에 5pt 가므로 같은 비율이 되는 값이다
    static let crawlFPS: Double = 6
    /// 원격 캐릭터의 보간 속도가 이 값을 넘으면 대시 동작을 그린다
    static let dashAnimationThreshold: CGFloat = 110
    /// 이동 방향. +1 오른쪽, -1 왼쪽
    private var facing: CGFloat = -1
    var facingSign: CGFloat { facing }

    func face(_ direction: CGFloat) {
        guard direction != 0 else { return }
        facing = direction > 0 ? 1 : -1
    }

    /// 주인이 알려 준 방향. 이걸 받기 시작하면 움직임으로 읽지 않는다 —
    /// 보간이 늦게 재생하는 탓에 들고 놓은 뒤 혼자 돌아서는 일이 있다
    private(set) var facingTold = false

    func faceAsTold(_ direction: CGFloat) {
        facingTold = true
        face(direction)
    }

    private var walkPhase: TimeInterval = 0
    private var renderedAnimation: Animation?
    private var renderedFrame = -1
    private var previousX: CGFloat = 0
    var hurtUntil: TimeInterval = 0
    private var bubbleUntil: TimeInterval = 0
    private var wasAirborne = false
    private var peakY: CGFloat = 0
    private var shadowStep = -1

    /// 마지막으로 좌표를 받은 시각. 끊김을 놓쳐도 이걸로 정리한다
    var lastSeen: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var samples: [(t: TimeInterval, x: CGFloat, y: CGFloat)] = []
    /// 받은 표본 두 개 사이를 재생하려면 늘 이만큼 과거를 그린다.
    /// 최근 도착 간격의 최대치를 따라간다 — 망이 좋으면 빠르게, 흔들리면 안정되게
    private(set) var renderDelay: TimeInterval = 0.2
    /// 흔들림을 잰 시각과 그 크기. 건수로 세면 띄엄띄엄 걷는 사람은 옛것이 오래 남는다
    private var gaps: [(at: TimeInterval, gap: TimeInterval)] = []
    /// 흔들림은 도착 시각으로 잰다. 표본 시각은 상대 시계로 놓기 때문이다
    private var lastArrival: TimeInterval = 0
    /// 상대 시계와 우리 시계의 차이. 가장 빨리 온 것이 가장 정확하다
    private var offsets: [TimeInterval] = []
    /// 상대가 마지막으로 보낸 시각. 이보다 옛것이 오면 순서가 뒤바뀐 것이다
    private var lastSentTime: TimeInterval?
    /// 직전에 같은 자리를 다시 받았다. 그 간격은 망이 느린 것이 아니다
    private var wasStill = false
    /// 이보다 벌어지면 보내는 쪽이 서 있었던 것으로 본다
    static let stillGap: TimeInterval = 0.3
    /// 흔들림을 기억하는 기간. 쉬지 않고 걸을 때의 옛 창(30건 ÷ 10Hz)과 같은 길이다
    static let gapMemory: TimeInterval = 3
    static let delayRange: ClosedRange<TimeInterval> = 0.15...0.5
    /// 지연을 갑자기 바꾸면 위치가 튄다. 초당 이만큼만 옮긴다
    static let delaySlew: TimeInterval = 0.1
    static let gravity: CGFloat = 1100
    /// 누르고 있는 정도에 따라 제자리·걷기·대시 순으로 높이 뛴다
    static let jumpApex: CGFloat = 72
    static let walkJumpApex: CGFloat = 78
    static let dashJumpApex: CGFloat = 108
    /// 공중에서 한 번 더 뛴다. 착지해야 다시 찬다
    static let maxJumps = 2
    static let airJumpApex: CGFloat = 60
    private var jumpsUsed = 0

    /// 뛰어서 닿는 최고점. 대시 점프 정점에서 한 번 더 차는 경우다
    static let maxJumpHeight = dashJumpApex + airJumpApex
    /// 이보다 높은 데서 떨어져야 아프다. 뛰어서는 닿지 않는다 —
    /// 마우스로 들어 올렸을 때만 해당한다. 점프를 손대면 이 값이 같이 올라간다
    static let hurtDropHeight = maxJumpHeight * 1.4

    init(id: String, name: String, isLocal: Bool) {
        self.id = id
        self.displayName = name
        self.isLocal = isLocal
        self.depthBias = CGFloat(stableHash(id) % 997) / 1000
        super.init()

        shadowStep = -1
        shadow.zPosition = -2
        addChild(shadow)

        image.anchorPoint = CGPoint(x: 0.5, y: 0)
        addChild(image)

        label.fontSize = 10
        label.fontColor = .white
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: 0, y: spriteDisplaySize / 2 + 2)
        addChild(label)

        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    private var sheet = Characters.Sheet(size: .zero, bodyWidth: 16,
                                        footPadding: 0, frames: [:])

    private(set) var look = Look.neutral

    func apply(_ look: Look) {
        self.look = look
        sheet = Characters.sheet(look)
        shadowStep = -1   // 몸 너비가 달라졌다. 높이 단계가 그대로여도 다시 만들어야 한다
        image.size = CGSize(width: sheet.size.width * 2, height: sheet.size.height * 2)
        // 칸 아래 빈 줄만큼 내려야 발이 바닥선에 닿는다
        image.position = CGPoint(x: 0, y: -spriteDisplaySize / 2 - sheet.footPadding * 2)
        image.texture = sheet.frames[.idle]?.first
        renderedAnimation = nil
        renderedFrame = -1
    }

    /// 방향키를 누르고 있는 정도에 따라 제자리·걷기·대시 순으로 높이 뛴다.
    /// 두 번째는 떨어지던 속도를 지우고 다시 차오른다
    func jump() {
        guard isLocal, !isDragging, jumpsUsed < CharacterNode.maxJumps else { return }
        jumpsUsed += 1
        let apex: CGFloat = jumpsUsed > 1
            ? CharacterNode.airJumpApex
            : (holding == 0 ? CharacterNode.jumpApex
               : (isDashing ? CharacterNode.dashJumpApex : CharacterNode.walkJumpApex))
        verticalSpeed = (2 * CharacterNode.gravity * apex).squareRoot()
    }

    /// 조종 입력을 받는다. 공중에서도 방향을 바꿀 수 있다.
    func hold(_ direction: CGFloat, dash: Bool) {
        holding = direction
        isDashing = dash && direction != 0
        face(direction)
    }

    /// 화면 구성이 바뀌어 자리를 옮긴다. 이동한 것으로 세지 않는다.
    /// 그러면 대시 동작이 나오고 피격 판정까지 성립한다
    func teleport(to newX: CGFloat) {
        x = newX
        previousX = newX
    }

    /// 집어 드는 순간 진행 중이던 운동을 지운다. 방향키는 지우지 않는다 —
    /// 누르고 있으면 놓는 순간부터 그쪽으로 가는 것이 맞다.
    /// 조종을 끝내면 Control 이 직접 지운다
    /// 놓는 순간의 높이부터 낙하로 센다. 들고 다니며 지나간 최고점은 떨어진 것이 아니다
    func endDrag() {
        isDragging = false
        peakY = y
    }

    func beginDrag() {
        isDragging = true
        verticalSpeed = 0
        jumpsUsed = 0
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
        isDashing = false
        // 맞으면 올라가던 힘이 사라진다. 떨어지던 중이면 그대로 둔다
        verticalSpeed = min(verticalSpeed, 0)
    }

    @discardableResult
    func setRemoteTarget(x newX: CGFloat, y newY: CGFloat,
                         sent: TimeInterval? = nil, at now: TimeInterval) -> Bool {
        // 순서가 뒤바뀌어 옛 좌표가 늦게 왔다. 최신만 쓴다
        if let sent, let previous = lastSentTime, sent <= previous { return false }
        lastSeen = now
        if let sent { lastSentTime = sent }

        // 같은 자리를 다시 알려 온 것은 살아 있다는 뜻뿐이다
        if let last = samples.last, last.x == newX, last.y == newY {
            wasStill = true
            lastArrival = now
            return true
        }
        // 서 있던 구간의 간격을 지연에 반영하면 움직이기 시작할 때 반 초 늦게 보인다
        if lastArrival > 0, !wasStill {
            gaps.append((now, now - lastArrival))
        }
        lastArrival = now

        // 도착 시각으로 놓으면 망의 흔들림이 재생에 그대로 실린다. 상대가 보낸
        // 시각 위에 놓되, 시계 원점이 다르므로 가장 빨리 온 것으로 차이를 잡는다
        var stamp = now
        if let sent {
            offsets.append(now - sent)
            if offsets.count > 30 { offsets.removeFirst() }
            let candidate = sent + (offsets.min() ?? 0)
            // 상대가 자다 깨면 시계가 튄다. 그때는 도착 시각으로 돌아간다
            if abs(candidate - now) <= CharacterNode.stillGap { stamp = candidate }
            else { offsets.removeAll() }
        }
        // 보내는 쪽이 서 있느라 건너뛴 구간이다. 한 구간으로 이으면 재생 시각이
        // 그 안에 갇혀, 걷기 시작할 때 튀었다가 멈춘 것처럼 보인다
        if let last = samples.last, stamp - last.t > CharacterNode.stillGap {
            samples[samples.count - 1].t = stamp - positionInterval
        }
        wasStill = false
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
        // 표본 시각은 늘 앞으로만 간다. 시계 차이가 줄면 뒤로 갈 수 있다
        if let last = samples.last { stamp = max(stamp, last.t + 0.001) }
        samples.append((stamp, newX, newY))
        if samples.count > 8 { samples.removeFirst(samples.count - 8) }
        return true
    }

    /// 한 위치 메시지에 실린 값은 한 스냅샷이다. 송신 시각이 오래됐으면 자세까지
    /// 전부 버려 위치와 행동이 서로 다른 패킷에서 섞이지 않게 한다.
    @discardableResult
    func applyRemoteSnapshot(x: CGFloat, y: CGFloat, bowing: Bool, dragging: Bool,
                             facing direction: Int?, sent: TimeInterval?, at now: TimeInterval) -> Bool {
        guard setRemoteTarget(x: x, y: y, sent: sent, at: now) else { return false }
        isBowing = bowing
        if let direction { faceAsTold(CGFloat(direction)) }
        if dragging { isDragging = true }
        else if isDragging { endDrag() }
        return true
    }

    func update(dt: TimeInterval, now: TimeInterval, strip: FloorStrip) {
        if isLocal {
            simulate(dt: dt, now: now, strip: strip)
        } else {
            interpolate(now: now, dt: dt)
        }
        // 낙하 피격은 소유자만 판정해 hit 메시지로 알린다. 원격 노드의 높이는
        // 보간 결과라 실제 궤적과 다르고, 여기서 다시 판정하면 화면마다 결과가 갈린다.
        if isLocal {
            peakY = max(peakY, y)
            detectLanding(now: now)
        }
        expireBubble(now: now)

        let moved = x - previousX
        previousX = x
        // 내 캐릭터는 입력이 방향을 정한다. 원격은 움직임으로 읽는다
        if !isLocal, !facingTold, !isDragging, abs(moved) > 0.1 { face(moved) }
        let speed = abs(moved) / CGFloat(max(dt, 0.001))

        let running = !isDragging && now >= hurtUntil && y <= 0
            && speed > CharacterNode.dashAnimationThreshold

        let animation: Animation
        if isDragging { animation = .idle }          // 들려 있는 동안은 가만히 서 있는다
        else if now < hurtUntil { animation = .hurt }
        else if y > 0 { animation = .jump }
        else if isBowing { animation = isWalking ? .dash : .bow }
        else if running { animation = .dash }
        else if isWalking { animation = .walk }
        else { animation = .idle }

        if !isDragging { walkPhase += dt }
        if let textures = sheet.frames[animation], !textures.isEmpty {
            // 기어갈 때는 달리기 그림을 천천히 넘긴다
            let fps = isBowing && animation == .dash ? CharacterNode.crawlFPS : animation.fps
            let index = isDragging ? 0 : Int(walkPhase * fps) % textures.count
            if animation != renderedAnimation || index != renderedFrame {
                image.texture = textures[index]
                renderedAnimation = animation
                renderedFrame = index
            }
        }
    }

    private func simulate(dt: TimeInterval, now: TimeInterval, strip: FloorStrip) {
        isWalking = false
        guard !isDragging else { return }
        let step = CGFloat(dt)
        // 맞은 동안에는 조종만 막는다. 중력까지 멈추면 공중에 떠 있는다
        let hurt = now < hurtUntil
        if !hurt {
            // 웅크린 채로는 천천히 기어간다
            let crouching = isBowing && y <= 0 && verticalSpeed == 0
            let speed = crouching ? CharacterNode.crawlSpeed
                : (isDashing ? CharacterNode.dashSpeed : CharacterNode.walkSpeed)
            x = strip.clamp(x + holding * speed * step)
        }

        if y > 0 || verticalSpeed != 0 {
            y += verticalSpeed * step - 0.5 * CharacterNode.gravity * step * step
            verticalSpeed -= CharacterNode.gravity * step
            if y <= 0 { y = 0; verticalSpeed = 0; jumpsUsed = 0 }
            return
        }
        isWalking = !hurt && holding != 0
    }

    /// 렌더 시각을 감싸는 두 표본 사이를 재생한다. 앞뒤를 다 쥐고 있으므로 추정하지 않는다.
    /// 표본이 끊기면 마지막 자리에 세워 둔다
    private func interpolate(now: TimeInterval, dt: TimeInterval) {
        guard let last = samples.last else { return }
        // 재는 시각 순으로 쌓이므로 앞에서부터 버린다
        while let first = gaps.first, now - first.at > CharacterNode.gapMemory {
            gaps.removeFirst()
        }
        let worst = gaps.reduce(0) { max($0, $1.gap) }
        let target = min(CharacterNode.delayRange.upperBound,
                         max(CharacterNode.delayRange.lowerBound, worst + 1.0 / 30))
        let step = CharacterNode.delaySlew * dt
        renderDelay += max(-step, min(step, target - renderDelay))
        let renderAt = now - renderDelay
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
    /// 프레임 타이밍과 무관하게 로컬 캐릭터에서 안정적으로 판정된다.
    /// 마지막 프레임의 높이로 계산하면 착지 직전 프레임이 어디에 걸리느냐에 따라
    /// 같은 높이에서 떨어져도 결과가 널뛴다.
    private func detectLanding(now: TimeInterval) {
        // 드래그 중에는 착지가 아니다. 커서를 바닥으로 내리면 낙하로 오인한다
        guard !isDragging else {
            wasAirborne = y > 0
            return
        }
        let airborne = y > 0
        // 속도로 바꿔 견줄 이유가 없다. 높이가 높을수록 충격도 크다
        if wasAirborne && !airborne, peakY > CharacterNode.hurtDropHeight { takeHit(now: now) }
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
        zPosition = x + depthBias
        // 스프라이트는 오른쪽을 보고 그려져 있다
        image.xScale = facing
        updateNameLabel()
    }

    /// 이름이 바뀔 때만 배경을 다시 만든다
    private func updateNameLabel() {
        guard renderedName != displayName else { return }
        renderedName = displayName
        // 여럿이 돌아다니면 어느 것이 내 것인지 바로 알아야 한다. 참가자 목록과 같은 말을 쓴다
        label.text = isLocal ? "\(displayName) (나)" : displayName

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

/// 말풍선 최대 폭. 캐릭터가 40pt 라 이보다 넓으면 누가 말하는지 흐려진다
private let bubbleMaxWidth: CGFloat = 100

extension CharacterNode {
    func showBubble(text: String, now: TimeInterval) {
        bubbleNode?.removeFromParent()

        let label = SKLabelNode(fontNamed: "Helvetica")
        label.text = text
        label.fontSize = 11
        label.fontColor = .black
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = bubbleMaxWidth
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        let padding: CGFloat = 6
        let size = CGSize(width: min(bubbleMaxWidth, label.frame.width) + padding * 2,
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
        bubbleNode = bubble
        bubbleUntil = now + 5
    }

    /// SKAction 으로 지우면 노드가 씬에서 빠져 있는 동안 시간이 흐르지 않아 말풍선이 남는다
    func expireBubble(now: TimeInterval) {
        guard bubbleUntil != 0, now >= bubbleUntil else { return }
        bubbleNode?.removeFromParent()
        bubbleNode = nil
        bubbleUntil = 0
    }

    func clampBubble(sceneWidth: CGFloat) {
        guard let bubble = bubbleNode else { return }
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
    /// SpriteKit 시계는 잠금·절전을 거치면 systemUptime 과 몇 분씩 벌어진다. 나머지가 전부
    /// systemUptime 이라 섞으면 tick 이 그만큼 멈추고, 그 사이 화면이 바뀌면 씬이 빈 채 남는다
    override func update(_ currentTime: TimeInterval) {
        World.shared.tick(now: ProcessInfo.processInfo.systemUptime)
    }
}

final class World {
    static let shared = World()

    /// 이 실행에서만 유효하다. 호스트를 이 값으로 정하고, 호스트가 중계하는 좌표마다
    /// 실려 나가므로 UUID 를 통째로 쓰지 않는다 — 50명이면 충돌 확률이 3e-7 이다
    let myID = String(UUID().uuidString.prefix(8))

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
    private(set) var lastTick: TimeInterval = 0
    private var lastPeerSweep: TimeInterval = 0
    private var reportedHurtUntil: TimeInterval = 0
    private var placed = false
    /// 마지막으로 보이던 화면 위 자리. 전환 중에는 화면이 0개로 보고되는 순간이 있어,
    /// 그때 띠에서 다시 계산하면 기억이 사라진다
    private var lastSeen: (global: CGPoint, offset: CGFloat)?

    private init() {
        World.renumberLook()
        let stored = UserDefaults.standard.string(forKey: "name") ?? NSFullUserName()
        me = CharacterNode(id: myID, name: sanitizeName(stored), isLocal: true)
        me.apply(World.myLook)
    }

    /// 10종이던 시절의 번호를 지금 배치로 옮긴다. 염소 5색은 자리가 같아 그대로다.
    /// 5 새 6 양 7 개구리 8 돼지 9 당근개구리 → 각 모양의 원본 자리로 보낸다
    private static func renumberLook() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "lookRenumbered2") else { return }
        defaults.set(true, forKey: "lookRenumbered2")
        guard let data = defaults.data(forKey: "look"),
              let look = try? JSONDecoder().decode(Look.self, from: data),
              let moved = [5: 12, 6: 6, 7: 18, 8: 24, 9: 18][look.design]
        else { return }
        defaults.set(try? JSONEncoder().encode(Look(design: moved)), forKey: "look")
    }

    /// 방 설정을 두는 곳. 테스트가 켜 둔 앱의 방을 지우지 않도록 교체할 수 있다
    static var store = UserDefaults.standard

    /// 들어가 있는 방의 id. nil 이면 혼자다 — 광고도 연결도 하지 않는다.
    /// 다음에 켤 때도 그대로 있으려고 저장한다
    static var myRoom: String? { store.string(forKey: "roomID") }
    /// 보여 주기만 하는 이름. 짝짓기는 id 로 한다
    static var myRoomName: String? { store.string(forKey: "roomName") }

    static func join(room id: String, name: String) {
        ChatLog.shared.clear()
        ChatLog.shared.note("\(name) 방에 들어왔습니다")
        store.set(id, forKey: "roomID")
        store.set(name, forKey: "roomName")
        Presence.shared.room = name
        Net.shared.roomChanged()
    }

    static func leaveRoom() {
        ChatLog.shared.clear()
        store.removeObject(forKey: "roomID")
        store.removeObject(forKey: "roomName")
        Presence.shared.room = nil
        Net.shared.roomChanged()
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
        if !self.strip.frames.isEmpty, let spot = self.strip.place(x: me.x, y: me.y) {
            let frame = self.strip.frames[spot.screenIndex]
            lastSeen = (CGPoint(x: frame.minX + spot.point.x, y: frame.minY + spot.point.y),
                        spot.point.x)
        }

        self.scenes = scenes
        self.strip = strip
        // 화면이 하나도 없는 순간에는 건드리지 않는다. 띠 길이가 0이라 좌표가 전부 0이 된다
        guard !strip.frames.isEmpty else { return }

        if !placed {
            // 주 화면 가운데서 시작한다. 어디서 시작하는지 알 수 있어야 하고,
            // 조금 흩어 놓아야 여럿이 같이 켤 때 겹쳐 서지 않는다
            placed = true
            let main = strip.frames[strip.mainIndex]
            me.teleport(to: strip.onMain(offset: main.width / 2 + .random(in: -120...120)))
        } else if let seen = lastSeen, let back = strip.locate(global: seen.global) {
            // 있던 화면이 남아 있으면 그 자리를 지킨다
            me.teleport(to: strip.clamp(back.x))
        } else if let seen = lastSeen {
            // 있던 화면이 사라졌다. 화면 안에서의 가로 위치를 지켜 주 화면으로 데려온다
            me.teleport(to: strip.onMain(offset: seen.offset))
        }
        me.x = strip.clamp(me.x)
    }

    func beginDrag() { me.beginDrag() }

    func endDrag() { me.endDrag() }

    /// 전역 커서 좌표를 띠 좌표로 바꾼다. 세로는 커서가 있는 화면의
    /// 바닥을 기준으로 잡는다.
    func updateDrag(toGlobal point: CGPoint) {
        guard let spot = strip.locate(global: point) else { return }
        me.x = strip.clamp(spot.x)
        me.y = spot.y
    }

    func tick(now: TimeInterval) {
        guard !scenes.isEmpty else { return }
        // 화면마다 씬이 따로 부르므로 한 프레임에 여러 번 들어온다
        let elapsed = now - lastTick
        guard lastTick == 0 || elapsed >= 1.0 / 70 else { return }
        let dt = lastTick == 0 ? 1.0 / 60 : min(0.25, elapsed)
        lastTick = now

        // 끊긴 피어를 찾는 일은 프레임마다 할 필요가 없다. 먼저 id를 모은 뒤 지워
        // Dictionary를 순회하는 도중 변경하지도 않는다.
        if now - lastPeerSweep >= 1 {
            lastPeerSweep = now
            let expired = peers.compactMap { id, node in
                now - node.lastSeen > World.peerTimeout ? id : nil
            }
            for id in expired { Session.shared.peerGone(id) }
        }

        let count = 1 + peers.count
        if Presence.shared.count != count { Presence.shared.count = count }

        var visible: [(node: CharacterNode, placement: Placement)] = []
        func update(_ node: CharacterNode) {
            node.update(dt: dt, now: now, strip: strip)

            guard let placement = strip.place(x: node.x, y: node.y) else {
                node.removeFromParent()
                return
            }
            let scene = scenes[placement.screenIndex]
            if node.parent !== scene {
                node.removeFromParent()
                scene.addChild(node)
            }
            visible.append((node, placement))
        }
        update(me)
        for node in peers.values { update(node) }

        if me.hurtUntil > reportedHurtUntil {
            reportedHurtUntil = me.hurtUntil
            Session.shared.sendHit()
        }

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
    /// 좌표가 이만큼 끊기면 없는 것으로 본다. 0.1초마다 오므로 넉넉한 값이다
    static let peerTimeout: TimeInterval = 15

    func addPeer(id: String, name: String, look: Look) {
        if peers[id] == nil { ChatLog.shared.joined(name) }
        let node = peers[id] ?? CharacterNode(id: id, name: name, isLocal: false)
        node.lastSeen = ProcessInfo.processInfo.systemUptime
        node.displayName = name
        node.apply(look.sanitized)
        peers[id] = node
    }

    func removePeer(id: String) {
        if let node = peers[id] { ChatLog.shared.gone(node.displayName) }
        peers[id]?.removeFromParent()
        peers[id] = nil
    }

    /// 메뉴는 SwiftUI 가 관찰하는 값이 바뀔 때만 다시 그린다.
    /// 함수를 직접 부르면 앱을 켠 순간의 값이 그대로 굳는다.
    func roster() -> [(id: String, name: String, look: Look, isMe: Bool, isHost: Bool)] {
        let host = Session.shared.hostPeer
        let mine = (me.id, me.displayName, me.look, true, me.id == host)
        let others = peers.values
            .sorted { $0.displayName < $1.displayName }
            .map { ($0.id, $0.displayName, $0.look, false, $0.id == host) }
        return [mine] + others
    }

    func setPeerTarget(id: String, x: CGFloat, y: CGFloat,
                       bowing: Bool, dragging: Bool, facing: Int?, sent: TimeInterval?) {
        guard let node = peers[id] else { return }
        node.applyRemoteSnapshot(x: x, y: y, bowing: bowing, dragging: dragging,
                                 facing: facing, sent: sent,
                                 at: ProcessInfo.processInfo.systemUptime)
    }

    func peerWasHit(id: String) {
        peers[id]?.takeHit(now: ProcessInfo.processInfo.systemUptime)
    }

    func showBubble(id: String, text: String) {
        guard let node = id == myID ? me : peers[id] else { return }
        node.showBubble(text: text, now: ProcessInfo.processInfo.systemUptime)
        ChatLog.shared.add(name: node.displayName, text: text, isMe: id == myID)
    }
}


/// 메뉴가 참가자 수를 따라 바뀌도록 관찰 가능한 값으로 들고 있는다
@Observable final class Presence {
    static let shared = Presence()
    var count = 1
    /// 프로토콜이 달라 연결하지 않은 피어 수
    var otherVersions = 0
    /// 지금 들어가 있는 방 이름. nil 이면 혼자다
    var room = roomDisplayName(id: World.myRoom, name: World.myRoomName)
    /// 내가 중계를 맡았는지. 메뉴가 관찰해야 해서 Session 것을 여기에 복사해 둔다
    var amHost = false
    /// 망에 보이는 방들. 참여하기 목록에 쓴다
    var rooms: [RoomListing] = []
    private init() {}
}
