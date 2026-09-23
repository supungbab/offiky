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
    case idle = 0, walk = 1, hurt = 2, jump = 3, bow = 4, dash = 5

    var frameCount: Int {
        switch self {
        case .idle: 4
        case .walk: 6
        case .hurt: 4
        case .jump: 3
        case .bow: 1
        case .dash: 6
        }
    }

    var fps: Double {
        switch self {
        case .idle: 5
        case .walk: 12
        case .hurt: 14
        case .jump: 11
        case .bow: 1
        case .dash: 18
        }
    }
}

/// 에셋의 스프라이트 시트를 잘라 색을 입힌 텍스처로 만든다
enum Characters {
    /// 번호가 그대로 오가므로 순서를 바꾸거나 중간에 끼워 넣을 수 없다.
    /// 새 프리셋은 끝에 붙이고, groups 가 이름 앞자리로 제 모양에 묶어 준다
    static let names = [
        "goat_white", "goat_brown", "goat_black", "goat_gold", "goat_red", "goat_demon",
        "sheep_grey", "sheep_suffolk", "sheep_ink", "sheep_candy", "sheep_fleece", "sheep_night",
        "birb_blue", "birb_penguin", "birb_magpie", "birb_parrot", "birb_flamingo", "birb_kingfisher",
        "frog_green", "frog_fire", "frog_dart", "frog_tree", "frog_azure", "frog_violet",
        "pig_red", "pig_pink", "pig_black", "pig_ivory", "pig_royal", "pig_carrot",
        "birb_scarlet", "cat_cheese", "cat_tuxedo"]
    static var count: Int { names.count }

    static func shape(_ design: Int) -> String {
        String(names[design].prefix { $0 != "_" })
    }

    static func preset(_ design: Int) -> String {
        String(names[design].drop { $0 != "_" }.dropFirst())
    }

    /// 모양마다 프리셋 번호를 모은 것. 모양이 처음 나온 차례를 따른다
    static let groups: [(shape: String, designs: [Int])] = {
        var order: [String] = []
        var designs: [String: [Int]] = [:]
        for design in 0..<names.count {
            let shape = shape(design)
            if designs[shape] == nil { order.append(shape) }
            designs[shape, default: []].append(design)
        }
        return order.map { ($0, designs[$0]!) }
    }()

    private static let labels = ["goat": "염소", "sheep": "양", "birb": "새",
                                 "frog": "개구리", "pig": "돼지",
                                 "cat": "고양이"]

    static func label(_ shape: String) -> String { labels[shape] ?? shape }

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
    /// 메뉴바 아이콘. 개구리 머리를 스프라이트에서 잘라 쓴다 — 그림을 고치면 같이 바뀐다.
    /// 색을 살려야 하므로 template 가 아니다. 밝기 반전은 포기한다
    static func menuBarIcon(hasUpdate: Bool) -> NSImage? {
        guard let frame = thumbnail(Look(design: 18))?
            .cgImage(forProposedRect: nil, context: nil, hints: nil),
              let head = frame.cropping(to: CGRect(x: 7, y: 4, width: 10, height: 9))
        else { return nil }
        let height: CGFloat = 16
        let width = (height * CGFloat(head.width) / CGFloat(head.height)).rounded()
        let dot: CGFloat = 8
        /// 점이 개구리 밖으로 나가는 정도. 모서리에 걸치되 멀리 떨어지지 않게 한다
        let overhang: CGFloat = 2
        // 칸은 점이 있든 없든 같은 크기라 새 버전이 생겨도 아이콘이 옆으로 밀리지 않는다
        let size = NSSize(width: width + overhang, height: height + overhang)
        return NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .none
            NSGraphicsContext.current?.cgContext.draw(
                head, in: CGRect(x: 0, y: overhang, width: width, height: height))
            if hasUpdate {
                let spot = CGRect(x: width - dot + overhang, y: 0, width: dot, height: dot)
                // 점 둘레를 파내 개구리와 떨어뜨린다. 겹쳐 놓기만 하면 한 덩어리로 보인다
                NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
                NSBezierPath(ovalIn: spot.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: spot).fill()
            }
            return true
        }
    }

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
