import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Offiky

struct CharacterTests {

    @Test func 모양_5가지에_프리셋_6가지다() {
        #expect(Characters.count == 30)
        #expect(Characters.names.count == 30)
        #expect(Set(Characters.names).count == 30)
        #expect(Characters.count % Characters.colorCount == 0)
        // 같은 모양이 가로 한 줄이다. 줄이 바뀌는 자리에서만 앞이름이 바뀐다
        for index in 1..<Characters.count {
            let shape = { (i: Int) in Characters.names[i].split(separator: "_")[0] }
            let sameRow = index % Characters.colorCount != 0
            #expect((shape(index) == shape(index - 1)) == sameRow,
                    "\(Characters.names[index - 1]) → \(Characters.names[index])")
        }
    }

    @Test func 애니메이션_프레임_수() {
        #expect(Animation.allCases.count == 6)
        #expect(Animation.bow.frameCount == 1)
        #expect(Animation.idle.frameCount == 4)
        #expect(Animation.walk.frameCount == 6)
        #expect(Animation.hurt.frameCount == 4)
        #expect(Animation.jump.frameCount == 3)
        #expect(Animation.dash.frameCount == 6)
    }

    @Test func 대시가_가장_빠르게_재생된다() {
        #expect(Animation.dash.fps > Animation.walk.fps)
        #expect(Animation.walk.fps > Animation.idle.fps)
    }

    @Test func 모든_캐릭터의_모든_애니메이션이_로드된다() {
        for index in 0..<Characters.count {
            let sheet = Characters.sheet(Look(design: index))
            #expect(sheet.size.width > 0, "\(Characters.names[index]) 크기 0")
            for animation in Animation.allCases {
                let textures = sheet.frames[animation] ?? []
                #expect(textures.count == animation.frameCount,
                        "\(Characters.names[index]) \(animation) 프레임 \(textures.count)개")
            }
        }
    }

    @Test func 고정_해시는_실행과_무관하게_같다() {
        #expect(stableHash("") == 0xcbf29ce484222325)
        #expect(stableHash("a") == 0xaf63dc4c8601ec8c)
    }

    @Test func 범위를_벗어난_번호는_제한된다() {
        #expect(Look(design: 999).sanitized.design == 999 % Characters.count)
        #expect(Look(design: -1).sanitized.design == Characters.count - 1)
    }

    @Test func 기본_외형은_id_로_결정되고_결정적이다() {
        #expect(Look.fallback(for: "peer-1") == Look.fallback(for: "peer-1"))
        let spread = Set((0..<40).map { Look.fallback(for: "peer-\($0)").design })
        #expect(spread.count > 1)
    }

    @Test func 외형은_주고받을_수_있다() throws {
        let look = Look(design: 27)
        let data = try JSONEncoder().encode(look)
        #expect(try JSONDecoder().decode(Look.self, from: data) == look)
        #expect(data.count < 24)
    }
}

struct PeerTimeoutTests {

    @MainActor @Test func 좌표를_받으면_생존_시각이_갱신된다() {
        let node = CharacterNode(id: "x", name: "x", isLocal: false)
        node.setRemoteTarget(x: 10, y: 0, at: 500)
        #expect(node.lastSeen == 500)
        node.setRemoteTarget(x: 20, y: 0, at: 500.1)
        #expect(node.lastSeen == 500.1)
    }

    @MainActor @Test func 제한시간은_전송주기보다_넉넉하다() {
        #expect(World.peerTimeout > snapshotInterval * 100)
    }
}

struct RemoteTests {

