import CoreGraphics
import Foundation
import Testing
@testable import Offiky

struct FloorStripTests {

    private let main = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private var single: FloorStrip {
        FloorStrip(visibleFrames: [main], main: main)
    }

    /// 주 화면 오른쪽에 500×600
    private var rightSide: FloorStrip {
        let second = CGRect(x: 1000, y: 100, width: 500, height: 600)
        return FloorStrip(visibleFrames: [second, main], main: main)
    }

    /// 주 화면 왼쪽에 800×600
    private var leftSide: FloorStrip {
        let second = CGRect(x: -800, y: 0, width: 800, height: 600)
        return FloorStrip(visibleFrames: [second, main], main: main)
    }

    /// 주 화면 바로 위에 1000×600. 세로로 안 겹치므로 다른 행이고, 아래 행이 먼저다
    private var stacked: FloorStrip {
        let second = CGRect(x: 0, y: 800, width: 1000, height: 600)
        return FloorStrip(visibleFrames: [second, main], main: main)
    }

    @Test func 띠의_양_끝이_첫_화면과_마지막_화면이다() {
        for strip in [single, rightSide, leftSide, stacked] {
            let left = strip.place(x: strip.minX, y: 0)
            #expect(left?.screenIndex == 0)
            #expect(left?.point.x == 0)
            #expect(strip.place(x: strip.maxX, y: 0)?.screenIndex == strip.frames.count - 1)
        }
    }

    /// 보조 화면을 왼쪽에 둔 사람과 오른쪽에 둔 사람은 띠의 구성이 다르다.
    /// 길이만 같으면 같은 x 가 양쪽 모두에서 놓이므로 서로 다 보인다
    @Test func 좌우_배치가_달라도_같은_x_가_놓인다() {
        let left = CGRect(x: -800, y: 0, width: 800, height: 600)
        let right = CGRect(x: 1000, y: 0, width: 800, height: 600)
        let a = FloorStrip(visibleFrames: [left, main], main: main)
        let b = FloorStrip(visibleFrames: [right, main], main: main)
        // 폭이 다른 화면이라 배치 순서가 실제로 갈린다
        #expect(a.frames.map(\.width) != b.frames.map(\.width))
        #expect(a.length == b.length)
        for x in stride(from: CGFloat(0), through: a.length, by: 50) {
            #expect((a.place(x: x, y: 0) == nil) == (b.place(x: x, y: 0) == nil))
        }
    }

    @Test func 같은_행에서는_왼쪽부터_잇는다() {
        #expect(rightSide.frames.map(\.width) == [1000, 500])
        #expect(leftSide.frames.map(\.width) == [800, 1000])
        #expect(rightSide.maxX == 1500)
        #expect(leftSide.maxX == 1800)
    }

    @Test func 세로로_쌓이면_아래_행을_먼저_둔다() {
        #expect(stacked.frames.map(\.minY) == [0, 800])
        #expect(stacked.maxX == 2000)
        #expect(stacked.mainIndex == 0)
    }

    /// 나란히 맞닿은 두 화면 사이로 아래 행의 화면이 끼어들면 안 된다
    @Test func 맞닿은_화면을_갈라놓지_않는다() {
        let a = CGRect(x: -1920, y: 1169, width: 1920, height: 1080)
        let b = CGRect(x: 0, y: 1169, width: 1920, height: 1080)
        let below = CGRect(x: -900, y: 0, width: 1800, height: 1130)   // 가로로는 A·B 사이
        let strip = FloorStrip(visibleFrames: [a, b, below], main: below)

        #expect(strip.frames == [below, a, b])
        #expect(strip.mainIndex == 0)
        // A 와 B 가 띠에서도 이웃이다
        let ia = try! #require(strip.frames.firstIndex(of: a))
        let ib = try! #require(strip.frames.firstIndex(of: b))
        #expect(abs(ia - ib) == 1)
    }

    /// 높이가 어긋나게 나란히 둔 것도 같은 행이다
    @Test func 세로_범위가_조금이라도_겹치면_같은_행이다() {
        let laptop = CGRect(x: 0, y: 0, width: 1800, height: 1130)
        let raised = CGRect(x: 1800, y: 700, width: 2560, height: 1440)
        let strip = FloorStrip(visibleFrames: [raised, laptop], main: laptop)
        #expect(strip.frames == [laptop, raised])
    }

    @Test func 사라진_화면_대신_갈_주_화면을_기억한다() {
        #expect(leftSide.mainIndex == 1)
        #expect(rightSide.mainIndex == 0)
        #expect(single.mainIndex == 0)
    }

