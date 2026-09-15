import CoreGraphics
import Foundation

/// 모든 피어가 같은 색과 초기 위치를 계산해야 하므로 Swift 의 hashValue 를 쓸 수 없다.
/// 그쪽은 프로세스마다 시드가 바뀐다.
func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for byte in s.utf8 {
        h ^= UInt64(byte)
        h = h &* 0x100000001b3
    }
    return h
}

enum Palette {
    /// 편집기의 빠른 선택용 프리셋. 저장 형식과는 무관하다.
    static let presets: [UInt32] = [
        0x000000, 0x1D2B53, 0x7E2553, 0x008751,
        0xAB5236, 0x5F574F, 0xC2C3C7, 0xFFF1E8,
        0xFF004D, 0xFFA300, 0xFFEC27, 0x00E436,
        0x29ADFF, 0x83769C, 0xFF77A8, 0xFFCCAA,
    ]
    static let dust: UInt32 = 0xAB5236
}

struct Sprite: Equatable {
    static let size = 16
    static let transparent = "......"
    private static let hex = Set("0123456789abcdef")

    /// 16줄. 각 줄은 16픽셀 × 6자이며, 픽셀은 `RRGGBB` 이거나 `......`(투명)이다.
    let rows: [String]

    init?(encoded: String) {
        let lines = encoded.components(separatedBy: "\n")
        guard lines.count == Sprite.size else { return nil }
        for line in lines {
            guard line.count == Sprite.size * 6 else { return nil }
            for chunk in Sprite.chunks(of: line) {
                let isTransparent = chunk == Sprite.transparent
                let isColor = chunk.allSatisfy { Sprite.hex.contains($0) }
                guard isTransparent || isColor else { return nil }
            }
        }
        self.rows = lines
    }

    private init(validatedRows: [String]) { self.rows = validatedRows }

    var encoded: String { rows.joined(separator: "\n") }

    static func chunks(of line: String) -> [String] {
        var result: [String] = []
        var index = line.startIndex
        while index < line.endIndex {
            let next = line.index(index, offsetBy: 6)
            result.append(String(line[index..<next]))
            index = next
        }
        return result
    }

    /// nil 은 투명
    func color(x: Int, y: Int) -> UInt32? {
        let chunk = Sprite.chunks(of: rows[y])[x]
        guard chunk != Sprite.transparent else { return nil }
        return UInt32(chunk, radix: 16)
    }