    @MainActor @Test func 보간_지연은_도착_간격을_따라간다() {
        let strip = FloorStrip(visibleFrames: [CGRect(x: 0, y: 0, width: 1800, height: 1000)],
                               main: nil)
        let node = CharacterNode(id: "p", name: "p", isLocal: false)
        var now: TimeInterval = 0
        var walked: CGFloat = 100
        func run(seconds: TimeInterval, gap: TimeInterval) {
            let end = now + seconds
            var nextSample = now
            while now < end {
                if now >= nextSample {
                    // 서 있으면 간격을 재지 않는다. 걷는 동안의 도착만 지연에 반영된다
                    walked += 7
                    node.setRemoteTarget(x: walked, y: 0, at: now)
                    nextSample += gap
                }
                node.update(dt: 1.0 / 30, now: now, strip: strip)
                now += 1.0 / 30
            }
        }
        run(seconds: 6, gap: 0.1)                       // 고른 망
        #expect(abs(node.renderDelay - CharacterNode.delayRange.lowerBound) < 0.01)

        run(seconds: 3, gap: 0.3)                       // 흔들리는 망
        #expect(node.renderDelay > 0.3)
        #expect(node.renderDelay <= CharacterNode.delayRange.upperBound)

        run(seconds: 10, gap: 0.1)                      // 다시 고른 망
        #expect(abs(node.renderDelay - CharacterNode.delayRange.lowerBound) < 0.01)
    }

    @MainActor @Test func 공중에서도_움직이는_쪽을_본다() {
        let strip = FloorStrip(visibleFrames: [CGRect(x: 0, y: 0, width: 1800, height: 1000)],
                               main: nil)
        let node = CharacterNode(id: "p", name: "p", isLocal: false)
        #expect(node.facingSign == -1)
        node.setRemoteTarget(x: 100, y: 50, at: 0)
        node.setRemoteTarget(x: 120, y: 50, at: 0.1)
        node.setRemoteTarget(x: 140, y: 50, at: 0.2)
        node.update(dt: 1.0 / 30, now: 0.30, strip: strip)
        node.update(dt: 1.0 / 30, now: 0.35, strip: strip)
        #expect(node.y > 0)
        #expect(node.facingSign == 1)
    }
}

struct ControlTests {

    private let strip = FloorStrip(visibleFrames: [CGRect(x: 0, y: 0, width: 1800, height: 1000)],
                                   main: CGRect(x: 0, y: 0, width: 1800, height: 1000))

    private func node() -> CharacterNode {
        let node = CharacterNode(id: "me", name: "me", isLocal: true)
        node.teleport(to: 900)
        return node
    }

    @MainActor @Test func 입력이_없으면_제자리에_선다() {
        let node = node()
        for _ in 0..<60 { node.update(dt: 1.0 / 60, now: 0, strip: strip) }
        #expect(node.x == 900)
        #expect(node.y == 0)
    }

    @MainActor @Test func 방향키를_누르는_동안_걷는다() {
        let node = node()
        node.hold(1, dash: false)
        for i in 0..<60 { node.update(dt: 1.0 / 60, now: Double(i) / 60, strip: strip) }
        #expect(abs(node.x - (900 + CharacterNode.walkSpeed)) < 2)
        #expect(node.facingSign == 1)

        node.hold(0, dash: false)
        let stopped = node.x
        for i in 0..<60 { node.update(dt: 1.0 / 60, now: 1 + Double(i) / 60, strip: strip) }
        #expect(node.x == stopped)
    }

    @MainActor @Test func 대시가_걷기보다_빠르다() {
        #expect(CharacterNode.dashSpeed > CharacterNode.chargeSpeed)
        #expect(CharacterNode.chargeSpeed > CharacterNode.walkSpeed)
    }

    /// 화면을 꽂았다 빼면 자리를 다시 잡는데, 그때 누르고 있던 방향이 사라지면
    /// 키를 뗐다 다시 누르기 전까지 서 있는다
    @MainActor @Test func 자리를_옮겨도_누르던_방향을_지킨다() {
        let node = node()
        node.hold(1, dash: false)
        node.update(dt: 1.0 / 60, now: 0, strip: strip)
        #expect(node.x > 900)

        node.teleport(to: 500)
        node.update(dt: 1.0 / 60, now: 1.0 / 60, strip: strip)
        #expect(node.x > 500)
    }

