import CoreGraphics
import Foundation
import SpriteKit

/// 같은 채널 사람과 하나씩 직접 주고받는다. 보낸 사람은 연결이 정한다
final class Session {
    static let shared = Session()

    /// 인사를 마친 연결 → 그 너머 사람
    private var peerByKey: [String: String] = [:]
    /// 인사를 마친 연결 → 그 사람이 채널에 들어온 시각
    private var sinceByKey: [String: Int] = [:]
    /// 내가 채널에 들어온 시각. 모두와 헤어지면 새로 들어온 것으로 본다
    var joinedAt = Session.now()
    /// 내가 연 연결 → 광고로 알고 연 상대. 이쪽이 먼저 인사하고, 받은 쪽은 확인한 뒤 답한다
    private var dialed: [String: String] = [:]
    /// UDP 포트를 알기 전에 인사를 마친 받은 연결. 포트를 알면 안내한다
    private var awaitingUDP: Set<String> = []
    private var lastSent: PosMsg?
    private var lastSentAt: TimeInterval = 0
    private var lastTypingAt: TimeInterval = 0
    /// 바뀐 뒤 같은 좌표를 더 보내는 횟수. UDP 로 멈춘 자리를 잃어도 상대가 멈춘 것을 안다
    private var repeatsLeft = 0
    static let settleRepeats = 2
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

