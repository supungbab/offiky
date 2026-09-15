import CoreGraphics
import Testing
@testable import offiky

struct SpriteTests {

    @Test func 라운드트립() throws {
        let encoded = Array(repeating: "0123456789abcdef", count: 16).joined(separator: "\n")
        let sprite = try #require(Sprite(encoded: encoded))
        #expect(sprite.encoded == encoded)
    }

    @Test func 투명문자를_허용한다() {
        let encoded = Array(repeating: "................", count: 16).joined(separator: "\n")
        #expect(Sprite(encoded: encoded) != nil)
    }

    @Test func 줄수가_다르면_거부한다() {
        let short = Array(repeating: "0123456789abcdef", count: 15).joined(separator: "\n")
        let long  = Array(repeating: "0123456789abcdef", count: 17).joined(separator: "\n")
        #expect(Sprite(encoded: short) == nil)
        #expect(Sprite(encoded: long) == nil)
    }

    @Test func 글자수가_다르면_거부한다() {
        var rows = Array(repeating: "0123456789abcdef", count: 16)
        rows[7] = "0123456789abcde"
        #expect(Sprite(encoded: rows.joined(separator: "\n")) == nil)
    }

    @Test func 허용되지_않은_문자를_거부한다() {
        for bad in ["g", "A", " ", "#"] {
            var rows = Array(repeating: "0123456789abcdef", count: 16)
            rows[0] = bad + "123456789abcdef"
            #expect(Sprite(encoded: rows.joined(separator: "\n")) == nil, "\(bad) 를 거부해야 한다")
        }
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
