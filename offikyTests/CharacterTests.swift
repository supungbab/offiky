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
        #expect(Animation.charge.frameCount == 1)
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
        func run(seconds: TimeInterval, gap: TimeInterval) {
            let end = now + seconds
            var nextSample = now
            while now < end {
                if now >= nextSample { node.setRemoteTarget(x: 100, y: 0, at: now); nextSample += gap }
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

    @MainActor @Test func 점프는_바닥에서만_시작한다() {
        let node = node()
        node.jump()
        node.update(dt: 1.0 / 60, now: 0, strip: strip)
        #expect(node.y > 0)
        let rising = node.y
        node.jump()                                   // 공중에서는 다시 뛰지 않는다
        node.update(dt: 1.0 / 60, now: 1.0 / 60, strip: strip)
        #expect(node.y > rising)

        var now = 2.0 / 60
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