    /// 들고 다니는 동안 지나간 높이로 충격을 계산하면, 바닥에 놓아도 아파한다
    @MainActor @Test func 높이_들었다_바닥에_놓으면_아프지_않다() {
        let node = node()
        node.beginDrag()
        node.y = 400                                  // 마우스로 높이 들어 올린다
        node.update(dt: 1.0 / 60, now: 0, strip: strip)
        node.y = 4                                    // 바닥 가까이 내린다
        node.update(dt: 1.0 / 60, now: 1.0 / 60, strip: strip)
        node.endDrag()

        var now = 2.0 / 60
        while node.y > 0, now < 2 { node.update(dt: 1.0 / 60, now: now, strip: strip); now += 1.0 / 60 }
        #expect(node.hurtUntil == 0)
    }

    @MainActor @Test func 높은_곳에서_놓으면_아파한다() {
        let node = node()
        node.beginDrag()
        node.y = 400
        node.update(dt: 1.0 / 60, now: 0, strip: strip)
        node.endDrag()

        var now = 1.0 / 60
        while node.y > 0, now < 2 { node.update(dt: 1.0 / 60, now: now, strip: strip); now += 1.0 / 60 }
        #expect(node.hurtUntil > 0)
    }

    @MainActor @Test func 집었다_놓아도_누르던_방향을_지킨다() {
        let node = node()
        node.hold(1, dash: false)
        node.beginDrag()
        node.update(dt: 1.0 / 60, now: 0, strip: strip)
        #expect(node.x == 900)              // 들려 있는 동안은 움직이지 않는다

        node.isDragging = false
        node.update(dt: 1.0 / 60, now: 1.0 / 60, strip: strip)
        #expect(node.x > 900)
    }

    /// 맞은 동안 중력까지 멈추면 공중에 뜬 채로 0.6초를 보내고 원래 궤적을 이어간다
    @MainActor @Test func 공중에서_맞으면_떨어진다() {
        let node = node()
        node.jump()
        for i in 0..<6 { node.update(dt: 1.0 / 60, now: Double(i) / 60, strip: strip) }
        #expect(node.y > 0)

        let hitAt = 6.0 / 60
        node.takeHit(now: hitAt)
        var highest = node.y
        var now = hitAt
        while node.y > 0, now < hitAt + 2 {
            now += 1.0 / 60
            node.update(dt: 1.0 / 60, now: now, strip: strip)
            #expect(node.y <= highest)          // 맞은 뒤에 다시 올라가지 않는다
            highest = node.y
        }
        #expect(node.y == 0)
        #expect(now < hitAt + 0.6)              // 피격이 끝나기 전에 바닥에 닿는다
    }

    @MainActor @Test func 뛰면_올라갔다_바닥으로_돌아온다() {
        let node = node()
        node.jump()
        node.update(dt: 1.0 / 60, now: 0, strip: strip)
        #expect(node.y > 0)

        var now = 1.0 / 60
        while node.y > 0, now < 3 { node.update(dt: 1.0 / 60, now: now, strip: strip); now += 1.0 / 60 }
        #expect(node.y == 0)
    }

    @MainActor @Test func 띠_밖으로는_나가지_않는다() {
        let node = node()
        node.hold(-1, dash: true)
        for i in 0..<1200 { node.update(dt: 1.0 / 60, now: Double(i) / 60, strip: strip) }
        #expect(node.x == strip.clamp(strip.minX))
    }
}

struct ScreenChangeTests {

    /// 노트북(주)이 오른쪽, 보조 모니터가 왼쪽
    private let laptop = CGRect(x: 0, y: 0, width: 1800, height: 1000)
    private let external = CGRect(x: -2560, y: 0, width: 2560, height: 1440)

    @MainActor private func attach(_ frames: [CGRect]) {
        World.shared.attach(scenes: [],
                            strip: FloorStrip(visibleFrames: frames, main: frames.isEmpty ? nil : laptop))
    }

    /// 띠는 [보조 0~2560][노트북 2560~4360] 이다.
    /// 노트북 위 300 지점은 띠 좌표 2860 이고, 보조를 빼면 300 이 되어야 한다.
    @MainActor @Test func 보조_화면을_빼도_주_화면의_자리를_지킨다() {
        attach([external, laptop])
        World.shared.me.teleport(to: 2860)
        attach([laptop])
        #expect(World.shared.me.x == 300)
    }

