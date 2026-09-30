import CoreGraphics
import Foundation

let protocolVersion = 11
let spriteDisplaySize: CGFloat = 40
/// 바닥을 화면 맨 아래에서 띄우는 높이. Dock 이나 화면 끝에 붙어 보이지 않게 한다
let floorOffset: CGFloat = 8
/// 움직이는 동안 좌표를 보내는 주기. 점프가 0.6초라 0.5초로는 표본이 한두 개뿐이다.
/// 서 있으면 이 주기로 보내지 않는다 — keepaliveInterval 을 본다
let positionInterval: TimeInterval = 0.1

/// 서 있으면 좌표가 그대로라 보내지 않는다. 그래도 이만큼마다 한 번은 보내야
/// 받는 쪽 15초 판정에서 없는 사람이 되지 않는다
let keepaliveInterval: TimeInterval = 3

/// 자리나 자세가 바뀌었는지. 생존 신호 주기는 Session 이 판정한다
func shouldSend(_ msg: PosMsg, last: PosMsg?) -> Bool {
    guard var last else { return true }
    // 보낸 시각은 비교하지 않는다. 매번 달라서 서 있어도 계속 보내게 된다
    last.m = msg.m
    return msg != last
}

enum Limits {
    static let maxMessageBytes = 16 * 1024
    /// 한 방에 들어갈 수 있는 사람 수. 모두 서로 직접 연결하므로 좌표 건수가 인원의 제곱으로 는다
    static let maxRoomMembers = 15
    /// 동시에 유지할 수 있는 소켓 수. 연결을 여는 중인 것까지 정원의 두 배 남짓이다
    static let maxLinks = 32
    /// 한 연결에서 초당 받을 수 있는 줄 수. 정상 좌표 10줄에 채팅 여유를 넉넉히 둔다.
    static let maxLinesPerSecond = 60
    /// 여러 연결이 동시에 쏟아부어도 메인 큐가 무너지지 않게 한다.
    /// 정원이 모두 움직여도 받는 정상 좌표는 초당 140줄이다.
    static let maxTotalLinesPerSecond = 2_000
    /// 악수를 끝내기 전에 받아 줄 줄 수. hello·좌표·UDP 안내 세 줄이 온다
    static let maxPendingLines = 16
    static let maxName = 20
    static let maxNameBytes = 256
    /// 방 이름 길이. 글자 수와 바이트 수 둘 다 막는다
    static let maxRoom = 20
    /// Bonjour TXT 는 한 쌍이 255바이트를 넘을 수 없다. 넘으면 광고가 통째로 실패한다
    static let maxRoomBytes = 60
    /// 말풍선이 보여 줄 만큼. 입력란과 수신 검증이 같은 값을 쓴다
    static let maxChat = 50
    static let maxChatBytes = 2 * 1024
    /// 방에 있는 동안 들고 있는 채팅 기록 수
    static let maxChatLog = 100
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

    /// `x` 는 스프라이트 중심, `y` 는 바닥으로부터의 높이. 둘 다 포인트.
    func place(x: CGFloat, y: CGFloat) -> Placement? {
        guard !frames.isEmpty else { return nil }
        let half = spriteDisplaySize / 2
        guard x + half >= 0, x - half <= length else { return nil }

        var accumulated: CGFloat = 0
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
        var accumulated: CGFloat = 0
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
        guard length > spriteDisplaySize else { return min(max(x, 0), length) }
        return min(max(x, half), length - half)
    }

    /// 사라진 화면에 있던 캐릭터를 주 화면의 같은 가로 위치로 데려온다.
    /// 화면 왼쪽에 있었으면 왼쪽에 놓인다. 주 화면이 더 좁으면 그 안으로 제한한다.
    func onMain(offset: CGFloat) -> CGFloat {
        guard !frames.isEmpty else { return 0 }
        let start = frames.prefix(mainIndex).reduce(CGFloat(0)) { $0 + $1.width }
        return clamp(start + min(max(offset, 0), frames[mainIndex].width))
    }
}

/// 다른 연결이 이미 그 id 를 쓰고 있는지. 연결은 상대를 증명하지 못하므로
/// 먼저 자리를 잡은 쪽이 이긴다 — 나중에 온 쪽이 남을 밀어내지 못하게 한다
func idIsTaken(_ id: String, by key: String, in table: [String: String]) -> Bool {
    table.contains { $0.key != key && $0.value == id }
}

/// 정원을 넘으면 나갈 사람. 모두 같은 입장 시각을 보므로 누가 판정해도 같은 사람이 나간다
func overflowing(_ members: [(id: String, since: Int)], limit: Int) -> String? {
    guard members.count > limit else { return nil }
    return members.max { ($0.since, $0.id) < ($1.since, $1.id) }?.id
}

/// 방을 구분하는 값. 만들 때 새로 뽑는다 — 이름이 같아도 다른 방이고,
/// 이름을 바꿔도 같은 방이다
func newRoomID() -> String {
    String(UUID().uuidString.prefix(8))
}