    /// 사라진 화면에 있던 가로 위치를 주 화면에 그대로 옮긴다
    @Test func 화면_안_가로_위치를_지켜_주_화면으로_옮긴다() {
        // leftSide: [800(보조), 1000(주)] — 주 화면은 800 부터 시작한다
        #expect(leftSide.onMain(offset: 0) == 800)
        #expect(leftSide.onMain(offset: 300) == 1100)
        #expect(leftSide.onMain(offset: 1000) == 1780)      // 끝은 clamp 된다
    }

    @Test func 주_화면보다_넓은_위치는_안으로_제한한다() {
        // 보조(800)의 오른쪽 끝에 있었어도 주 화면(1000) 밖으로 나가지 않는다
        #expect(leftSide.onMain(offset: 5000) <= leftSide.maxX)
        #expect(leftSide.onMain(offset: -100) == 800)
    }

    @Test func 원점은_첫_화면_왼쪽에_놓인다() throws {
        let p = try #require(single.place(x: 0, y: 0))
        #expect(p.screenIndex == 0)
        #expect(p.point.x == 0)
        #expect(p.point.y == 28)
    }

    @Test func 왼쪽_끝과_오른쪽_끝() throws {
        #expect(try #require(single.place(x: 0, y: 0)).point.x == 0)
        #expect(try #require(single.place(x: 1000, y: 0)).point.x == 1000)
    }

    @Test func 두번째_화면으로_넘어간다() throws {
        let p = try #require(rightSide.place(x: 1200, y: 0))
        #expect(p.screenIndex == 1)
        #expect(p.point.x == 200)
    }

    @Test func 왼쪽에_붙은_화면이_앞에_온다() throws {
        let p = try #require(leftSide.place(x: 300, y: 0))
        #expect(p.screenIndex == 0)
        #expect(p.point.x == 300)
    }

    @Test func 걸쳐_있으면_표시한다() throws {
        let p = try #require(single.place(x: 1015, y: 0))
        #expect(p.screenIndex == 0)
        #expect(p.point.x == 1015)
    }

    @Test func 완전히_벗어나면_표시하지_않는다() {
        #expect(single.place(x: 1021, y: 0) == nil)
        #expect(single.place(x: -21, y: 0) == nil)
    }

    @Test func 높이는_화면_안으로_제한된다() throws {
        // 두 번째 화면 높이 600, 스프라이트 40, 바닥 띄움 8 -> 최대 552
        let p = try #require(rightSide.place(x: 1200, y: 5000))
        #expect(p.point.y == 8.0 + 20.0 + 552.0)
    }

    @Test func 띠_밖으로_나가지_않는다() {
        #expect(single.clamp(-5000) == 20)
        #expect(single.clamp(5000) == 980)
        #expect(single.clamp(100) == 100)
    }

    /// place 와 locate 가 같은 기준에서 누적하는지 본다.
    /// 어긋나면 잡아 끈 위치가 통째로 밀린다.
    @Test func 좌표와_화면_변환이_왕복한다() throws {
        for strip in [single, rightSide, leftSide, stacked] {
            for x in stride(from: strip.minX + 30, to: strip.maxX - 30, by: 137) {
                let spot = try #require(strip.place(x: x, y: 0))
                let frame = strip.frames[spot.screenIndex]
                let global = CGPoint(x: frame.minX + spot.point.x,
                                     y: frame.minY + spot.point.y)
                let back = try #require(strip.locate(global: global))
                #expect(abs(back.x - x) < 0.001, "x=\(x) 에서 \(back.x) 로 돌아왔다")
            }
        }
    }

    @Test func 화면_밖_커서는_무시한다() {
        #expect(single.locate(global: CGPoint(x: -5000, y: 0)) == nil)
    }

    @Test func 화면이_없어도_무너지지_않는다() {
        let empty = FloorStrip(visibleFrames: [], main: nil)
        #expect(empty.length == 0)
        #expect(empty.place(x: 0, y: 0) == nil)
        #expect(empty.clamp(100) == 0)
        #expect(empty.onMain(offset: 100) == 0)
    }
}

struct VersionCompareTests {

    /// 문자열로 비교하면 "2.0.10" 이 "2.0.9" 보다 작게 나온다
    @Test func 자릿수가_늘어도_숫자로_비교한다() {
        #expect(UpdateChecker.isNewer("2.0.10", than: "2.0.9"))
        #expect(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
    }