    /// 레퍼런스에서 추출한 기본 캐릭터. 팔레트와 인덱스 격자는 소스 내부 표현이다.
    static let designs: [(palette: [String], rows: [String])] = [
        (palette: ["2d1a71", "409def", "70dbff", "6e6aff", "fbc800", "323821", "dd8c00"], rows: [
            "................",
            "..0000000.......",
            ".00111122000....",
            "0301454144460...",
            "03014541224460..",
            "00014441222440..",
            ".0301111224440..",
            ".0301111120000..",
            "..0001122220....",
            "....01122220....",
            "..0001122220....",
            "..0221122220....",
            "..0011101120....",
            "...001440440....",
            ".....064000.....",
            "......0000......",
        ]),
        (palette: ["353234", "665d5b", "998d86", "fbc800", "cdbfb3", "eae6da"], rows: [
            "...000000000....",
            "0000111222220...",
            "02211111222220..",
            "00113331222220..",
            ".0003001222110..",
            "...03331221000..",
            "...01111222100..",
            "...01111120000..",
            "...004455550....",
            "....04455550....",
            "...004005550....",
            "...054220450....",
            "...001110550....",
            ".....000020.....",
            ".......010......",
            ".......00.......",
        ]),
        (palette: ["0e3e12", "fbc800", "6cb328", "afe356", "fff699"], rows: [
            "....0000...00...",
            "....011100010...",
            "...0200133300...",
            "...0211133310...",
            "...0222333330...",
            "...0222333330...",
            "...0222233330...",
            "...0222114000...",
            "...002144440....",
            "....02144440....",
            "....02144440....",
            "...002144440....",
            "...0223011300...",
            "....022033330...",
            "....000000230...",
            ".........000....",
        ]),
        (palette: ["550e2b", "ff424f", "af102e", "fbc800"], rows: [
            "..0000000000....",
            "..01222111110...",
            "..00222211110...",
            "...0303211110...",
            "...0303212220...",
            "...0333210200...",
            "...0222212220...",
            "...0222221000...",
            "...002211110....",
            "...002211110....",
            "...0122111100...",
            "...0022122110...",
            "....021111220...",
            "....02100000....",
            "....020.........",
            "....00..........",
        ]),
        (palette: ["353234", "665d5b", "cdbfb3", "eae6da", "ffffff"], rows: [
            ".00000000.......",
            ".011101110......",
            ".0011000000000..",
            "..0022233333330.",
            "...022223333330.",
            "000044423332220.",
            "032240023332000.",
            "002244423333200.",
            "..0022223333330.",
            "...022222300000.",
            "...002233330....",
            "..0332233330....",
            "..0022202230....",
            "...002330330....",
            ".....023000.....",
            "......0000......",
        ]),
        (palette: ["353234", "665d5b", "cb734d", "efaf79", "ffffff"], rows: [
            ".00000000.......",
            ".011101110......",
            ".0011000000000..",
            "..0022233333330.",
            ".00044423332220.",
            "002240023332000.",
            "032244423333200.",
            "000022223333330.",
            "...022222300000.",
            "...002233330....",
            "..03322333300...",
            "..00222322330...",
            "...0023333220...",
            "....02300000....",
            "....020.........",
            "....00..........",
        ]),
        (palette: ["353234", "665d5b", "ff424f", "af102e", "ffffff"], rows: [
            ".......00000000.",
            "......011101110.",
            "..0000000001100.",
            ".0222222233300..",
            ".03332223444000.",
            ".000322230043300",
            ".003222234443320",
            ".022222233330000",
            ".000002333330...",
            "....022223300...",
            "....0222003220..",
            "....0230223300..",
            "....022033300...",
            ".....020000.....",
            "......030.......",
            ".......00.......",
        ]),
        (palette: ["353234", "998d86", "665d5b", "ffffff"], rows: [
            ".00000000.......",
            ".011101110......",
            ".0011000000000..",
            "..0022211111110.",
            "...022221111110.",
            ".00033321112220.",
            "002230021112000.",
            "012233321111200.",
            "000022221111110.",
            "...022222100000.",
            "...002211110....",
            "..0012201110....",
            "..0122110210....",
            "..0002110210....",
            ".....021000.....",
            ".....0000.......",
        ]),
    ]

    static var designCount: Int { designs.count }

    /// 소스 내부의 팔레트 인덱스 격자를 4.1 의 RRGGBB 형식으로 바꾼다
    static func design(at index: Int) -> Sprite {
        let design = designs[index % designs.count]
        return Sprite(validatedRows: design.rows.map { row in
            row.map { character in
                guard let slot = character.hexDigitValue, slot < design.palette.count
                else { return transparent }
                return design.palette[slot]
            }.joined()
        })
    }

    static func standard(for id: String) -> Sprite {
        design(at: Int(stableHash(id) % UInt64(designs.count)))
    }

    func cgImage() -> CGImage? {
        let n = Sprite.size
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            let chunks = Sprite.chunks(of: rows[y])
            for x in 0..<n {
                guard chunks[x] != Sprite.transparent,
                      let color = UInt32(chunks[x], radix: 16) else { continue }
                let offset = (y * n + x) * 4
                pixels[offset]     = UInt8((color >> 16) & 0xFF)
                pixels[offset + 1] = UInt8((color >> 8) & 0xFF)
                pixels[offset + 2] = UInt8(color & 0xFF)
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    }
}