    @MainActor @Test func 화면이_잠깐_0개로_보고돼도_자리를_지킨다() {
        attach([external, laptop])
        World.shared.me.teleport(to: 2860)
        attach([])                               // 전환 중 한 번 비어서 온다
        attach([laptop])
        #expect(World.shared.me.x == 300)
    }

    @MainActor @Test func 없던_화면이_같은_구성으로_돌아오면_그대로다() {
        attach([external, laptop])
        World.shared.me.teleport(to: 2860)
        attach([])
        attach([external, laptop])
        #expect(World.shared.me.x == 2860)
    }

    @MainActor @Test func 화면_없는_상태가_이어져도_유지된다() {
        attach([external, laptop])
        World.shared.me.teleport(to: 2860)
        for _ in 0..<5 { attach([]) }            // 잠자기처럼 한동안 없을 수 있다
        attach([external, laptop])
        #expect(World.shared.me.x == 2860)
    }

    @MainActor @Test func 자는_사이에_모니터를_꽂아도_자리를_지킨다() {
        attach([laptop])
        World.shared.me.teleport(to: 300)
        attach([])
        attach([external, laptop])               // 자는 사이에 모니터를 꽂았다
        #expect(World.shared.me.x == 2860)
    }

    @MainActor @Test func 뺐다_꽂으면_제자리로_돌아온다() {
        attach([external, laptop])
        World.shared.me.teleport(to: 2860)
        attach([laptop])
        #expect(World.shared.me.x == 300)
        attach([external, laptop])
        #expect(World.shared.me.x == 2860)
    }
}

struct DoubleJumpTests {

    private let strip = FloorStrip(visibleFrames: [CGRect(x: 0, y: 0, width: 1800, height: 1000)],
                                   main: nil)

    /// 뜬 뒤 0.2초에 한 프레임마다 한 번씩, 최대 `jumps` 번까지 누른다
    @MainActor private func peak(pressing jumps: Int) -> CGFloat {
        let node = CharacterNode(id: "me", name: "me", isLocal: true)
        node.teleport(to: 900)
        node.jump()
        var used = 1
        var best: CGFloat = 0
        var now: TimeInterval = 0
        while now < 2 {
            node.update(dt: 1.0 / 60, now: now, strip: strip)
            best = max(best, node.y)
            if used < jumps, node.y > 0, now > 0.2 { node.jump(); used += 1 }
            now += 1.0 / 60
        }
        return best
    }

    @MainActor @Test func 공중에서_한_번_더_뛰면_더_높이_간다() {
        #expect(peak(pressing: 2) > peak(pressing: 1))
    }

    @MainActor @Test func 세_번째는_듣지_않는다() {
        #expect(peak(pressing: 3) == peak(pressing: 2))
    }

    @MainActor @Test func 착지하면_다시_두_번_쓸_수_있다() {
        let node = CharacterNode(id: "me", name: "me", isLocal: true)
        node.teleport(to: 900)
        node.jump(); node.jump()
        var now: TimeInterval = 0
        while now < 3 {                          // 떨어질 때까지 둔다
            node.update(dt: 1.0 / 60, now: now, strip: strip)
            now += 1.0 / 60
        }
        #expect(node.y == 0)
        node.jump()
        node.update(dt: 1.0 / 60, now: now, strip: strip)
        #expect(node.y > 0)
    }
}

struct BowTests {

    private let strip = FloorStrip(visibleFrames: [CGRect(x: 0, y: 0, width: 1800, height: 1000)],
                                   main: nil)

    @MainActor private func node() -> CharacterNode {
        let node = CharacterNode(id: "me", name: "me", isLocal: true)
        node.teleport(to: 900)
        return node
    }

    @MainActor @Test func 웅크리면_걷기보다_느리게_간다() {
        func travel(bowing: Bool) -> CGFloat {
            let node = node()
            node.isBowing = bowing
            node.hold(1, dash: false)
            for i in 0..<60 { node.update(dt: 1.0 / 60, now: Double(i) / 60, strip: strip) }
            return node.x - 900
        }
        #expect(abs(travel(bowing: true) - CharacterNode.crawlSpeed) < 2)
        #expect(travel(bowing: true) < travel(bowing: false))
    }