/// 실제 참여 여부는 room id로 정하고, 이름이 없을 때만 id를 표시용으로 쓴다.
func roomDisplayName(id: String?, name: String?) -> String? {
    id.map { name ?? $0 }
}

/// 참여하기 목록에 쓰는 한 줄
struct RoomListing: Identifiable, Equatable {
    let id: String
    let name: String
    /// 목록에 보여 줄 글자. 이름이 같은 방이 둘이면 뒤에 짧은 코드가 붙는다
    let label: String
    let count: Int
}

/// Bonjour 광고에서 프로토콜이 같고 같은 방에 있는 피어만 고른다.
/// 방에 없으면 아무와도 연결하지 않는다 — 혼자다.
/// 버전이 다른 피어와는 연결해도 서로 무시하므로 후보에 넣지 않는다.
func compatiblePeers(_ entries: [(id: String, pv: String?, room: String?, roomName: String?)],
                     myRoom: String?)
    -> (ids: Set<String>, mismatched: Int, rooms: [RoomListing]) {
    var ids: Set<String> = []
    var others: Set<String> = []
    var members: [String: Set<String>] = [:]
    var names: [String: String] = [:]
    for entry in entries {
        guard Int(entry.pv ?? "") == protocolVersion else { others.insert(entry.id); continue }
        guard let room = entry.room, !room.isEmpty else { continue }
        // 같은 사람이 인터페이스마다 따로 보고된다. 줄 수가 아니라 사람 수를 센다
        members[room, default: []].insert(entry.id)
        if names[room] == nil, let name = entry.roomName, !name.isEmpty { names[room] = name }
        if room == myRoom { ids.insert(entry.id) }
    }
    var counts: [String: Int] = [:]
    for room in members.keys { counts[names[room] ?? room, default: 0] += 1 }
    let rooms = members
        .map { room, people -> RoomListing in
            let name = names[room] ?? room
            // 이름이 같은 방이 둘이면 목록에서 구분할 수 있어야 한다
            let label = (counts[name] ?? 0) > 1 ? "\(name) · \(room.prefix(4))" : name
            return RoomListing(id: room, name: name, label: label, count: people.count)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
    return (ids, others.subtracting(ids).count, rooms)
}

/// ZWJ 는 남긴다 — 이모지를 잇는 글자라 제거하면 🧑‍💻 가 통째로 사라진다
private let strippable = CharacterSet.controlCharacters
    .subtracting(CharacterSet(charactersIn: "\u{200D}"))

private func stripControls(_ s: String) -> String {
    s.filter { !$0.unicodeScalars.contains { strippable.contains($0) } }
}

/// 글자 수와 바이트 수를 함께 막는다
func clamped(_ raw: String, maxCount: Int, maxBytes: Int) -> String {
    var out = ""
    for character in raw {
        guard out.count < maxCount,
              out.utf8.count + String(character).utf8.count <= maxBytes
        else { break }
        out.append(character)
    }
    return out
}

func sanitizeName(_ raw: String) -> String {
    let out = clamped(stripControls(raw).trimmingCharacters(in: .whitespaces),
                      maxCount: Limits.maxName, maxBytes: Limits.maxNameBytes)
    return out.isEmpty ? "?" : out
}

/// 이 값은 Bonjour TXT 에 실린다. 이모지는 한 글자가 스물다섯 바이트까지 가므로
/// 글자 수만 막으면 255바이트 제한을 넘겨 리스너가 실패하고, 아무에게도 보이지 않는다.
/// 빈 문자열은 방을 만들지 않겠다는 뜻이다
func sanitizeRoom(_ raw: String) -> String {
    clamped(stripControls(raw).trimmingCharacters(in: .whitespaces),
            maxCount: Limits.maxRoom, maxBytes: Limits.maxRoomBytes)
}

func validChat(_ raw: String) -> String? {
    let cleaned = stripControls(raw)
    guard !cleaned.isEmpty,
          cleaned.count <= Limits.maxChat,
          cleaned.utf8.count <= Limits.maxChatBytes
    else { return nil }
    return cleaned
}

struct HelloMsg: Codable {
    var t = "hello"
    var pv = protocolVersion
    let id: String
    let name: String
    let look: Look
    let room: String
    /// 방에 들어온 시각(ms). 정원을 넘으면 늦게 들어온 사람이 나간다
    let since: Int
}

/// 보낸 사람은 연결이 정한다. 메시지에 id 를 적지 않으므로 남을 사칭할 수 없다
struct PosMsg: Codable, Equatable {
    var t = "pos"
    let x: Double
    let y: Double?
    /// 인사 중일 때만 싣는다. 옛 버전은 이 값을 무시하고 서 있는 것으로 본다
    var b: Bool?
    /// 들려 있을 때만 싣는다. 받는 쪽은 좌표만으로 이걸 알 수 없다
    var d: Bool?
    /// 보고 있는 쪽. +1 오른쪽, -1 왼쪽. 옛 버전은 싣지 않는다
    var f: Int?
    /// 보낸 시각(ms, 보낸 기계 기준). 받는 쪽은 도착 시각 대신 이걸로 표본을 놓는다
    var m: Int?
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

/// 높은 곳에서 떨어진 피격은 소유자만 판정하고 다른 화면에 한 번 알린다.
struct HitMsg: Codable {
    var t = "hit"
}

/// 정원이 찼다. 받은 쪽은 방에서 나간다
struct FullMsg: Codable {
    var t = "full"
}

/// 연결을 받은 쪽이 좌표용 UDP 포트를 알린다. 연결을 연 쪽은 데이터그램 첫 줄에 토큰을 적어 자기를 밝힌다
struct UDPMsg: Codable {
    var t = "udp"
    let port: Int
    let token: String
}

/// 흐름을 연 쪽이 데이터그램 첫 줄에 적는 값. 상대 데이터그램을 받았으면 `!` 를 붙여 반대 방향도 통한다고 알린다
func udpPrefix(token: String, acked: Bool) -> Data {
    Data((token + (acked ? "!" : "") + "\n").utf8)
}

/// `udpPrefix` 의 첫 줄(개행 제외)을 읽는다
func readUDPPrefix(_ line: Data) -> (token: String, acked: Bool)? {
    guard var token = String(data: line, encoding: .utf8) else { return nil }
    let acked = token.hasSuffix("!")
    if acked { token.removeLast() }
    return (token, acked)
}

/// 데이터그램 하나의 상한. 넘으면 IP 조각으로 나뉘고 조각 하나만 잃어도 전체를 잃는다
let maxDatagramBytes = 1200

/// 개행으로 나뉜 줄을 줄 경계에서 잘라 데이터그램마다 `prefix` 를 앞에 적는다
func datagrams(_ lines: Data, prefix: Data = Data()) -> [Data] {
    var out: [Data] = []
    var current = prefix
    for line in lines.split(separator: 0x0A, omittingEmptySubsequences: true) {
        if current.count > prefix.count, current.count + line.count + 1 > maxDatagramBytes {
            out.append(current)
            current = prefix
        }
        current.append(contentsOf: line)
        current.append(0x0A)
    }
    if current.count > prefix.count { out.append(current) }
    return out
}

enum IncomingLineDecision: Equatable {
    case forward, discard, disconnect
}

/// 소켓과 분리한 링크 정책. 악수와 트래픽 제한을 실제 연결 없이도 검증한다.
struct LinkTrafficPolicy {
    let startedAt: TimeInterval
    private(set) var isIdentified = false
    private(set) var pendingLines = 0

    mutating func identify() { isIdentified = true }

    func handshakeExpired(at now: TimeInterval, timeout: TimeInterval) -> Bool {
        !isIdentified && now - startedAt >= timeout
    }

    mutating func decision(linkLines: Int, totalLines: Int) -> IncomingLineDecision {
        if linkLines > Limits.maxLinesPerSecond { return .disconnect }
        if !isIdentified {
            pendingLines += 1
            if pendingLines > Limits.maxPendingLines { return .disconnect }
        }
        // 전역 상한은 시스템 보호용이다. 임계점을 우연히 넘긴 정상 연결을 범인처럼
        // 끊지 않고, 이 윈도우의 초과 메시지만 버린다.
        if totalLines > Limits.maxTotalLinesPerSecond { return .discard }
        return .forward
    }
}

/// 종류를 먼저 따로 디코딩하면 좌표 하나마다 JSON 전체를 두 번 읽게 된다.
/// 같은 Decoder에서 종류를 보고 구체 메시지를 만들어 한 번만 순회한다.
enum IncomingMessage: Decodable {
    case hello(HelloMsg)
    case position(PosMsg)
    case say(SayMsg)
    case profile(ProfileMsg)
    case hit(HitMsg)
    case full(FullMsg)
    case udp(UDPMsg)

    private enum CodingKeys: String, CodingKey { case t }

    init(from decoder: Decoder) throws {
        let type = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .t)
        switch type {
        case "hello":   self = .hello(try HelloMsg(from: decoder))
        case "pos":     self = .position(try PosMsg(from: decoder))
        case "say":     self = .say(try SayMsg(from: decoder))
        case "profile": self = .profile(try ProfileMsg(from: decoder))
        case "hit":     self = .hit(try HitMsg(from: decoder))
        case "full":    self = .full(try FullMsg(from: decoder))
        case "udp":     self = .udp(try UDPMsg(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .t,
                in: try decoder.container(keyedBy: CodingKeys.self),
                debugDescription: "unknown message type")
        }
    }
}

/// 캐릭터 외형. `Characters.names` 중 하나를 가리키는 번호다
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