    static func now() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    func start() {
        Net.shared.onLine = { [weak self] data, key in
            DispatchQueue.main.async { self?.handle(data, from: key) }
        }
        Net.shared.onReady = { [weak self] key, peerID in
            DispatchQueue.main.async { self?.linkReady(key, peerID: peerID) }
        }
        Net.shared.onGone = { [weak self] key in
            DispatchQueue.main.async { self?.linkGone(key) }
        }
        Net.shared.onUDPPort = { [weak self] in
            guard let self else { return }
            for key in self.awaitingUDP { self.inviteUDP(key) }
        }

        // 기본 모드 타이머는 대화상자나 메뉴를 열어 두면 멈춘다.
        // 그동안 좌표가 끊겨 동료 쪽 15초 판정에 해당해 내 캐릭터가 사라진다
        let timer = Timer(timeInterval: positionInterval, repeats: true) {
            [weak self] _ in self?.sendPosition()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 크기 상한은 Net 이 보낼 때 검사한다
    private func encode<T: Encodable>(_ value: T) -> Data? {
        try? encoder.encode(value)
    }

    private func linkReady(_ key: String, peerID: String?) {
        guard let peerID else { return }
        dialed[key] = peerID
        guard sendHello(to: key) else { Net.shared.dropLink(key); return }
    }

    /// 서 있으면 다음 좌표가 몇 초 뒤다. 좌표를 같이 보내지 않으면 그때까지 띠 왼쪽 끝에 서 있는 것으로 보인다
    private func sendHello(to key: String) -> Bool {
        let me = World.shared.me
        guard let hello = encode(HelloMsg(id: World.shared.myID, name: me.displayName,
                                          look: World.myLook, ch: World.myChannel, since: joinedAt)),
              let position = encode(stamped(snapshot(of: me)))
        else { return false }
        Net.shared.send(hello, to: key)
        Net.shared.send(position, to: key)
        return true
    }

    private func snapshot(of node: CharacterNode) -> PosMsg {
        PosMsg(x: Double(node.x),
               y: node.y > 0 ? Double(node.y) : nil,
               b: node.isBowing ? true : nil,
               d: node.isDragging ? true : nil,
               k: node.isDead ? true : nil,
               f: Int(node.facing))
    }

    /// 받는 쪽이 도착 시각 대신 이걸로 표본을 놓는다. 망이 흔들려도 걸음이 고르다
    private func stamped(_ msg: PosMsg) -> PosMsg {
        var out = msg
        out.m = Int(ProcessInfo.processInfo.systemUptime * 1000)
        return out
    }

    private func sendPosition() {
        let msg = snapshot(of: World.shared.me)
        let now = ProcessInfo.processInfo.systemUptime
        if shouldSend(msg, last: lastSent) {
            repeatsLeft = Session.settleRepeats
        } else if repeatsLeft > 0 {
            repeatsLeft -= 1
        } else if now - lastSentAt < keepaliveInterval {
            return
        }
        lastSent = msg
        lastSentAt = now
        if let data = encode(stamped(msg)) { Net.shared.broadcast(data, fast: true) }
    }

    func sendSay(_ text: String) {
        guard let body = validChat(text), let data = encode(SayMsg(msg: body)) else { return }
        Net.shared.broadcast(data)
        World.shared.showBubble(id: World.shared.myID, text: body)
        lastTypingAt = 0
    }

    /// 받는 쪽 입력 중 표시는 3초 뒤 만료된다. 그보다 짧은 간격으로 다시 보낸다
    func sendTyping() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTypingAt >= 2 else { return }
        lastTypingAt = now
        if let data = encode(TypingMsg()) { Net.shared.broadcast(data) }
        World.shared.showTyping(id: World.shared.myID)
    }

    func sendProfile() {
        let me = World.shared.me
        if let data = encode(ProfileMsg(name: me.displayName, look: World.myLook)) {
            Net.shared.broadcast(data)
        }
    }

    /// 낙하는 소유자가 자기 캐릭터에 대해 판정한다. 결과만 다른 화면에 알린다.
    func sendHit(rammed: String? = nil) {
        if let data = encode(HitMsg(rammed: rammed)) { Net.shared.broadcast(data) }
    }

    /// 좌표가 끊겨 없는 것으로 판정했을 때 World 가 호출한다.
    /// 연결을 끊어 두면 다시 연결하면서 hello 가 오가고 그때 되살아난다
    func peerGone(_ id: String) {
        World.shared.removePeer(id: id)
        Net.shared.dropLinks(to: id)
    }

    private func linkGone(_ key: String) {
        dialed[key] = nil
        awaitingUDP.remove(key)
        sinceByKey[key] = nil
        guard let id = peerByKey.removeValue(forKey: key) else { return }
        World.shared.removePeer(id: id)
        if peerByKey.isEmpty { joinedAt = Session.now() }
    }

    private func handle(_ data: Data, from key: String) {
        guard let message = try? decoder.decode(IncomingMessage.self, from: data) else { return }
        switch message {
        case let .hello(msg):
            greet(msg, key: key)
        case .full:
            // 인사한 상대나 광고를 보고 연 상대만 나를 내보낼 수 있다
            guard peerByKey[key] != nil || dialed[key] != nil else { return }
            World.moveToNextChannel()
        case let .udp(msg):
            guard peerByKey[key] != nil, dialed[key] != nil, msg.token.utf8.count <= 64
            else { return }
            Net.shared.openUDP(port: msg.port, token: msg.token, via: key)
        default:
            guard let id = peerByKey[key] else { return }
            apply(message, from: id)
        }
    }

    private func greet(_ msg: HelloMsg, key: String) {
        guard msg.pv == protocolVersion,
              msg.ch == World.myChannel,
              msg.id != World.shared.myID,
              // 내가 연 연결이면 광고한 사람이 답해야 한다
              dialed[key].map({ $0 == msg.id }) ?? true,
              !idIsTaken(msg.id, by: key, in: peerByKey)
        else {
            Net.shared.dropLink(key)
            return
        }
        let isNew = peerByKey[key] == nil
        if isNew, !makeSpace(for: msg, key: key) { return }
        peerByKey[key] = msg.id
        sinceByKey[key] = msg.since
        Net.shared.identify(key, as: msg.id)
        World.shared.addPeer(id: msg.id, name: sanitizeName(msg.name), look: msg.look.sanitized)
        if isNew, dialed[key] == nil {
            _ = sendHello(to: key)
            inviteUDP(key)
        }
    }

    /// 정원을 넘으면 가장 늦게 들어온 사람을 내보낸다. 연결은 그 사람이 채널을 옮기며 끊는다
    private func makeSpace(for msg: HelloMsg, key: String) -> Bool {
        let members = peerByKey.map { (id: $0.value, since: sinceByKey[$0.key] ?? 0) }
            + [(id: World.shared.myID, since: joinedAt), (id: msg.id, since: msg.since)]
        guard let out = overflowing(members, limit: Limits.maxChannelMembers) else { return true }
        if out == World.shared.myID {
            World.moveToNextChannel()
            return false
        }
        let outKey = out == msg.id ? key : peerByKey.first { $0.value == out }?.key
        if let outKey, let data = encode(FullMsg()) { Net.shared.send(data, to: outKey) }
        guard out != msg.id else { return false }
        if let outKey {
            peerByKey[outKey] = nil
            sinceByKey[outKey] = nil
        }
        World.shared.removePeer(id: out)
        return true
    }

    /// 포트를 모르면 알게 될 때까지 미룬다. 그동안은 TCP 로만 주고받는다
    private func inviteUDP(_ key: String) {
        guard let port = Net.shared.udpPort else { awaitingUDP.insert(key); return }
        awaitingUDP.remove(key)
        let token = UUID().uuidString
        Net.shared.allowUDP(token, for: key)
        if let data = encode(UDPMsg(port: Int(port), token: token)) { Net.shared.send(data, to: key) }
    }

    private func apply(_ message: IncomingMessage, from id: String) {
        switch message {
        case let .position(msg):
            guard abs(msg.x) <= Limits.maxX, (0...Limits.maxY).contains(msg.y ?? 0)
            else { return }
            World.shared.setPeerTarget(id: id, x: CGFloat(msg.x), y: CGFloat(msg.y ?? 0),
                                       bowing: msg.b == true, dragging: msg.d == true,
                                       dead: msg.k == true,
                                       facing: msg.f, sent: msg.m.map { Double($0) / 1000 })
        case let .say(msg):
            guard let body = validChat(msg.msg) else { return }
            World.shared.showBubble(id: id, text: body)
        case .typing:
            World.shared.showTyping(id: id)
        case let .profile(msg):
            World.shared.addPeer(id: id, name: sanitizeName(msg.name), look: msg.look.sanitized)
        case let .hit(msg):
            World.shared.peerWasHit(id: id)
            if msg.rammed == World.shared.myID { World.shared.wasRammed(by: id) }
        case .hello, .full, .udp:
            break
        }
    }
}