    @MainActor @Test func 방향키를_놓으면_웅크린_채_멈춘다() {
        let node = node()
        node.isBowing = true
        for i in 0..<60 { node.update(dt: 1.0 / 60, now: Double(i) / 60, strip: strip) }
        #expect(node.x == 900)
    }

    @MainActor @Test func 공중에서는_인사가_걸리지_않는다() {
        let node = node()
        node.jump()
        node.isBowing = true
        node.update(dt: 1.0 / 60, now: 0, strip: strip)
        #expect(node.y > 0)                       // 인사해도 물리는 그대로 돈다
    }

    @Test func 인사는_인사할_때만_실린다() throws {
        let quiet = try JSONEncoder().encode(PosMsg(x: 1, y: nil))
        let bowing = try JSONEncoder().encode(PosMsg(x: 1, y: nil, b: true))
        #expect(!String(decoding: quiet, as: UTF8.self).contains("b"))
        #expect(try JSONDecoder().decode(PosMsg.self, from: bowing).b == true)
        // 옛 메시지에는 값이 없다. 서 있는 것으로 본다
        let old = #"{"t":"pos","x":1}"#
        #expect(try JSONDecoder().decode(PosMsg.self, from: Data(old.utf8)).b == nil)
    }
}

@Suite("들고 다니기")
struct RemoteDragTests {
    private let strip = FloorStrip(visibleFrames: [CGRect(x: 0, y: 0, width: 1800, height: 1000)],
                                   main: CGRect(x: 0, y: 0, width: 1800, height: 1000))

    /// 상대가 캐릭터를 높이 들었다 바닥에 내려놓는 동안 내가 받는 좌표를 그대로 재생한다.
    /// 들려 있다는 것을 같이 보내지 않으면 살살 내려놓아도 피격 동작이 나온다
    @MainActor @Test func 상대가_들고_내려놓으면_아프지_않다() {
        let node = CharacterNode(id: "peer", name: "peer", isLocal: false)
        var now: TimeInterval = 0
        func feed(_ y: CGFloat) {
            node.setRemoteTarget(x: 900, y: y, at: now)
            for _ in 0..<6 { node.update(dt: 1.0 / 60, now: now, strip: strip); now += 1.0 / 60 }
        }
        node.isDragging = true
        for y in stride(from: CGFloat(0), through: 400, by: 40) { feed(y) }
        for y in stride(from: CGFloat(400), through: 0, by: -40) { feed(y) }
        node.endDrag()
        for _ in 0..<40 { feed(0) }
        #expect(node.hurtUntil == 0)
    }

    @MainActor @Test func 상대가_높은_곳에서_놓으면_아파한다() {
        let node = CharacterNode(id: "peer", name: "peer", isLocal: false)
        var now: TimeInterval = 0
        func feed(_ y: CGFloat) {
            node.setRemoteTarget(x: 900, y: y, at: now)
            for _ in 0..<6 { node.update(dt: 1.0 / 60, now: now, strip: strip); now += 1.0 / 60 }
        }
        node.isDragging = true
        feed(300)
        node.endDrag()
        for y in stride(from: CGFloat(300), through: 0, by: -100) { feed(y) }
        for _ in 0..<10 { feed(0) }
        #expect(node.hurtUntil > 0)
    }
}

@Suite("서 있을 때")
struct StillTests {
    private let strip = FloorStrip(visibleFrames: [CGRect(x: 0, y: 0, width: 1800, height: 1000)],
                                   main: nil)

    private func pos(_ x: Double, b: Bool? = nil) -> PosMsg {
        PosMsg(x: x, y: nil, b: b)
    }

    @Test func 바뀐_것이_없으면_보내지_않는다() {
        #expect(!shouldSend(pos(100), last: pos(100), since: 0.1))
    }

    @Test func 처음에는_보낸다() {
        #expect(shouldSend(pos(100), last: nil, since: 0))
    }

    @Test func 한_칸이라도_움직이면_보낸다() {
        #expect(shouldSend(pos(100.5), last: pos(100), since: 0.1))
    }

