import CoreGraphics
import Foundation

let protocolVersion = 1
let spriteDisplaySize: CGFloat = 32

enum Limits {
    static let maxMessageBytes = 16 * 1024
    static let maxName = 20
    static let maxChat = 200
    static let maxX: Double = 20_000
    static let maxY: Double = 4_000
}

struct Placement: Equatable {
    let screenIndex: Int
    let point: CGPoint
}

struct FloorStrip {
    let frames: [CGRect]

    init(visibleFrames: [CGRect]) {
        self.frames = visibleFrames.sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
    }

    var length: CGFloat { frames.reduce(0) { $0 + $1.width } }

    /// `x` 는 스프라이트 중심, `y` 는 바닥으로부터의 높이. 둘 다 포인트.
    func place(x: CGFloat, y: CGFloat) -> Placement? {
        guard !frames.isEmpty else { return nil }
        let half = spriteDisplaySize / 2
        guard x + half >= 0, x - half <= length else { return nil }

        var accumulated: CGFloat = 0
        for (index, frame) in frames.enumerated() {
            if x < accumulated + frame.width || index == frames.count - 1 {
                let maxY = max(0, frame.height - spriteDisplaySize)
                return Placement(
                    screenIndex: index,
                    point: CGPoint(x: x - accumulated, y: half + min(y, maxY)))
            }
            accumulated += frame.width
        }
        return nil
    }

    func clampToWall(_ x: CGFloat) -> CGFloat {
        let half = spriteDisplaySize / 2
        guard length > spriteDisplaySize else { return min(max(x, 0), length) }
        return min(max(x, half), length - half)
    }
}

/// 보이는 피어 중 id 가 가장 작은 쪽이 호스트다. 나는 언제나 후보에 포함된다.
func electHost(candidates: Set<String>, excluded: Set<String>, me: String) -> String {
    var pool = candidates.subtracting(excluded)
    pool.insert(me)
    return pool.min()!
}

struct SeqTracker {
    private var last: [String: Int] = [:]

    mutating func accept(id: String, seq: Int) -> Bool {
        if let previous = last[id], seq <= previous { return false }
        last[id] = seq
        return true
    }

    mutating func forget(id: String) { last[id] = nil }
}

private func stripControls(_ s: String) -> String {
    s.filter { !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }
}

func sanitizeName(_ raw: String) -> String {
    let cleaned = stripControls(raw).trimmingCharacters(in: .whitespaces)
    if cleaned.isEmpty { return "?" }
    return String(cleaned.prefix(Limits.maxName))
}

func validChat(_ raw: String) -> String? {
    let cleaned = stripControls(raw)
    guard !cleaned.isEmpty, cleaned.count <= Limits.maxChat else { return nil }
    return cleaned
}

struct Envelope: Decodable { let t: String }

struct PeerPos: Codable {
    let id: String
    let x: Double
    let y: Double?
}

struct HelloMsg: Codable {
    var t = "hello"
    var pv = protocolVersion
    let id: String
    let name: String
    let sprite: String
}

struct PosMsg: Codable {
    var t = "pos"
    let x: Double
    let y: Double?
}

struct SayMsg: Codable {
    var t = "say"
    var id: String?
    let seq: Int
    let msg: String
}

struct ProfileMsg: Codable {
    var t = "profile"
    var id: String?
    let name: String
    let sprite: String
}

struct JoinMsg: Codable {
    var t = "join"
    let id: String
    let name: String
    let sprite: String
}

struct LeaveMsg: Codable {
    var t = "leave"
    let id: String
}

struct SnapMsg: Codable {
    var t = "snap"
    let p: [PeerPos]
}

struct AckMsg: Codable {
    var t = "ack"
    let seq: Int
}