    @Test func 같거나_낮으면_새_버전이_아니다() {
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.1"))
    }

    @Test func 자릿수가_달라도_비교한다() {
        #expect(UpdateChecker.isNewer("1.1", than: "1.0.9"))
        #expect(!UpdateChecker.isNewer("1.0", than: "1.0.0"))
    }
}

@Suite("릴리스 피드 읽기")
struct ReleaseFeedTests {

    /// 실제 피드 모양. 맨 위 feed 차원의 id 가 먼저 나오는 것이 함정이다
    private let feed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <id>tag:github.com,2008:https://github.com/supungbab/offiky/releases</id>
      <entry>
        <id>tag:github.com,2008:Repository/1372443808/v2.0.0</id>
        <title>Offiky 2.0.0</title>
      </entry>
      <entry>
        <id>tag:github.com,2008:Repository/1372443808/v1.4.2</id>
        <title>Offiky 1.4.2</title>
      </entry>
    </feed>
    """

    /// 피드는 새것부터 나열된다. feed 차원의 id 를 태그로 잘못 읽으면 안 된다
    @Test func 첫_항목의_태그를_읽는다() {
        #expect(UpdateChecker.latestTag(inFeed: feed) == "v2.0.0")
    }

    @Test func 릴리스가_없으면_못_읽는다() {
        let empty = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <id>tag:github.com,2008:https://github.com/supungbab/offiky/releases</id>
        </feed>
        """
        #expect(UpdateChecker.latestTag(inFeed: empty) == nil)
        #expect(UpdateChecker.latestTag(inFeed: "") == nil)
        #expect(UpdateChecker.latestTag(inFeed: "<html>429</html>") == nil)
    }

    /// 태그는 릴리스 페이지 주소에 들어간다. 쓸 수 없는 글자가 있으면 그 항목을
    /// 건너뛰고 다음 항목을 읽는다 — 잘린 조각을 태그로 쓰지 않는다
    @Test func 주소에_못_쓸_태그는_건너뛴다() {
        let bad = feed.replacingOccurrences(of: "/v2.0.0<", with: "/v2 0.0<")
        #expect(UpdateChecker.latestTag(inFeed: bad) == "v1.4.2")
    }

    /// 피드에서 읽은 뒤에도 버전 비교는 그대로다
    @Test func 읽은_태그로_새_버전을_판정한다() throws {
        let tag = try #require(UpdateChecker.latestTag(inFeed: feed))
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        #expect(UpdateChecker.isNewer(latest, than: "1.4.2"))
        #expect(!UpdateChecker.isNewer(latest, than: "2.0.0"))
    }
}

struct SanitizeTests {

    @Test func 이름을_20자로_자른다() {
        #expect(sanitizeName(String(repeating: "가", count: 30)).count == 20)
    }

    @Test func 한_글자가_커도_이름_바이트_제한을_넘지_않는다() {
        let oneHugeCharacter = "a" + String(repeating: "\u{0301}", count: 20_000)
        #expect(oneHugeCharacter.count == 1)
        #expect(sanitizeName(oneHugeCharacter).utf8.count <= Limits.maxNameBytes)
    }

    @Test func 이름의_제어문자를_제거한다() {
        #expect(sanitizeName("Ky\nle\t") == "Kyle")
    }

    @Test func 빈_이름은_물음표가_된다() {
        #expect(sanitizeName("") == "?")
        #expect(sanitizeName("\n\n") == "?")
    }

    @Test func 채팅은_길거나_비면_거부한다() {
        #expect(validChat("") == nil)
        #expect(validChat(String(repeating: "가", count: 201)) == nil)
        #expect(validChat("점심") == "점심")
    }

    @Test func 글자_수는_작아도_바이트가_큰_채팅은_거부한다() {
        let oneHugeCharacter = "a" + String(repeating: "\u{0301}", count: 20_000)
        #expect(oneHugeCharacter.count == 1)
        #expect(validChat(oneHugeCharacter) == nil)
    }

    @Test func ZWJ_로_이은_이모지는_남는다() {
        #expect(validChat("🧑‍💻") == "🧑‍💻")
        #expect(validChat("🧑‍💻 회의") == "🧑‍💻 회의")
        #expect(sanitizeName("👨‍👩‍👧") == "👨‍👩‍👧")
    }