    /// 자세만 바뀌어도 알려야 상대 화면에서 같이 웅크린다
    @Test func 자리가_같아도_자세가_바뀌면_보낸다() {
        #expect(shouldSend(pos(100, b: true), last: pos(100), since: 0.1))
    }

    @Test func 가만히_있어도_생존_주기마다_보낸다() {
        #expect(!shouldSend(pos(100), last: pos(100), since: keepaliveInterval - 0.01))
        #expect(shouldSend(pos(100), last: pos(100), since: keepaliveInterval))
    }

    @Test func 생존_주기가_제한시간보다_넉넉하다() {
        #expect(keepaliveInterval * 3 < World.peerTimeout)
    }

    /// 서 있던 몇 초가 도착 간격으로 들어가면 움직이기 시작할 때 반 초 늦게 보인다
    @MainActor @Test func 서_있던_구간은_보간_지연을_늘리지_않는다() {
        let node = CharacterNode(id: "p", name: "p", isLocal: false)
        var now: TimeInterval = 0
        var walked: CGFloat = 100

        func step(moving: Bool, gap: TimeInterval, seconds: TimeInterval) {
            let end = now + seconds
            var next = now
            while now < end {
                if now >= next {
                    if moving { walked += 7 }
                    node.setRemoteTarget(x: walked, y: 0, at: now)
                    next += gap
                }
                node.update(dt: 1.0 / 30, now: now, strip: strip)
                now += 1.0 / 30
            }
        }

        step(moving: true, gap: 0.1, seconds: 6)          // 걸어온다
        let walking = node.renderDelay
        #expect(abs(walking - CharacterNode.delayRange.lowerBound) < 0.01)

        step(moving: false, gap: keepaliveInterval, seconds: 12)   // 서 있는다
        step(moving: true, gap: 0.1, seconds: 3)          // 다시 걷는다
        #expect(abs(node.renderDelay - CharacterNode.delayRange.lowerBound) < 0.01)
    }

    @MainActor @Test func 같은_자리를_받아도_살아_있는_것으로_센다() {
        let node = CharacterNode(id: "p", name: "p", isLocal: false)
        node.setRemoteTarget(x: 100, y: 0, at: 0)
        node.setRemoteTarget(x: 100, y: 0, at: 5)
        #expect(node.lastSeen == 5)
    }
}

@Suite("얼굴 방향")
struct FacingTests {
    private let strip = FloorStrip(visibleFrames: [CGRect(x: 0, y: 0, width: 1800, height: 1000)],
                                   main: CGRect(x: 0, y: 0, width: 1800, height: 1000))

    /// 내 캐릭터를 오른쪽으로 끌었다 놓는 동안, 상대가 받는 것을 그대로 재생한다.
    /// 방향을 같이 보내지 않으면 상대 쪽만 놓은 뒤에 혼자 돌아선다
    @MainActor @Test func 끌었다_놓아도_양쪽_방향이_같다() {
        let mine = CharacterNode(id: "me", name: "me", isLocal: true)
        let theirs = CharacterNode(id: "me", name: "me", isLocal: false)
        var now: TimeInterval = 0
        var sent: TimeInterval = -1

        func relay() {
            guard now - sent >= snapshotInterval else { return }
            sent = now
            if mine.isDragging { theirs.isDragging = true }
            else if theirs.isDragging { theirs.endDrag() }
            theirs.faceAsTold(mine.facingSign)
            theirs.setRemoteTarget(x: mine.x, y: mine.y, at: now)
        }

        mine.teleport(to: 100)
        mine.beginDrag()
        for step in 0...40 {
            mine.x = 100 + CGFloat(step) * 10        // 오른쪽으로 400pt 끈다
            mine.update(dt: 1.0 / 60, now: now, strip: strip)
            relay()
            theirs.update(dt: 1.0 / 60, now: now, strip: strip)
            now += 1.0 / 60
        }
        #expect(mine.facingSign == theirs.facingSign)

        mine.endDrag()
        var everMatched = true
        for _ in 0..<120 {                           // 놓은 뒤 2초
            mine.update(dt: 1.0 / 60, now: now, strip: strip)
            relay()
            theirs.update(dt: 1.0 / 60, now: now, strip: strip)
            // 한 프레임이라도 갈리면 깜박인다. 0.1초 뒤 바로잡혀도 보인다
            if mine.facingSign != theirs.facingSign { everMatched = false }
            now += 1.0 / 60
        }
        #expect(everMatched)
    }

