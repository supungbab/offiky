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

    /// 소스 내부 표현. 외부로 전송되지 않는다.
    private static let template = [
        "................",
        "......#####.....",
        ".....#BBBBB#....",
        "....#BVVVVVB#...",
        "....#VLLVVVV#...",
        "....#VVVVVVV#...",
        "..###VVVVVVB#...",
        ".#BB#VVVVVBB#...",
        ".#BB#BBBBBBB#...",
        ".#BB#BBBBBBB#...",
        ".#BB#BBBBBBB#...",
        "..###BBBBBBB#...",
        "....#BBBBBBB#...",
        "....#BBBBBBB#...",
        "....#BB#.#BB#...",
        "....####.####...",
    ]

    /// 바이저·외곽선·반사광 색을 제외한 12가지
    private static let bodyColors = [
        "1d2b53", "7e2553", "008751", "ab5236",
        "5f574f", "c2c3c7", "ff004d", "ffa300",
        "ffec27", "00e436", "83769c", "ff77a8",
    ]

    static func standard(for id: String) -> Sprite {
        let body = bodyColors[Int(stableHash(id) % UInt64(bodyColors.count))]
        let map: [Character: String] = [
            ".": transparent, "#": "000000", "V": "29adff", "L": "fff1e8", "B": body,
        ]
        return Sprite(validatedRows: template.map { line in
            line.map { map[$0] ?? transparent }.joined()
        })
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