    /// 글자 순서를 뒤집어 이름을 위장할 수 있다. ZWJ 를 남겨도 이건 계속 막는다
    @Test func 방향을_뒤집는_문자는_제거한다() {
        #expect(validChat("점심\u{202E}먹자") == "점심먹자")
        #expect(sanitizeName("Kyle\u{200F}") == "Kyle")
    }

    @Test func 채팅의_제어문자를_제거한다() {
        #expect(validChat("점심\n먹자") == "점심먹자")
    }

    /// 입력란이 이 값으로 자른다. 제어문자 제거는 글자를 늘리지 않으므로
    /// 원본을 자르면 전송에서 길이로 거부되지 않는다
    @Test func 입력에서_자른_채팅은_길이로_거부되지_않는다() {
        let long = clamped(String(repeating: "가", count: 250),
                           maxCount: Limits.maxChat, maxBytes: Limits.maxChatBytes)
        #expect(long.count == Limits.maxChat)
        #expect(validChat(long) == long)

        let heavy = clamped(String(repeating: "a\u{0301}", count: 3_000),
                            maxCount: Limits.maxChat, maxBytes: Limits.maxChatBytes)
        #expect(heavy.utf8.count <= Limits.maxChatBytes)
        #expect(validChat(heavy) == heavy)
    }
}

struct MessageTests {

    @Test func 좌표_메시지를_주고받는다() throws {
        let json = #"{"t":"pos","x":862.5,"y":48}"#
        let msg = try JSONDecoder().decode(PosMsg.self, from: Data(json.utf8))
        #expect(msg.x == 862.5)
        #expect(msg.y == 48)
    }

    @Test func 바닥에_있으면_y_가_없다() throws {
        let json = #"{"t":"pos","x":862.5}"#
        let msg = try JSONDecoder().decode(PosMsg.self, from: Data(json.utf8))
        #expect(msg.y == nil)
    }

    /// 옛 버전이 보낸 좌표에는 이 값이 없다. 그때는 서 있는 것으로 본다
    @Test func 들려_있다는_표시가_없어도_읽힌다() throws {
        let json = #"{"t":"pos","x":100}"#
        let msg = try JSONDecoder().decode(PosMsg.self, from: Data(json.utf8))
        #expect(msg.d == nil)
        #expect(msg.b == nil)
    }

    @Test func 들고_있을_때만_표시를_싣는다() throws {
        let still = String(decoding: try JSONEncoder().encode(PosMsg(x: 1, y: nil)), as: UTF8.self)
        let held = String(decoding: try JSONEncoder().encode(PosMsg(x: 1, y: nil, d: true)),
                          as: UTF8.self)
        #expect(!still.contains("d"))
        #expect(held.contains("\"d\":true"))
    }

    @Test func 종류와_내용을_한_번에_읽는다() throws {
        let json = #"{"t":"say","msg":"안녕"}"#
        let message = try JSONDecoder().decode(IncomingMessage.self, from: Data(json.utf8))
        guard case let .say(msg) = message else {
            Issue.record("say 메시지로 디코딩되지 않았다")
            return
        }
        #expect(msg.msg == "안녕")
    }

    /// 클라이언트가 보내는 것에는 id 가 없다. 포함하면 남을 사칭할 수 있다 —
    /// 호스트는 연결로 보낸 사람을 정하고 중계할 때만 그 값을 채운다
    @Test func 클라이언트가_보내는_좌표와_채팅에는_id_가_없다() throws {
        let pos = String(decoding: try JSONEncoder().encode(PosMsg(x: 1, y: nil)), as: UTF8.self)
        let say = String(decoding: try JSONEncoder().encode(SayMsg(msg: "hi")), as: UTF8.self)
        #expect(!pos.contains("id"))
        #expect(!say.contains("id"))
    }

