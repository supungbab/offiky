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

    @Test func 기본_캐릭터_9종이_모두_유효하다() {
        #expect(Sprite.designCount == 9)
        for index in 0..<Sprite.designCount {
            for frame in 0..<Sprite.frameCount {
                let sprite = Sprite.design(at: index, frame: frame)
                #expect(Sprite(encoded: sprite.encoded) == sprite, "\(index)-\(frame) 무효")
                let filled = (0..<16).flatMap { y in (0..<16).compactMap { sprite.color(x: $0, y: y) } }
                #expect(filled.count > 40, "\(index)-\(frame) 비어 있다")
            }
        }
    }

    @Test func 기본_캐릭터는_서로_다르다() {
        let all = Set((0..<Sprite.designCount).map { Sprite.design(at: $0).encoded })
        #expect(all.count == Sprite.designCount)
    }

    @Test func 걷기_두_프레임은_다르다() {
        for index in 0..<Sprite.designCount {
            #expect(Sprite.design(at: index, frame: 0) != Sprite.design(at: index, frame: 1),
                    "\(index)번 두 프레임이 같다")
        }
    }

    @Test func 인덱스는_범위를_넘어도_안전하다() {
        #expect(Sprite.design(at: 99) == Sprite.design(at: 99 % Sprite.designCount))
        #expect(Sprite.design(at: -1) == Sprite.design(at: Sprite.designCount - 1))
    }

    @Test func 색_조정이_반영된다() {
        let plain = Sprite.design(at: 0)
        var tint = Look.neutral
        tint.hue = 0.3
        #expect(Sprite.design(at: 0, frame: 0, tint: tint) != plain)
    }

    @Test func 중립_조정은_원본과_같다() {
        #expect(Sprite.design(at: 3, frame: 0, tint: .neutral) == Sprite.design(at: 3))
    }

    @Test func 범위를_벗어난_조정값은_제한된다() {
        let wild = Look(design: 99, hue: 9, saturation: -3, brightness: 99).sanitized
        #expect(wild.design == 99 % Sprite.designCount)
        #expect(wild.hue == 0.5)
        #expect(wild.saturation == 0)
        #expect(wild.brightness == 1.5)
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
