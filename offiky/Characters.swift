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

/// 값은 스프라이트 시트의 행 번호다
enum Animation: Int, CaseIterable {
    case idle = 0, walk = 1, hurt = 2, jump = 3, charge = 4, dash = 5

    var frameCount: Int {
        switch self {
        case .idle: 4
        case .walk: 6
        case .hurt: 4
        case .jump: 3
        case .charge: 1
        case .dash: 6
        }
    }

    var fps: Double {
        switch self {
        case .idle: 5
        case .walk: 12
        case .hurt: 14
        case .jump: 11
        case .charge: 1
        case .dash: 18
        }
    }

    /// 달리기로 넘어가기 전에 웅크린 자세를 보여 주는 시간
    static let chargeHold: TimeInterval = 0.1
}

/// 에셋의 스프라이트 시트를 잘라 색을 입힌 텍스처로 만든다
enum Characters {
    /// 모양 5가지 × 색 8가지. 모양이 가로 한 줄이다.
    /// 순서를 바꾸면 쓰던 사람의 캐릭터가 딴것으로 바뀐다
    static let names = [
        "goat_white", "goat_brown", "goat_black", "goat_gold",
        "goat_red", "goat_blue", "goat_green", "goat_orange",
        "sheep_white", "sheep_brown", "sheep_black", "sheep_gold",
        "sheep_red", "sheep_blue", "sheep_green", "sheep_orange",
        "birb_white", "birb_brown", "birb_black", "birb_gold",
        "birb_red", "birb_blue", "birb_green", "birb_orange",
        "frog_white", "frog_brown", "frog_black", "frog_gold",
        "frog_red", "frog_blue", "frog_green", "frog_orange",
        "pig_white", "pig_brown", "pig_black", "pig_gold",
        "pig_red", "pig_blue", "pig_green", "pig_orange"]
    static var count: Int { names.count }
    /// 한 모양이 갖는 색 수. 선택 창의 한 줄 길이이기도 하다
    static let colorCount = 8

    /// 시트는 24x24 칸이 6열 6행이다
    static let columns = 6
    static let rows = 6

    struct Sheet {
        let size: CGSize
        /// 대기 자세의 실제 몸 너비(픽셀). 프레임 폭에는 대시 자세의 여백이 들어 있다
        let bodyWidth: CGFloat
        /// 칸 아래쪽 빈 줄 수(픽셀). 이만큼 내려 놓아야 발이 바닥에 닿는다
        let footPadding: CGFloat
        let frames: [Animation: [SKTexture]]
    }

    private static var cache: [Int: Sheet] = [:]

    static func sheet(_ look: Look) -> Sheet {
        let design = look.sanitized.design
        if let hit = cache[design] { return hit }
        let made = build(design)
        if cache.count > 64 { cache.removeAll() }
        cache[design] = made
        return made
    }

    private static func build(_ design: Int) -> Sheet {
        guard let image = NSImage(named: names[design]),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return Sheet(size: CGSize(width: 16, height: 16), bodyWidth: 16,
                         footPadding: 0, frames: [:])
        }

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

        let frameW = sheetW / columns, frameH = sheetH / rows
        var frames: [Animation: [SKTexture]] = [:]
        for animation in Animation.allCases {
            frames[animation] = (0..<animation.frameCount).compactMap {
                texture(from: pixels, sheetW: sheetW,
                        x: $0 * frameW, y: animation.rawValue * frameH,
                        width: frameW, height: frameH)
            }
        }
        let measured = body(pixels, sheetW: sheetW, width: frameW, height: frameH)
        return Sheet(size: CGSize(width: frameW, height: frameH),
                     bodyWidth: measured.width, footPadding: measured.foot, frames: frames)
    }

    /// 대기 첫 프레임에서 불투명한 픽셀의 가로 범위와 발밑 빈 줄 수를 잰다
    private static func body(_ pixels: [UInt8], sheetW: Int,
                             width: Int, height: Int) -> (width: CGFloat, foot: CGFloat) {
        var first = width, last = -1, bottom = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * sheetW + x) * 4 + 3] > 0 {
                first = min(first, x)
                last = max(last, x)
                bottom = max(bottom, y)
            }
        }
        guard last >= first else { return (CGFloat(width), 0) }
        return (CGFloat(last - first + 1), CGFloat(height - 1 - bottom))
    }

    private static var thumbCache: [Int: NSImage] = [:]

    /// 목록에 쓰는 대기 첫 장. SKTexture.cgImage() 는 부를 때마다 GPU 에서 읽어 오므로
    /// 캐시가 없으면 화면을 다시 그릴 때마다 40장을 새로 만든다 — 실측 192ms
    static func thumbnail(_ look: Look) -> NSImage? {
        let design = look.sanitized.design
        if let hit = thumbCache[design] { return hit }
        let sheet = sheet(look)
        guard let cg = sheet.frames[.idle]?.first?.cgImage() as CGImage? else { return nil }
        let made = NSImage(cgImage: cg, size: sheet.size)
        thumbCache[design] = made
        return made
    }

    // MARK: 그림자

    private static var shadowCache: [String: SKTexture] = [:]

    static func shadowSize(bodyWidth: CGFloat) -> (width: Int, height: Int) {
        // 몸 너비보다 좌우 1픽셀씩 넓게 깔린다
        let w = max(4, Int(bodyWidth)) + 2
        return (w, max(3, Int((bodyWidth * 0.37).rounded())))
    }

    /// 필요한 픽셀 수만큼의 타원을 만든다. 고정 텍스처를 늘리면 배율이 정수가 아니어서
    /// 픽셀 크기가 들쭉날쭉해지고 캐릭터의 격자와 어긋난다.
    static func shadowTexture(_ size: (width: Int, height: Int)) -> SKTexture {
        let key = "\(size.width)x\(size.height)"
        if let hit = shadowCache[key] { return hit }

        var pixels = [UInt8](repeating: 0, count: size.width * size.height * 4)
        let cx = Double(size.width - 1) / 2, cy = Double(size.height - 1) / 2
        let rx = Double(size.width) / 2, ry = Double(size.height) / 2
        for y in 0..<size.height {
            for x in 0..<size.width {
                let dx = (Double(x) - cx) / rx, dy = (Double(y) - cy) / ry
                if dx * dx + dy * dy <= 1 { pixels[(y * size.width + x) * 4 + 3] = 255 }
            }
        }
        let made = texture(from: pixels, sheetW: size.width,
                           x: 0, y: 0, width: size.width, height: size.height)
            ?? SKTexture()
        shadowCache[key] = made
        return made
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