    @Test func 호스트가_중계한_것에는_보낸_사람이_있다() throws {
        let data = try JSONEncoder().encode(PosMsg(id: "철수", x: 1, y: nil))
        let message = try JSONDecoder().decode(IncomingMessage.self, from: data)
        #expect(message.senderID == "철수")
        #expect(try JSONDecoder()
            .decode(IncomingMessage.self, from: JSONEncoder().encode(PosMsg(x: 1, y: nil)))
            .senderID == nil)
    }

    @Test func 클라이언트가_빠진_것과_정원이_찬_것을_구분한다() throws {
        let bye = try JSONDecoder().decode(IncomingMessage.self,
                                           from: JSONEncoder().encode(ByeMsg(id: "철수")))
        guard case let .bye(msg) = bye else {
            Issue.record("bye 메시지로 디코딩되지 않았다")
            return
        }
        #expect(msg.id == "철수")

        let full = try JSONDecoder().decode(IncomingMessage.self,
                                            from: JSONEncoder().encode(FullMsg()))
        guard case .full = full else {
            Issue.record("full 메시지로 디코딩되지 않았다")
            return
        }
    }

    /// 걷는 동안 초당 열 번, 전원에게 나간다. 붙는 값마다 그만큼 곱해진다
    @Test func 좌표_한_건이_작다() throws {
        let walking = try JSONEncoder().encode(PosMsg(x: 1234.5, y: nil, f: 1, m: 802489529))
        #expect(walking.count < 48)
        let everything = try JSONEncoder().encode(
            PosMsg(x: 1234.5, y: 48, b: true, d: true, f: 1, m: 802489529))
        #expect(everything.count < 76)
    }

    /// 중계하면 id 가 붙는다. UUID 를 통째로 쓰면 그 자리가 한 건의 절반을 넘는다
    @MainActor @Test func 중계한_좌표도_작다() throws {
        #expect(World.shared.myID.count == 8)
        let relayed = try JSONEncoder().encode(
            PosMsg(id: World.shared.myID, x: 1234.5, y: nil, f: 1, m: 802489529))
        #expect(relayed.count < 60)
    }

    @Test func hello_는_프로토콜_번호를_싣는다() throws {
        let data = try JSONEncoder().encode(
            HelloMsg(id: "abc", name: "나", look: .neutral, room: "room-a"))
        let back = try JSONDecoder().decode(HelloMsg.self, from: data)
        #expect(back.pv == protocolVersion)
        #expect(back.id == "abc")
        #expect(back.room == "room-a")
    }

    @Test func 피격_메시지를_구분한다() throws {
        let data = try JSONEncoder().encode(HitMsg())
        let message = try JSONDecoder().decode(IncomingMessage.self, from: data)
        guard case .hit = message else {
            Issue.record("hit 메시지로 디코딩되지 않았다")
            return
        }
    }
}

@Suite("링크 트래픽 정책")
struct LinkTrafficPolicyTests {

    @MainActor @Test func 악수_전에는_방송을_받지_않고_기한이_지나면_만료된다() {
        var policy = LinkTrafficPolicy(startedAt: 10)
        #expect(!policy.canReceiveBroadcast)
        #expect(!policy.handshakeExpired(at: 14.99, timeout: 5))
        #expect(policy.handshakeExpired(at: 15, timeout: 5))

        policy.identify()
        #expect(policy.canReceiveBroadcast)
        #expect(!policy.handshakeExpired(at: 100, timeout: 5))
    }

    @MainActor @Test func 악수_전_메시지가_지나치면_연결을_끊는다() {
        var policy = LinkTrafficPolicy(startedAt: 0)
        for line in 1...Limits.maxPendingLines {
            #expect(policy.decision(linkLines: line, totalLines: line) == .forward)
        }
        #expect(policy.decision(linkLines: Limits.maxPendingLines + 1,
                                totalLines: Limits.maxPendingLines + 1) == .disconnect)
    }

    /// 호스트는 확정 직후 명단을 한 번에 보낸다. 그 첫 줄로 연결을 확정하지만
    /// 판정이 메인 큐를 거쳐 돌아오는 사이 나머지가 다 도착한다 — 클라이언트 몫으로 재면 끊긴다
    @MainActor @Test func 명단이_한_번에_와도_악수_전에_끊기지_않는다() {
        var policy = LinkTrafficPolicy(startedAt: 0, maxLines: Limits.maxRelayedLinesPerSecond,
                                       maxPending: Limits.maxRosterLines)
        // 정원이 찬 방에 들어가면 사람마다 hello 와 좌표가 한 줄씩 온다
        #expect(2 * Limits.maxRoomMembers <= Limits.maxRosterLines)
        for line in 1...Limits.maxRosterLines {
            #expect(policy.decision(linkLines: line, totalLines: line) == .forward)
        }
        #expect(policy.decision(linkLines: Limits.maxRosterLines + 1,
                                totalLines: Limits.maxRosterLines + 1) == .disconnect)
    }

    @MainActor @Test func 링크별_상한을_넘긴_연결만_끊는다() {
        var policy = LinkTrafficPolicy(startedAt: 0)
        policy.identify()
        #expect(policy.decision(linkLines: Limits.maxLinesPerSecond + 1,
                                totalLines: 1) == .disconnect)
    }

    /// 호스트 연결 하나에 전원 몫이 중계되어 온다. 클라이언트 몫으로 재면 호스트를 끊는다
    @MainActor @Test func 호스트_연결은_중계된_양을_견딘다() {
        var policy = LinkTrafficPolicy(startedAt: 0, maxLines: Limits.maxRelayedLinesPerSecond)
        policy.identify()
        let everyoneWalking = Limits.maxRoomMembers * Int(1 / positionInterval)
        #expect(everyoneWalking <= Limits.maxRelayedLinesPerSecond)
        #expect(policy.decision(linkLines: everyoneWalking, totalLines: everyoneWalking)
                == .forward)
        #expect(policy.decision(linkLines: Limits.maxRelayedLinesPerSecond + 1,
                                totalLines: 1) == .disconnect)
    }

    @MainActor @Test func 전역_상한은_연결을_끊지_않고_초과_메시지만_버린다() {
        var policy = LinkTrafficPolicy(startedAt: 0)
        policy.identify()
        #expect(policy.decision(linkLines: 10,
                                totalLines: Limits.maxTotalLinesPerSecond + 1) == .discard)
        #expect(policy.canReceiveBroadcast)
    }
}

