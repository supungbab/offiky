import CoreGraphics
import Foundation
import Testing
@testable import offiky

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

    /// 주 화면 바로 위에 1000×600. 가로 중심이 같으므로 오른쪽에 잇는다
    private var stacked: FloorStrip {
        let second = CGRect(x: 0, y: 800, width: 1000, height: 600)
        return FloorStrip(visibleFrames: [second, main], main: main)
    }

    @Test func 원점은_주_디스플레이_한가운데다() {
        #expect(single.minX == -500)
        #expect(single.maxX == 500)
    }

    @Test func 오른쪽_화면은_오른쪽에_이어진다() {
        #expect(rightSide.frames.map(\.width) == [1000, 500])
        #expect(rightSide.minX == -500)
        #expect(rightSide.maxX == 1000)
    }

    @Test func 왼쪽_화면은_왼쪽에_이어진다() {
        #expect(leftSide.frames.map(\.width) == [800, 1000])
        #expect(leftSide.minX == -1300)
        #expect(leftSide.maxX == 500)
    }

    @Test func 세로로_붙은_화면은_오른쪽에_이어진다() {
        #expect(stacked.frames.map(\.height) == [800, 600])
        #expect(stacked.maxX == 1500)
    }

    @Test func 원점은_주_화면_한가운데에_놓인다() throws {
        let p = try #require(single.place(x: 0, y: 0))
        #expect(p.screenIndex == 0)
        #expect(p.point.x == 500)
        #expect(p.point.y == 28)
    }

    @Test func 왼쪽_끝과_오른쪽_끝() throws {
        #expect(try #require(single.place(x: -500, y: 0)).point.x == 0)
        #expect(try #require(single.place(x: 500, y: 0)).point.x == 1000)
    }

    @Test func 두번째_화면으로_넘어간다() throws {
        let p = try #require(rightSide.place(x: 700, y: 0))
        #expect(p.screenIndex == 1)
        #expect(p.point.x == 200)
    }

    @Test func 왼쪽_화면의_좌표는_음수다() throws {
        let p = try #require(leftSide.place(x: -1000, y: 0))
        #expect(p.screenIndex == 0)
        #expect(p.point.x == 300)
    }

    @Test func 걸쳐_있으면_표시한다() throws {
        let p = try #require(single.place(x: 515, y: 0))
        #expect(p.screenIndex == 0)
        #expect(p.point.x == 1015)
    }

    @Test func 완전히_벗어나면_표시하지_않는다() {
        #expect(single.place(x: 521, y: 0) == nil)
        #expect(single.place(x: -521, y: 0) == nil)
    }

    @Test func 높이는_화면_안으로_제한된다() throws {
        // 두 번째 화면 높이 600, 스프라이트 40, 바닥 띄움 8 -> 최대 552
        let p = try #require(rightSide.place(x: 700, y: 5000))
        #expect(p.point.y == 8.0 + 20.0 + 552.0)
    }

    @Test func 띠_밖으로_나가지_않는다() {
        #expect(single.clamp(-5000) == -480)
        #expect(single.clamp(5000) == 480)
        #expect(single.clamp(100) == 100)
    }

    /// place 와 locate 가 같은 기준에서 누적하는지 본다.
    /// 어긋나면 잡아 끈 위치가 originOffset 만큼 통째로 밀린다.
    @Test func 좌표와_화면_변환이_왕복한다() throws {
        for strip in [single, rightSide, leftSide, stacked] {
            for x in stride(from: strip.minX + 30, to: strip.maxX - 30, by: 137) {
                let placed = try #require(strip.place(x: x, y: 0))
                let frame = strip.frames[placed.screenIndex]
                let global = CGPoint(x: frame.minX + placed.point.x,
                                     y: frame.minY + placed.point.y)
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
    }
}

struct VersionTests {

    @Test func 같은_버전만_후보가_된다() {
        let result = compatiblePeers([("a", "1"), ("b", "1")])
        #expect(result.ids == ["a", "b"])
        #expect(result.mismatched == 0)
    }

    @Test func 버전이_다르면_빼고_센다() {
        let result = compatiblePeers([("a", "1"), ("b", "2"), ("c", "99")])
        #expect(result.ids == ["a"])
        #expect(result.mismatched == 2)
    }

    /// 버전을 광고하지 않는 피어는 해석할 수 없으므로 연결하지 않는다
    @Test func 버전이_없거나_숫자가_아니면_뺀다() {
        let result = compatiblePeers([("a", nil), ("b", "abc"), ("c", "")])
        #expect(result.ids.isEmpty)
        #expect(result.mismatched == 3)
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

struct ElectionTests {

    @Test func 가장_작은_id_가_호스트다() {
        #expect(electHost(candidates: ["b", "c", "a"], excluded: [], me: "b") == "a")
    }

    @Test func 제외된_피어는_후보에서_빠진다() {
        #expect(electHost(candidates: ["b", "c", "a"], excluded: ["a"], me: "b") == "b")
    }

    @Test func 나는_항상_후보다() {
        #expect(electHost(candidates: [], excluded: [], me: "z") == "z")
        #expect(electHost(candidates: ["a"], excluded: ["a", "z"], me: "z") == "z")
    }

    @Test func 같은_목록이면_전원이_같은_답을_낸다() {
        let seen: Set<String> = ["m", "a", "z"]
        for me in seen {
            #expect(electHost(candidates: seen, excluded: [], me: me) == "a")
        }
    }
}

struct SeqTrackerTests {

    @Test func 처음_본_번호는_받는다() {
        var t = SeqTracker()
        #expect(t.accept(id: "a", seq: 1) == true)
    }

    @Test func 재전송을_한_번만_받는다() {
        var t = SeqTracker()
        #expect(t.accept(id: "a", seq: 7) == true)
        #expect(t.accept(id: "a", seq: 7) == false)
    }

    @Test func 늦게_도착한_오래된_번호를_무시한다() {
        var t = SeqTracker()
        _ = t.accept(id: "a", seq: 10)
        #expect(t.accept(id: "a", seq: 3) == false)
        #expect(t.accept(id: "a", seq: 11) == true)
    }

    @Test func 피어마다_독립이다() {
        var t = SeqTracker()
        _ = t.accept(id: "a", seq: 5)
        #expect(t.accept(id: "b", seq: 1) == true)
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
        let json = #"{"t":"snap","p":[[3,862,48]]}"#
        let env = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8))
        #expect(env.t == "snap")
    }

    @Test func 스냅샷은_번호와_정수_좌표로_싣는다() throws {
        let data = try JSONEncoder().encode(SnapMsg(p: [[7, 862, 48], [3, -120]]))
        #expect(String(decoding: data, as: UTF8.self).contains("[[7,862,48],[3,-120]]"))
        let back = try JSONDecoder().decode(SnapMsg.self, from: data)
        #expect(back.p == [[7, 862, 48], [3, -120]])
    }

    /// id 를 그대로 싣던 때는 같은 인원이 2.8KB 였다
    @Test func 오십명_스냅샷이_1KB_아래다() throws {
        let entries = (0..<50).map { i -> [Int] in
            let x = -4000 + i * 160
            return i % 9 == 0 ? [i, x, 48] : [i, x]
        }
        let data = try JSONEncoder().encode(SnapMsg(p: entries))
        #expect(data.count < 1000)
    }

    @Test func 번호를_모르는_피어의_좌표는_버린다() throws {
        let json = #"{"t":"snap","p":[[99,10],[3]]}"#
        let msg = try JSONDecoder().decode(SnapMsg.self, from: Data(json.utf8))
        #expect(msg.p.count == 2)
        #expect(msg.p[1].count == 1)      // 좌표가 없으면 handleSnap 이 건너뛴다
    }
}
