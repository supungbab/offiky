import CoreGraphics
import Foundation

let protocolVersion = 2
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

struct Placement: Equatable {
    let screenIndex: Int
    let point: CGPoint
}

struct FloorStrip {
    /// 화면을 가로 위치 순으로 늘어놓은 것. 세로로 쌓였어도 가로로 잇는다
    let frames: [CGRect]
    /// 화면이 사라졌을 때 캐릭터를 보낼 곳
    let mainIndex: Int

    /// 원점은 띠의 왼쪽 끝이다. 좌우 방향이라는 개념이 없어지므로 배치가 달라도
    /// 같은 개수의 화면을 쓰면 서로 완전히 겹친다. 주 화면을 기준으로 잡으면
    /// 한쪽은 모니터가 왼쪽, 한쪽은 오른쪽일 때 보조 화면끼리 겹치지 않는다.
    init(visibleFrames: [CGRect], main: CGRect?) {
        guard !visibleFrames.isEmpty else {
            frames = []
            mainIndex = 0
            return
        }
        let ordered = FloorStrip.order(visibleFrames)
        frames = ordered
        mainIndex = main.flatMap { ordered.firstIndex(of: $0) } ?? 0
    }

    /// 나란히 놓인 화면은 띠에서도 나란히 둔다.
    ///
    /// 세로 범위가 겹치는 화면끼리 한 행으로 묶고, 행은 아래부터 행 안에서는 왼쪽부터
    /// 잇는다. 가로 중심만으로 정렬하면 아래 행의 화면이 위 행의 맞닿은 두 화면 사이로
    /// 끼어들어, 실제로는 베젤을 맞대고 있는 두 화면이 띠에서 갈라진다.
    ///
    /// 아래 행을 먼저 두면 대개 노트북인 주 화면이 띠 앞쪽에 와서, 모니터를 빼도
    /// 주 화면 구간이 움직이지 않는다.
    static func order(_ frames: [CGRect]) -> [CGRect] {
        var rows: [[CGRect]] = []
        for frame in frames.sorted(by: { $0.minY != $1.minY ? $0.minY < $1.minY : $0.minX < $1.minX }) {
            if let index = rows.firstIndex(where: { row in
                row.contains { $0.minY < frame.maxY && frame.minY < $0.maxY }
            }) {
                rows[index].append(frame)
            } else {
                rows.append([frame])
            }
        }
        return rows
            .sorted { ($0.map(\.minY).min() ?? 0, $0.map(\.minX).min() ?? 0)
                   < ($1.map(\.minY).min() ?? 0, $1.map(\.minX).min() ?? 0) }
            .flatMap { $0.sorted { $0.minX < $1.minX } }
    }

    var length: CGFloat { frames.reduce(0) { $0 + $1.width } }
    var minX: CGFloat { 0 }
    var maxX: CGFloat { length }

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

    /// 사라진 화면에 있던 캐릭터를 주 화면의 같은 가로 위치로 데려온다.
    /// 화면 왼쪽에 있었으면 왼쪽에 놓인다. 주 화면이 더 좁으면 그 안으로 제한한다.
    func onMain(offset: CGFloat) -> CGFloat {
        guard !frames.isEmpty else { return 0 }
        let start = frames.prefix(mainIndex).reduce(CGFloat(0)) { $0 + $1.width }
        return clamp(start + min(max(offset, 0), frames[mainIndex].width))
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
    let msg: String
}

struct ProfileMsg: Codable {
    var t = "profile"
    let name: String
    let look: Look
}

/// 캐릭터 외형. 내장 40종 중 하나를 가리키는 번호다
struct Look: Codable, Equatable {
    var design: Int

    static let neutral = Look(design: 0)

    static func fallback(for id: String) -> Look {
        Look(design: Int(stableHash(id) % UInt64(Characters.count)))
    }

    /// 수신값은 신뢰할 수 없으므로 범위 안으로 제한한다
    var sanitized: Look {
        Look(design: ((design % Characters.count) + Characters.count) % Characters.count)
    }
}
