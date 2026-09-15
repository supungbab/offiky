import CoreGraphics
import Foundation
import Testing
@testable import offiky

struct CharacterTests {

    @Test func 캐릭터는_9종이다() {
        #expect(Characters.count == 9)
        #expect(Characters.names.count == 9)
    }

    @Test func 애니메이션_프레임_수() {
        #expect(Animation.allCases.count == 5)
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
            let sheet = Characters.sheet(Look(design: index, hue: 0, saturation: 1, brightness: 1))
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

    @Test func 범위를_벗어난_외형값은_제한된다() {
        let wild = Look(design: 99, hue: 9, saturation: -3, brightness: 99).sanitized
        #expect(wild.design == 99 % Characters.count)
        #expect(wild.hue == 0.5)
        #expect(wild.saturation == 0)
        #expect(wild.brightness == 1.5)
    }

    @Test func 음수_인덱스도_안전하다() {
        #expect(Look(design: -1, hue: 0, saturation: 1, brightness: 1).sanitized.design
                == Characters.count - 1)
    }

    @Test func 기본_외형은_id_로_결정되고_결정적이다() {
        #expect(Look.fallback(for: "peer-1") == Look.fallback(for: "peer-1"))
        let spread = Set((0..<40).map { Look.fallback(for: "peer-\($0)").design })
        #expect(spread.count > 1)
    }

    @Test func 외형은_주고받을_수_있다() throws {
        let look = Look(design: 3, hue: 0.25, saturation: 1.4, brightness: 0.9)
        let data = try JSONEncoder().encode(look)
        #expect(try JSONDecoder().decode(Look.self, from: data) == look)
        #expect(data.count < 120)
    }
}
