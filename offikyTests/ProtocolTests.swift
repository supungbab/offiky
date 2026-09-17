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

struct SanitizeTests {

    @Test func 이름을_20자로_자른다() {
        #expect(sanitizeName(String(repeating: "가", count: 30)).count == 20)
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

    @Test func 채팅의_제어문자를_제거한다() {
        #expect(validChat("점심\n먹자") == "점심먹자")
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

    @Test func 종류를_먼저_읽을_수_있다() throws {
        let json = #"{"t":"say","msg":"안녕"}"#
        let env = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8))
        #expect(env.t == "say")
    }

    /// 보내는 사람은 연결이 정한다. id 를 실으면 남을 사칭할 수 있다
    @Test func 좌표와_채팅에는_id_가_없다() throws {
        let pos = String(decoding: try JSONEncoder().encode(PosMsg(x: 1, y: nil)), as: UTF8.self)
        let say = String(decoding: try JSONEncoder().encode(SayMsg(msg: "hi")), as: UTF8.self)
        #expect(!pos.contains("id"))
        #expect(!say.contains("id"))
    }

    @Test func 좌표_한_건이_작다() throws {
        let data = try JSONEncoder().encode(PosMsg(x: 1234.5, y: 48))
        #expect(data.count < 40)
    }

    @Test func hello_는_프로토콜_번호를_싣는다() throws {
        let data = try JSONEncoder().encode(
            HelloMsg(id: "abc", name: "나", look: .neutral))
        let back = try JSONDecoder().decode(HelloMsg.self, from: data)
        #expect(back.pv == protocolVersion)
        #expect(back.id == "abc")
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

@Suite("버전 거르기")
struct CompatiblePeerTests {
    @Test func 같은_버전만_후보가_된다() {
        let seen = compatiblePeers([("철수", "\(protocolVersion)"),
                                    ("영희", "\(protocolVersion + 1)")])
        #expect(seen.ids == ["철수"])
        #expect(seen.mismatched == 1)
    }

    @Test func pv_가_없거나_숫자가_아니면_다른_버전으로_본다() {
        let seen = compatiblePeers([("철수", nil), ("영희", "둘"), ("민수", "")])
        #expect(seen.ids.isEmpty)
        #expect(seen.mismatched == 3)
    }

    /// 같은 사람이 인터페이스마다 따로 보고된다. Wi-Fi 와 이더넷이 함께 켜져 있으면 두 번이다
    @Test func 같은_사람이_두_번_보고돼도_한_명이다() {
        let old = "\(protocolVersion + 1)"
        let seen = compatiblePeers([("철수", old), ("철수", old), ("영희", old)])
        #expect(seen.mismatched == 2)
    }

    @Test func 아무도_없으면_비어_있다() {
        let seen = compatiblePeers([])
        #expect(seen.ids.isEmpty)
        #expect(seen.mismatched == 0)
    }
}