@Suite("호스트 뽑기")
struct HostElectionTests {

    /// 뽑는 절차가 없다. 같은 명단을 보면 모두 같은 답을 낸다
    @Test func 방에서_id_가_가장_작은_사람이_호스트다() {
        #expect(electHost(among: ["나무", "가지"], me: "바람") == "가지")
        #expect(electHost(among: ["나무", "바람"], me: "가지") == "가지")
    }

    @Test func 혼자면_내가_호스트다() {
        #expect(electHost(among: [], me: "바람") == "바람")
    }

    /// 호스트가 나가면 남은 사람 중 가장 작은 id 가 호스트가 된다
    @Test func 호스트가_나가면_다음_사람이_호스트가_된다() {
        let everyone: Set = ["가지", "나무", "바람"]
        #expect(electHost(among: everyone.subtracting(["다래"]), me: "다래") == "가지")
        #expect(electHost(among: everyone.subtracting(["가지", "다래"]), me: "다래") == "나무")
        #expect(electHost(among: everyone.subtracting(["가지", "나무", "다래"]), me: "다래")
                == "다래")
    }

    /// 방에 있는 모두가 같은 사람을 가리켜야 연결이 호스트 하나로 모인다
    @Test func 누가_보아도_같은_사람을_가리킨다() {
        let everyone: Set = ["가지", "나무", "바람", "다래"]
        let elected = everyone.map { electHost(among: everyone.subtracting([$0]), me: $0) }
        #expect(Set(elected) == ["가지"])
    }
}

@Suite("호스트 표시", .serialized)
struct HostBadgeTests {

    /// 실제 환경설정에 쓰면 켜 둔 앱의 방이 날아간다. 따로 만든 곳에만 쓰고 지운다
    private func inRoom<T>(_ id: String?, _ body: () -> T) -> T {
        let name = "offiky.tests"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        if let id { suite.set(id, forKey: "roomID") }
        World.store = suite
        defer {
            World.store = .standard
            suite.removePersistentDomain(forName: name)
        }
        return body()
    }

    /// 참가자 목록이 중계를 맡은 사람을 짚어 주는지. 혼자면 내가 호스트다
    @MainActor @Test func 방에_있으면_호스트가_표시된다() {
        inRoom("testroom") {
            let rows = World.shared.roster()
            #expect(rows.first?.isMe == true)
            #expect(rows.first?.isHost == true)
            #expect(Session.shared.hostPeer == World.shared.myID)
        }
    }

    /// 방에 없으면 호스트라는 것이 없다
    @MainActor @Test func 방에_없으면_아무도_호스트가_아니다() {
        inRoom(nil) {
            #expect(Session.shared.hostPeer == nil)
            #expect(World.shared.roster().allSatisfy { !$0.isHost })
        }
    }

    /// 테스트가 실제 환경설정을 건드리면 안 된다 — 이것 때문에 방이 한 번 날아갔다
    @MainActor @Test func 실제_환경설정은_건드리지_않는다() {
        let before = UserDefaults.standard.string(forKey: "roomID")
        inRoom("testroom") { _ = World.shared.roster() }
        #expect(UserDefaults.standard.string(forKey: "roomID") == before)
        #expect(World.store === UserDefaults.standard)
    }
}

@Suite("방 정원")
struct RoomCapacityTests {

