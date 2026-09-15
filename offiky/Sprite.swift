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
    static let rgb: [UInt32] = [
        0x000000, 0x1D2B53, 0x7E2553, 0x008751,
        0xAB5236, 0x5F574F, 0xC2C3C7, 0xFFF1E8,
        0xFF004D, 0xFFA300, 0xFFEC27, 0x00E436,
        0x29ADFF, 0x83769C, 0xFF77A8, 0xFFCCAA,
    ]
    static let dustIndex = 4
}

struct Sprite: Equatable {
    static let size = 16
    private static let allowed = Set("0123456789abcdef.")

    let rows: [String]

    init?(encoded: String) {
        let lines = encoded.components(separatedBy: "\n")
        guard lines.count == Sprite.size else { return nil }
        for line in lines {
            guard line.count == Sprite.size,
                  line.allSatisfy({ Sprite.allowed.contains($0) })
            else { return nil }
        }
        self.rows = lines
    }

    private init(validatedRows: [String]) { self.rows = validatedRows }

    var encoded: String { rows.joined(separator: "\n") }

    /// 소스 내부 표현. 외부로 전송되지 않는다.
    private static let template = [
        "................",
        ".....######.....",
        "....#HHHHHH#....",
        "...#HHHHHHHH#...",
        "...#HHHHHHHH#...",
        "...#HSSSSSSH#...",
        "...#HSESSESH#...",
        "...#HSSSSSSH#...",
        "....#SSSSSS#....",
        ".....#SSSS#.....",
        "......#SS#......",
        "...#BBBBBBBB#...",
        "..#SBBBBBBBBS#..",
        "..#SBBBBBBBBS#..",
        "...#BBBBBBBB#...",
        "...#WW#..#WW#...",
    ]

    private static let hairColors: [Character] = ["0", "1", "2", "4", "5", "9", "d", "e"]
    private static let shirtColors: [Character] = ["2", "3", "8", "9", "b", "c", "d", "e"]

    static func standard(for id: String) -> Sprite {
        let h = stableHash(id)
        let map: [Character: Character] = [
            ".": ".", "#": "0", "S": "f", "E": "0", "W": "5",
            "H": hairColors[Int(h % 8)],
            "B": shirtColors[Int((h / 8) % 8)],
        ]
        return Sprite(validatedRows: template.map { String($0.map { map[$0] ?? "." }) })
    }

    func cgImage() -> CGImage? {
        let n = Sprite.size
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let index = ch.hexDigitValue, index < Palette.rgb.count else { continue }
                let color = Palette.rgb[index]
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
