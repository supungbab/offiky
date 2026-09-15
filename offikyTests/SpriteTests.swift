import CoreGraphics
import Testing
@testable import offiky

struct SpriteTests {

    private func row(_ pixel: String) -> String {
        String(repeating: pixel, count: 16)
    }

    private func grid(_ pixel: String) -> String {
        Array(repeating: row(pixel), count: 16).joined(separator: "\n")
    }

    @Test func 라운드트립() throws {
        let encoded = grid("ff004d")
        let sprite = try #require(Sprite(encoded: encoded))
        #expect(sprite.encoded == encoded)
    }

    @Test func 투명픽셀을_허용한다() throws {
        let sprite = try #require(Sprite(encoded: grid("......")))
        #expect(sprite.color(x: 0, y: 0) == nil)
    }

    @Test func 색을_읽는다() throws {
        let sprite = try #require(Sprite(encoded: grid("29adff")))
        #expect(sprite.color(x: 3, y: 7) == 0x29ADFF)
    }

    @Test func 줄수가_다르면_거부한다() {
        let short = Array(repeating: row("000000"), count: 15).joined(separator: "\n")
        let long  = Array(repeating: row("000000"), count: 17).joined(separator: "\n")
        #expect(Sprite(encoded: short) == nil)
        #expect(Sprite(encoded: long) == nil)
    }

    @Test func 줄길이가_다르면_거부한다() {
        var lines = Array(repeating: row("000000"), count: 16)
        lines[7] = String(repeating: "000000", count: 15)
        #expect(Sprite(encoded: lines.joined(separator: "\n")) == nil)
    }

    @Test func 허용되지_않은_문자를_거부한다() {
        for bad in ["gg0000", "AA0000", " 00000", "00-000"] {
            var lines = Array(repeating: row("000000"), count: 16)
            lines[0] = bad + String(repeating: "000000", count: 15)
            #expect(Sprite(encoded: lines.joined(separator: "\n")) == nil, "\(bad) 를 거부해야 한다")
        }
    }

    @Test func 투명과_색이_섞인_픽셀을_거부한다() {
        var lines = Array(repeating: row("000000"), count: 16)
        lines[0] = "..0000" + String(repeating: "000000", count: 15)
        #expect(Sprite(encoded: lines.joined(separator: "\n")) == nil)
    }

    @Test func 빈_문자열을_거부한다() {
        #expect(Sprite(encoded: "") == nil)
    }

    @Test func 기본_캐릭터는_유효하고_결정적이다() throws {
        let a = Sprite.standard(for: "peer-1")
        let b = Sprite.standard(for: "peer-1")
        #expect(a == b)
        #expect(Sprite(encoded: a.encoded) == a)
    }

    @Test func 기본_캐릭터의_바이저는_하늘색이다() {
        #expect(Sprite.standard(for: "peer-1").color(x: 7, y: 5) == 0x29ADFF)
    }

    @Test func 기본_캐릭터는_id_에_따라_달라진다() {
        let variants = Set((0..<40).map { Sprite.standard(for: "peer-\($0)").encoded })
        #expect(variants.count > 1)
    }

    @Test func 고정_해시는_실행과_무관하게_같다() {
        #expect(stableHash("") == 0xcbf29ce484222325)
        #expect(stableHash("a") == 0xaf63dc4c8601ec8c)
    }

    @Test func 이미지로_변환된다() throws {
        let image = try #require(Sprite.standard(for: "peer-1").cgImage())
        #expect(image.width == 16)
        #expect(image.height == 16)
    }
}