    /// 호스트를 포함해 정원까지 받는다. 클라이언트는 마흔아홉이다
    @Test func 호스트를_포함해_쉰_명이다() {
        #expect(Limits.maxRoomMembers == 50)
        #expect(Limits.maxRoomMembers - 1 < Limits.maxLinks)
    }
}

@Suite("현재 방 표시")
struct CurrentRoomTests {

    @Test func 방_id가_없으면_이름만_남아도_참여_중이_아니다() {
        #expect(roomDisplayName(id: nil, name: "옛 이름") == nil)
    }

    @Test func 방_이름이_없으면_id를_대신_보여준다() {
        #expect(roomDisplayName(id: "abcd1234", name: nil) == "abcd1234")
    }

    @Test func 방_id와_이름이_있으면_이름을_보여준다() {
        #expect(roomDisplayName(id: "abcd1234", name: "디자인팀") == "디자인팀")
    }
}

@Suite("사칭")
struct ImpersonationTests {
    /// TXT 레코드에 id 가 그대로 노출되므로 남의 id 를 대고 연결할 수 있다.
    /// 먼저 자리를 잡은 연결이 이겨야 그 사람이 밀려나지 않는다
    @Test func 남이_쓰는_id_는_받지_않는다() {
        let table = ["연결A": "철수", "연결B": "영희"]
        #expect(idIsTaken("철수", by: "공격자", in: table))
        #expect(idIsTaken("영희", by: "공격자", in: table))
        #expect(!idIsTaken("민수", by: "공격자", in: table))
    }

    @Test func 같은_연결이_다시_인사하면_받는다() {
        #expect(!idIsTaken("철수", by: "연결A", in: ["연결A": "철수"]))
    }

    @Test func 빈_표에서는_누구든_받는다() {
        #expect(!idIsTaken("철수", by: "연결A", in: [:]))
    }
}

@Suite("방 고르기")
struct RoomFilterTests {
    private let mine = "aaaa1111"
    private let now = "\(protocolVersion)"

    @Test func 같은_방의_같은_버전만_후보가_된다() {
        let seen = compatiblePeers([("철수", now, mine, "디자인팀"),
                                    ("영희", now, "bbbb2222", "2팀"),
                                    ("민수", "\(protocolVersion + 1)", mine, "디자인팀")],
                                   myRoom: mine)
        #expect(seen.ids == ["철수"])
        #expect(seen.mismatched == 1)
    }

    /// 이름이 아니라 id 로 짝을 짓는다. 같은 이름을 따로 만들면 다른 방이다
    @Test func 이름이_같아도_id_가_다르면_다른_방이다() {
        let seen = compatiblePeers([("철수", now, "bbbb2222", "디자인팀")], myRoom: mine)
        #expect(seen.ids.isEmpty)
        #expect(seen.rooms.count == 1)
    }

    /// 목록에서 어느 쪽인지 고를 수 있어야 한다
    @Test func 이름이_같은_방이_둘이면_코드를_붙인다() {
        let seen = compatiblePeers([("철수", now, "aaaa1111", "디자인팀"),
                                    ("영희", now, "bbbb2222", "디자인팀"),
                                    ("민수", now, "cccc3333", "2팀")],
                                   myRoom: nil)
        let labels = seen.rooms.map(\.label).sorted()
        #expect(labels == ["2팀", "디자인팀 · aaaa", "디자인팀 · bbbb"])
    }

    /// 방에 없으면 아무와도 연결하지 않는다. 그래도 방 목록은 보여야 한다
    @Test func 방에_없으면_혼자다() {
        let seen = compatiblePeers([("철수", now, mine, "디자인팀"),
                                    ("영희", now, "bbbb2222", "2팀")],
                                   myRoom: nil)
        #expect(seen.ids.isEmpty)
        #expect(seen.rooms.count == 2)
    }

    /// 옛 버전은 방을 모른다. 같이 놀 수 없으니 메뉴가 알려 줘야 한다
    @Test func 방을_안_싣는_옛_버전은_다른_버전으로_센다() {
        let seen = compatiblePeers([("철수", "2", nil, nil)], myRoom: mine)
        #expect(seen.ids.isEmpty)
        #expect(seen.mismatched == 1)
        #expect(seen.rooms.isEmpty)
    }

    @Test func pv_가_없거나_숫자가_아니면_다른_버전으로_본다() {
        let seen = compatiblePeers([("철수", nil, mine, "방"), ("영희", "둘", mine, "방"),
                                    ("민수", "", mine, "방")],
                                   myRoom: mine)
        #expect(seen.ids.isEmpty)
        #expect(seen.mismatched == 3)
    }

