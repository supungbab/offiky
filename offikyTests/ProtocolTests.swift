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
            let left = strip.place(x: 0, y: 0)
            #expect(left?.screenIndex == 0)
            #expect(left?.point.x == 0)
            #expect(strip.place(x: strip.length, y: 0)?.screenIndex == strip.frames.count - 1)
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
        #expect(rightSide.length == 1500)
        #expect(leftSide.length == 1800)
    }

    @Test func 세로로_쌓이면_아래_행을_먼저_둔다() {
        #expect(stacked.frames.map(\.minY) == [0, 800])
        #expect(stacked.length == 2000)
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
        #expect(leftSide.onMain(offset: 5000) <= leftSide.length)
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
            for x in stride(from: 30, to: strip.length - 30, by: 137) {
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

    @Test func 묘비일_때만_k_를_싣는다() throws {
        let alive = String(decoding: try JSONEncoder().encode(PosMsg(x: 1, y: nil)), as: UTF8.self)
        let dead = String(decoding: try JSONEncoder().encode(PosMsg(x: 1, y: nil, k: true)),
                          as: UTF8.self)
        #expect(!alive.contains("\"k\""))
        #expect(dead.contains("\"k\":true"))
    }

    /// 보낸 사람은 연결이 정한다. 메시지에 id 가 있으면 남을 사칭할 수 있다
    @Test func 좌표와_채팅에는_id_가_없다() throws {
        let pos = String(decoding: try JSONEncoder().encode(PosMsg(x: 1, y: nil)), as: UTF8.self)
        let say = String(decoding: try JSONEncoder().encode(SayMsg(msg: "hi")), as: UTF8.self)
        #expect(!pos.contains("id"))
        #expect(!say.contains("id"))
    }

    @Test func 입력_중인_것을_읽는다() throws {
        let typing = try JSONDecoder().decode(IncomingMessage.self,
                                              from: JSONEncoder().encode(TypingMsg()))
        guard case .typing = typing else {
            Issue.record("typing 메시지로 디코딩되지 않았다")
            return
        }
    }

    @Test func 정원이_찬_것을_읽는다() throws {
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

    @Test func hello_는_프로토콜_번호를_싣는다() throws {
        let data = try JSONEncoder().encode(
            HelloMsg(id: "abc", name: "나", look: .neutral, ch: 3, since: 1))
        let back = try JSONDecoder().decode(HelloMsg.self, from: data)
        #expect(back.pv == protocolVersion)
        #expect(back.id == "abc")
        #expect(back.ch == 3)
    }

    @Test func 피격_메시지를_구분한다() throws {
        let data = try JSONEncoder().encode(HitMsg())
        let message = try JSONDecoder().decode(IncomingMessage.self, from: data)
        guard case .hit = message else {
            Issue.record("hit 메시지로 디코딩되지 않았다")
            return
        }
        let rammed = try JSONDecoder().decode(IncomingMessage.self,
                                              from: JSONEncoder().encode(HitMsg(rammed: "abc")))
        guard case let .hit(msg) = rammed else { Issue.record("hit 메시지로 디코딩되지 않았다"); return }
        #expect(msg.rammed == "abc")
        let old = try JSONDecoder().decode(IncomingMessage.self, from: Data(#"{"t":"hit"}"#.utf8))
        guard case let .hit(plain) = old else { Issue.record("hit 메시지로 디코딩되지 않았다"); return }
        #expect(plain.rammed == nil)
    }
}

@Suite("링크 트래픽 정책")
struct LinkTrafficPolicyTests {

    @MainActor @Test func 악수_전에는_방송을_받지_않고_기한이_지나면_만료된다() {
        var policy = LinkTrafficPolicy(startedAt: 10)
        #expect(!policy.isIdentified)
        #expect(!policy.handshakeExpired(at: 14.99, timeout: 5))
        #expect(policy.handshakeExpired(at: 15, timeout: 5))

        policy.identify()
        #expect(policy.isIdentified)
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

    @MainActor @Test func 링크별_상한을_넘긴_연결만_끊는다() {
        var policy = LinkTrafficPolicy(startedAt: 0)
        policy.identify()
        #expect(policy.decision(linkLines: Limits.maxLinesPerSecond + 1,
                                totalLines: 1) == .disconnect)
    }

    @MainActor @Test func 전역_상한은_연결을_끊지_않고_초과_메시지만_버린다() {
        var policy = LinkTrafficPolicy(startedAt: 0)
        policy.identify()
        #expect(policy.decision(linkLines: 10,
                                totalLines: Limits.maxTotalLinesPerSecond + 1) == .discard)
        #expect(policy.isIdentified)
    }
}

@Suite("환경설정 분리", .serialized)
struct PreferenceIsolationTests {

    /// 실제 환경설정에 쓰면 켜 둔 앱의 채널이 바뀐다. 따로 만든 곳에만 쓰고 지운다
    private func inChannel<T>(_ channel: Int?, _ body: () -> T) -> T {
        let name = "offiky.tests"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        if let channel { suite.set(channel, forKey: "channel") }
        World.store = suite
        defer {
            World.store = .standard
            suite.removePersistentDomain(forName: name)
        }
        return body()
    }

    /// 테스트가 실제 환경설정을 건드리면 안 된다 — 이것 때문에 방 설정이 한 번 삭제됐다
    @MainActor @Test func 실제_환경설정은_건드리지_않는다() {
        let before = UserDefaults.standard.object(forKey: "channel") as? Int
        inChannel(7) { _ = World.shared.roster() }
        #expect(UserDefaults.standard.object(forKey: "channel") as? Int == before)
        #expect(World.store === UserDefaults.standard)
    }

    @MainActor @Test func 처음이거나_범위를_벗어나면_1채널이다() {
        #expect(inChannel(nil) { World.myChannel } == 1)
        #expect(inChannel(Limits.channels + 1) { World.myChannel } == 1)
        #expect(inChannel(7) { World.myChannel } == 7)
    }
}

@Suite("채널 정원")
struct ChannelCapacityTests {

    /// 모두 서로 직접 연결하므로 좌표 건수가 인원의 제곱으로 는다. Wi-Fi AP 하나가 감당하는 선으로 제한한다
    @Test func 나를_포함해_열다섯_명이다() {
        #expect(Limits.maxChannelMembers == 15)
        #expect(Limits.maxChannelMembers - 1 < Limits.maxLinks)
        #expect((Limits.maxChannelMembers - 1) * Limits.maxLinesPerSecond <= Limits.maxTotalLinesPerSecond)
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

    @Test func 정원을_넘으면_가장_늦게_들어온_사람이_나간다() {
        let room = [("가", 1), ("나", 2), ("다", 3)].map { (id: $0.0, since: $0.1) }
        #expect(overflowing(room, limit: 3) == nil)
        #expect(overflowing(room + [(id: "라", since: 4)], limit: 3) == "라")
        #expect(overflowing(room + [(id: "라", since: 0)], limit: 3) == "다")
        // 같은 시각이면 id 로 판정해 모두 같은 사람을 고른다
        #expect(overflowing(room + [(id: "마", since: 3)], limit: 3) == "마")
    }
}

@Suite("채널 고르기")
struct ChannelFilterTests {
    private let now = "\(protocolVersion)"

    @Test func 같은_채널의_같은_버전만_후보가_된다() {
        let seen = compatiblePeers([("철수", now, "1"), ("영희", now, "2"),
                                    ("민수", "\(protocolVersion + 1)", "1")],
                                   myChannel: 1)
        #expect(seen.ids == ["철수"])
        #expect(seen.mismatched == 1)
        #expect(seen.counts == [1: 1, 2: 1])
    }

    @Test func 채널이_없거나_범위를_벗어나면_세지_않는다() {
        let seen = compatiblePeers([("철수", now, nil), ("영희", now, "0"),
                                    ("민수", now, "\(Limits.channels + 1)"), ("수지", now, "셋")],
                                   myChannel: 1)
        #expect(seen.ids.isEmpty)
        #expect(seen.counts.isEmpty)
    }

    @Test func pv_가_없거나_숫자가_아니면_다른_버전으로_본다() {
        let seen = compatiblePeers([("철수", nil, "1"), ("영희", "둘", "1"), ("민수", "", "1")],
                                   myChannel: 1)
        #expect(seen.ids.isEmpty)
        #expect(seen.mismatched == 3)
    }

    /// Wi-Fi 와 이더넷이 함께 켜져 있으면 같은 사람이 두 번 보고된다
    @Test func 같은_사람이_두_번_보고돼도_한_명이다() {
        let old = "\(protocolVersion + 1)"
        let seen = compatiblePeers([("철수", old, "1"), ("철수", old, "1"), ("영희", old, "1")],
                                   myChannel: 1)
        #expect(seen.mismatched == 2)

        let counts = compatiblePeers([("철수", now, "2"), ("철수", now, "2")], myChannel: 1).counts
        #expect(counts[2] == 1)
    }

    @Test func 아무도_없으면_비어_있다() {
        let seen = compatiblePeers([], myChannel: 1)
        #expect(seen.ids.isEmpty)
        #expect(seen.mismatched == 0)
        #expect(seen.counts.isEmpty)
    }

    @Test func 밀려나면_자리가_있는_다음_채널로_간다() {
        let full = Limits.maxChannelMembers
        #expect(nextChannel(after: 1, counts: [:]) == 2)
        #expect(nextChannel(after: 1, counts: [2: full, 3: full]) == 4)
        #expect(nextChannel(after: Limits.channels, counts: [:]) == 1)
    }

    /// 모두 찼으면 다음 번호로 간다. 거기서도 밀려나면 또 다음으로 간다
    @Test func 모두_찼으면_다음_번호로_간다() {
        let counts = Dictionary(uniqueKeysWithValues: (1...Limits.channels).map { ($0, Limits.maxChannelMembers) })
        #expect(nextChannel(after: 5, counts: counts) == 6)
    }
}

struct DatagramTests {

    @Test func 줄_경계에서_자르고_조각마다_토큰을_앞에_적는다() {
        let line = Data(repeating: 0x61, count: 100) + Data([0x0A])
        let prefix = Data("tok\n".utf8)
        let out = datagrams(Array(repeating: line, count: 30).reduce(Data(), +),
                            prefix: prefix)
        #expect(out.count == 3)
        #expect(out.allSatisfy { $0.count <= 1200 && $0.starts(with: prefix) })
        let body = out.map { $0.dropFirst(prefix.count) }.reduce(Data(), +)
        #expect(body.split(separator: 0x0A).count == 30)
    }

    @Test func 토큰_줄에_수신_확인_여부를_적는다() throws {
        for acked in [false, true] {
            let line = udpPrefix(token: "tok", acked: acked).dropLast()
            let read = try #require(readUDPPrefix(Data(line)))
            #expect(read.token == "tok" && read.acked == acked)
        }
    }

    @Test func 빈_입력이면_보내지_않는다() {
        #expect(datagrams(Data(), prefix: Data("t\n".utf8)).isEmpty)
    }

    @Test func 한도보다_긴_줄도_혼자_나간다() {
        let out = datagrams(Data(repeating: 0x61, count: 2000) + Data([0x0A]))
        #expect(out.count == 1)
    }

    @Test func udp_안내를_읽는다() throws {
        let message = try JSONDecoder().decode(IncomingMessage.self,
                                               from: Data(#"{"t":"udp","port":5000,"token":"x"}"#.utf8))
        guard case let .udp(msg) = message else { Issue.record("udp 가 아니다"); return }
        #expect(msg.port == 5000 && msg.token == "x")
    }
}
