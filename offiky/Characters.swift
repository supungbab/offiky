import AppKit
import SpriteKit

/// 모든 피어가 같은 값을 계산해야 하므로 Swift 의 hashValue 를 쓸 수 없다.
/// 그쪽은 프로세스마다 시드가 바뀐다.
func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for byte in s.utf8 {
        h ^= UInt64(byte)
        h = h &* 0x100000001b3
    }
    return h
}

enum Animation: Int, CaseIterable {
    case idle = 0, walk = 1, hurt = 2, jump = 3, dash = 4
    var frameCount: Int { [4, 6, 4, 3, 6][rawValue] }
    var fps: Double { [3, 8, 10, 8, 14][rawValue] }
}

/// 에셋의 스프라이트 시트를 잘라 색을 입힌 텍스처로 만든다
enum Characters {
    static let names = ["goat_white", "goat_tan", "goat_gray", "goat_gold", "goat_red",
                        "bird", "goat_ash", "frog", "imp"]
    static var count: Int { names.count }

    struct Sheet {
        let size: CGSize
        let frames: [Animation: [SKTexture]]
    }

    private static var cache: [String: Sheet] = [:]

    static func sheet(_ look: Look) -> Sheet {
        let look = look.sanitized
        let key = "\(look.design)|\(look.hue)|\(look.saturation)|\(look.brightness)"
        if let hit = cache[key] { return hit }
        let made = build(look)
        if cache.count > 64 { cache.removeAll() }
        cache[key] = made
        return made
    }

    private static func build(_ look: Look) -> Sheet {
        guard let image = NSImage(named: names[look.design]),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return Sheet(size: CGSize(width: 16, height: 16), frames: [:]) }

        let sheetW = cg.width, sheetH = cg.height
        var pixels = [UInt8](repeating: 0, count: sheetW * sheetH * 4)
        pixels.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: sheetW, height: sheetH,
                bitsPerComponent: 8, bytesPerRow: sheetW * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(cg, in: CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
        }
        applyTint(&pixels, look)

        let frameW = sheetW / 6, frameH = sheetH / Animation.allCases.count
        var frames: [Animation: [SKTexture]] = [:]
        for animation in Animation.allCases {
            frames[animation] = (0..<animation.frameCount).compactMap {
                texture(from: pixels, sheetW: sheetW,
                        x: $0 * frameW, y: animation.rawValue * frameH,
                        width: frameW, height: frameH)
            }
        }
        return Sheet(size: CGSize(width: frameW, height: frameH), frames: frames)
    }

    /// 픽셀 전체에 같은 HSB 변환을 적용해 명암 관계를 유지한다
    private static func applyTint(_ pixels: inout [UInt8], _ look: Look) {
        guard look.hue != 0 || look.saturation != 1 || look.brightness != 1 else { return }
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            NSColor(srgbRed: CGFloat(pixels[i]) / 255,
                    green: CGFloat(pixels[i + 1]) / 255,
                    blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
                .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            h = (h + CGFloat(look.hue)).truncatingRemainder(dividingBy: 1)
            if h < 0 { h += 1 }
            let shifted = NSColor(hue: h,
                                  saturation: min(1, s * CGFloat(look.saturation)),
                                  brightness: min(1, b * CGFloat(look.brightness)), alpha: 1)
            pixels[i] = UInt8((shifted.redComponent * 255).rounded())
            pixels[i + 1] = UInt8((shifted.greenComponent * 255).rounded())
            pixels[i + 2] = UInt8((shifted.blueComponent * 255).rounded())
        }
    }

    private static func texture(from pixels: [UInt8], sheetW: Int,
                                x: Int, y: Int, width: Int, height: Int) -> SKTexture? {
        var cut = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let from = ((y + row) * sheetW + x) * 4
            cut.replaceSubrange(row * width * 4 ..< (row + 1) * width * 4,
                                with: pixels[from ..< from + width * 4])
        }
        guard let provider = CGDataProvider(data: Data(cut) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }
}