    /// Wi-Fi 와 이더넷이 함께 켜져 있으면 같은 사람이 두 번 보고된다
    @Test func 같은_사람이_두_번_보고돼도_한_명이다() {
        let old = "\(protocolVersion + 1)"
        let seen = compatiblePeers([("철수", old, mine, "방"), ("철수", old, mine, "방"),
                                    ("영희", old, mine, "방")],
                                   myRoom: mine)
        #expect(seen.mismatched == 2)

        let rooms = compatiblePeers([("철수", now, "bbbb2222", "2팀"),
                                     ("철수", now, "bbbb2222", "2팀")], myRoom: nil).rooms
        #expect(rooms.first?.count == 1)
    }

    @Test func 방_목록은_사람_많은_순이다() {
        let seen = compatiblePeers([("철수", now, "b", "2팀"), ("영희", now, "a", "디자인팀"),
                                    ("민수", now, "a", "디자인팀"), ("수지", now, "c", "1팀")],
                                   myRoom: nil)
        #expect(seen.rooms.map(\.name) == ["디자인팀", "1팀", "2팀"])
        #expect(seen.rooms.first?.count == 2)
    }

    /// 이름을 못 받으면 코드라도 보여 준다. 빈 줄이 뜨면 고를 수가 없다
    @Test func 이름이_없으면_코드를_보여_준다() {
        let seen = compatiblePeers([("철수", now, "abcd1234", nil)], myRoom: nil)
        #expect(seen.rooms.first?.label == "abcd1234")
    }

    @Test func 아무도_없으면_비어_있다() {
        let seen = compatiblePeers([], myRoom: mine)
        #expect(seen.ids.isEmpty)
        #expect(seen.mismatched == 0)
        #expect(seen.rooms.isEmpty)
    }

    @Test func 방_id_는_매번_새로_나온다() {
        #expect(newRoomID() != newRoomID())
        #expect(newRoomID().count == 8)
    }
}

@Suite("방 이름")
struct RoomNameTests {
    /// TXT 한 쌍이 255바이트를 넘으면 리스너가 실패해 아무에게도 안 보인다.
    /// 이모지는 한 글자가 스물다섯 바이트까지 간다 — 글자 수로는 못 막는다
    @Test func 바이트로도_자른다() {
        let name = sanitizeRoom(String(repeating: "🧑", count: 20))   // 한 글자에 4바이트
        #expect(name.utf8.count <= Limits.maxRoomBytes)
        #expect(name.count < 20)
        #expect(!name.isEmpty)
    }

    /// ZWJ 로 이어 붙인 이모지는 남긴다. 바이트 상한이 따로 있어 TXT 는 넘지 않는다.
    /// 글자 순서를 뒤집어 이름을 위장하는 U+202E 는 계속 막는다
    @Test func 이모지는_남기고_방향_문자는_막는다() {
        #expect(sanitizeRoom("👨‍👩‍👧‍👦") == "👨‍👩‍👧‍👦")
        #expect(sanitizeRoom("가\u{202E}나") == "가나")
    }

    @Test func 글자수로도_자른다() {
        #expect(sanitizeRoom(String(repeating: "a", count: 100)).count == Limits.maxRoom)
    }

    @Test func 한글_스무자는_그대로다() {
        let name = String(repeating: "가", count: 20)
        #expect(sanitizeRoom(name) == name)
        #expect(name.utf8.count <= Limits.maxRoomBytes)
    }

    @Test func 자르고도_쪼개진_글자가_없다() {
        let name = sanitizeRoom(String(repeating: "🧑", count: 20))
        #expect(String(decoding: Array(name.utf8), as: UTF8.self) == name)
    }

    @Test func 앞뒤_공백과_제어문자를_없앤다() {
        #expect(sanitizeRoom("  디자인팀\n  ") == "디자인팀")
    }

    /// 빈 이름은 방을 만들지 않겠다는 뜻이다. 사람 이름과 달리 물음표로 바꾸지 않는다
    @Test func 빈_이름은_빈_채로_돌려준다() {
        #expect(sanitizeRoom("   ").isEmpty)
        #expect(sanitizeRoom("").isEmpty)
    }

    /// TXT 는 첫 등호에서만 자른다. 값 안의 등호는 안전하다
    @Test func 등호가_들어가도_된다() {
        #expect(sanitizeRoom("a=b") == "a=b")
    }
}
