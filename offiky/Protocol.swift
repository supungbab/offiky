import CoreGraphics
import Foundation

let protocolVersion = 1
let spriteDisplaySize: CGFloat = 40
/// 바닥을 화면 맨 아래에서 띄우는 높이. Dock 이나 화면 끝에 붙어 보이지 않게 한다
let floorOffset: CGFloat = 8
/// 좌표 전송·중계 주기. 점프가 0.6초라 0.5초로는 표본이 한두 개뿐이다
let snapshotInterval: TimeInterval = 0.1

enum Limits {
    static let maxMessageBytes = 16 * 1024
    static let maxName = 20
    static let maxChat = 200
    static let maxX: Double = 10_000
    static let maxY: Double = 4_000
}

/// 맵은 화면보다 넓다. 카메라가 내 캐릭터를 따라가며 이 범위의 일부를 비춘다.
/// 고정값이라 참가자가 드나들어도 맵이 흔들리지 않는다 — 폭이 바뀌면
/// 같은 좌표가 다른 자리를 가리켜 모두의 캐릭터가 밀린다.
let mapHalfWidth: CGFloat = 2400

func clampToMap(_ x: CGFloat) -> CGFloat {
    min(max(x, -mapHalfWidth), mapHalfWidth)
}

/// 내 캐릭터가 가운데 40% 안에 있으면 카메라를 두고, 벗어나면 그만큼만 민다.
/// 화면 한가운데 붙잡아 두면 걸어 다니는 느낌이 사라진다.
func followCamera(_ camera: CGFloat, target: CGFloat, viewHalf: CGFloat) -> CGFloat {
    guard viewHalf > 0 else { return 0 }
    guard viewHalf < mapHalfWidth else { return 0 }   // 맵이 다 보이면 움직일 이유가 없다
    let dead = viewHalf * 0.4
    var next = camera
    if target - camera > dead { next = target - dead }
    if target - camera < -dead { next = target + dead }
    return min(max(next, -mapHalfWidth + viewHalf), mapHalfWidth - viewHalf)
}

struct Placement: Equatable {
    let screenIndex: Int
    let point: CGPoint
}

struct FloorStrip {
    /// 주 디스플레이 기준으로 좌우에 배치한 화면들
    let frames: [CGRect]
    /// 띠 왼쪽 끝에서 원점(x = 0)까지의 거리
    let originOffset: CGFloat

    init(visibleFrames: [CGRect], main: CGRect?) {
        guard let main = main ?? visibleFrames.first, !visibleFrames.isEmpty else {
            frames = []
            originOffset = 0
            return
        }
        // 세로로 붙은 화면도 가로 중심이 어느 쪽으로 치우쳤는지만 본다.
        // 정확히 가운데면 오른쪽에 잇는다.
        let others = visibleFrames.filter { $0 != main }
        let left = others.filter { $0.midX < main.midX }.sorted { $0.midX < $1.midX }
        let right = others.filter { $0.midX >= main.midX }.sorted { $0.midX < $1.midX }
        frames = left + [main] + right
        originOffset = left.reduce(0) { $0 + $1.width } + main.width / 2
    }

    var length: CGFloat { frames.reduce(0) { $0 + $1.width } }
    /// 원점은 주 디스플레이 한가운데이므로 왼쪽은 음수다
    var minX: CGFloat { -originOffset }
    var maxX: CGFloat { length - originOffset }

    /// `x` 는 스프라이트 중심, `y` 는 바닥으로부터의 높이. 둘 다 포인트.
    func place(x: CGFloat, y: CGFloat) -> Placement? {
        guard !frames.isEmpty else { return nil }
        let half = spriteDisplaySize / 2
        guard x + half >= minX, x - half <= maxX else { return nil }

        var accumulated = minX
        for (index, frame) in frames.enumerated() {
            if x < accumulated + frame.width || index == frames.count - 1 {
                let maxLift = max(0, frame.height - spriteDisplaySize - floorOffset)
                return Placement(
                    screenIndex: index,
                    point: CGPoint(x: x - accumulated,
                                   y: floorOffset + half + min(y, maxLift)))
            }
            accumulated += frame.width
        }
        return nil
    }

    /// `place` 의 역변환. 전역 커서 좌표를 띠 좌표로 바꾼다.
    /// 두 함수가 같은 기준에서 누적해야 한다 — 어긋나면 잡아 끈 위치가 통째로 밀린다.
    func locate(global point: CGPoint) -> (x: CGFloat, y: CGFloat)? {
        var accumulated = minX
        for frame in frames {
            if frame.contains(point) {
                return (accumulated + point.x - frame.minX,
                        max(0, point.y - frame.minY - floorOffset - spriteDisplaySize / 2))
            }
            accumulated += frame.width
        }
        return nil
    }

    /// 캐릭터가 띠를 벗어나지 않게 한다
    func clamp(_ x: CGFloat) -> CGFloat {
        let half = spriteDisplaySize / 2
        guard length > spriteDisplaySize else { return min(max(x, minX), maxX) }
        return min(max(x, minX + half), maxX - half)
    }
}

/// Bonjour 광고에서 프로토콜이 같은 피어만 고른다.
/// 버전이 다른 피어와는 연결해도 서로 무시하므로 후보에 넣지 않는다.
func compatiblePeers(_ entries: [(id: String, pv: String?)]) -> (ids: Set<String>, mismatched: Int) {
    var ids: Set<String> = []
    var mismatched = 0
    for entry in entries {
        if Int(entry.pv ?? "") == protocolVersion { ids.insert(entry.id) } else { mismatched += 1 }
    }
    return (ids, mismatched)
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
    let look: Look
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
    let look: Look
}

struct JoinMsg: Codable {
    var t = "join"
    let id: String
    let name: String
    let look: Look
    /// 스냅샷에서 이 피어를 가리키는 번호. 호스트가 접속 순서대로 부여한다
    var n: Int?
}

struct LeaveMsg: Codable {
    var t = "leave"
    let id: String
}

/// 한 건은 `[번호, x]` 또는 `[번호, x, y]` 다. 좌표는 포인트 단위 정수로 내림한다.
/// 표시는 2포인트 격자에 맞추므로 정밀도 손실이 화면에 나타나지 않는다.
/// id 를 그대로 싣던 때는 한 건이 56바이트였고 지금은 8바이트다
struct SnapMsg: Codable {
    var t = "snap"
    let p: [[Int]]
}

struct AckMsg: Codable {
    var t = "ack"
    let seq: Int
}

/// 캐릭터 외형. 내장 9종 중 하나에 색 조정값을 더한 것이다.
struct Look: Codable, Equatable {
    var design: Int
    /// -0.5 ~ 0.5 색상 회전
    var hue: Double
    /// 0 ~ 2 채도 배율
    var saturation: Double
    /// 0.5 ~ 1.5 밝기 배율
    var brightness: Double

    static let neutral = Look(design: 0, hue: 0, saturation: 1, brightness: 1)

    static func fallback(for id: String) -> Look {
        Look(design: Int(stableHash(id) % UInt64(Characters.count)),
             hue: 0, saturation: 1, brightness: 1)
    }

    /// 수신값은 신뢰할 수 없으므로 범위 안으로 제한한다
    var sanitized: Look {
        Look(design: ((design % Characters.count) + Characters.count) % Characters.count,
             hue: min(max(hue, -0.5), 0.5),
             saturation: min(max(saturation, 0), 2),
             brightness: min(max(brightness, 0.5), 1.5))
    }

}