    /// 띠 끝에서는 눌러도 움직이지 않는다. 움직임으로 읽으면 상대는 돌아선 것을 모른다
    @MainActor @Test func 벽에_붙어_돌아서도_상대가_안다() {
        let node = CharacterNode(id: "p", name: "p", isLocal: false)
        node.faceAsTold(1)
        for i in 0..<30 { node.setRemoteTarget(x: 100, y: 0, at: Double(i) / 10) }
        #expect(node.facingSign == 1)
    }

    /// 옛 버전은 방향을 싣지 않는다. 그때는 예전처럼 움직임으로 읽는다
    @MainActor @Test func 방향을_안_보내는_상대는_움직임으로_읽는다() {
        let node = CharacterNode(id: "p", name: "p", isLocal: false)
        #expect(node.facingSign == -1)
        var now: TimeInterval = 0
        var walked: CGFloat = 100
        for _ in 0..<40 {
            walked += 7
            node.setRemoteTarget(x: walked, y: 0, at: now)
            for _ in 0..<6 { node.update(dt: 1.0 / 60, now: now, strip: strip); now += 1.0 / 60 }
        }
        #expect(node.facingSign == 1)
    }
}

@Suite("앱 자원")
struct AppResourceTests {
    /// 정보 창이 이 이름으로 읽는다. 시스템이 주는 아이콘은 캐시가 낡으면 옛것이 나온다
    @MainActor @Test func 아이콘을_에셋_이름으로_읽을_수_있다() {
        #expect(NSImage(named: "AppIcon") != nil)
        #expect(NSImage(named: "MenuBarIcon") != nil)
    }
}

@Suite("낙하 피격")
struct FallDamageTests {
    /// 기준이 최고점 바로 위에 있으면, 점프 높이를 조금만 올려도
    /// 2단 점프 착지가 아파진다. 그 관계를 여기서 고정한다
    @Test func 뛰어서_닿는_높이보다_확실히_높다() {
        #expect(CharacterNode.hurtDropHeight > CharacterNode.maxJumpHeight * 1.3)
    }

    @Test func 최고점은_대시_점프에_2단을_더한_것이다() {
        #expect(CharacterNode.maxJumpHeight
                == CharacterNode.dashJumpApex + CharacterNode.airJumpApex)
        #expect(CharacterNode.dashJumpApex > CharacterNode.walkJumpApex)
        #expect(CharacterNode.walkJumpApex > CharacterNode.jumpApex)
    }

    /// 가장 높이 뛰는 방법으로 뛰어도 착지가 아프지 않아야 한다
    @MainActor @Test func 가장_높이_뛰어도_아프지_않다() {
        let strip = FloorStrip(visibleFrames: [CGRect(x: 0, y: 0, width: 1800, height: 1000)],
                               main: nil)
        let node = CharacterNode(id: "me", name: "me", isLocal: true)
        node.teleport(to: 900)
        node.hold(1, dash: true)                       // 대시 점프가 제일 높다
        node.jump()
        var now: TimeInterval = 0
        var used = 1
        var best: CGFloat = 0
        var previous: CGFloat = 0
        while now < 3 {
            node.update(dt: 1.0 / 60, now: now, strip: strip)
            best = max(best, node.y)
            // 더 오르지 않으면 정점이다. 거기서 한 번 더 차야 제일 높이 간다
            if used < 2, node.y > 0, node.y <= previous { node.jump(); used = 2 }
            previous = node.y
            now += 1.0 / 60
        }
        #expect(node.y == 0)
        #expect(best > CharacterNode.maxJumpHeight - 1)   // 실제로 최고점까지 갔다
        #expect(node.hurtUntil == 0)
    }
}
