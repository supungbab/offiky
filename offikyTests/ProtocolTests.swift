import CoreGraphics
import Foundation
import Testing
@testable import offiky

struct FloorStripTests {

    private var single: FloorStrip {
        FloorStrip(visibleFrames: [CGRect(x: 0, y: 0, width: 1000, height: 800)])
    }

    private var dual: FloorStrip {
        FloorStrip(visibleFrames: [
            CGRect(x: 1000, y: 100, width: 500, height: 600),
            CGRect(x: 0, y: 0, width: 1000, height: 800),
        ])
    }

    @Test func 띠_길이는_폭의_합이다() {
        #expect(single.length == 1000)
        #expect(dual.length == 1500)
    }

    @Test func 정렬은_minX_오름차순이다() {
        #expect(dual.frames.map(\.width) == [1000, 500])
    }

    @Test func 왼쪽_끝은_첫_화면의_왼쪽이다() throws {
        let p = try #require(single.place(x: 0, y: 0))
        #expect(p.screenIndex == 0)
        #expect(p.point.x == 0)
        #expect(p.point.y == 20)
    }

    @Test func 두번째_화면으로_넘어간다() throws {
        let p = try #require(dual.place(x: 1200, y: 0))
        #expect(p.screenIndex == 1)
        #expect(p.point.x == 200)
    }

    @Test func 화면_경계는_앞_화면에_속한다() throws {
        let p = try #require(dual.place(x: 999, y: 0))
        #expect(p.screenIndex == 0)
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
        let p = try #require(dual.place(x: 1200, y: 5000))
        #expect(p.point.y == 20.0 + 560.0)
    }

    @Test func 띠_밖으로_나가지_않는다() {
        #expect(single.clamp(-50) == 20)
        #expect(single.clamp(5000) == 980)
        #expect(single.clamp(500) == 500)
    }

    @Test func 화면이_없어도_무너지지_않는다() {
        let empty = FloorStrip(visibleFrames: [])
        #expect(empty.length == 0)
        #expect(empty.place(x: 0, y: 0) == nil)
        #expect(empty.clamp(100) == 0)
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
        let json = #"{"t":"snap","p":[{"id":"a","x":1}]}"#
        let env = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8))
        #expect(env.t == "snap")
    }
}
