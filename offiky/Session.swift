import CoreGraphics
import Foundation
import SpriteKit

/// 같은 방 사람과 하나씩 직접 주고받는다. 보낸 사람은 연결이 정한다
final class Session {
    static let shared = Session()

    /// 인사를 마친 연결 → 그 너머 사람
    private var peerByKey: [String: String] = [:]
    /// 내가 연 연결 → 광고로 알고 연 상대. 이쪽이 먼저 인사하고, 받은 쪽은 확인한 뒤 답한다
    private var dialed: [String: String] = [:]
    /// UDP 포트를 알기 전에 인사를 마친 받은 연결. 포트를 알면 안내한다
    private var awaitingUDP: Set<String> = []
    private var lastSent: PosMsg?
    private var lastSentAt: TimeInterval = 0
    /// 바뀐 뒤 같은 좌표를 더 보내는 횟수. UDP 로 멈춘 자리를 잃어도 상대가 멈춘 것을 안다
    private var repeatsLeft = 0
    static let settleRepeats = 2
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

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
        // 인사하면 상대가 나를 추가한 뒤라 정원 안내를 받아 주지 않는다. 확정하지 않은 연결은 악수 기한이 지나면 정리된다
        if isFull(for: peerID) {
            if let data = encode(FullMsg()) { Net.shared.send(data, to: key) }
            return
        }
        guard sendHello(to: key) else { Net.shared.dropLink(key); return }
    }

    /// 이 사람이 새로 들어오면 정원을 넘는지
    private func isFull(for id: String) -> Bool {
        World.shared.peers[id] == nil && World.shared.peers.count >= Limits.maxRoomMembers - 1
    }

    /// 서 있으면 다음 좌표가 몇 초 뒤다. 좌표를 같이 보내지 않으면 그때까지 띠 왼쪽 끝에 서 있는 것으로 보인다
    private func sendHello(to key: String) -> Bool {
        guard let room = World.myRoom else { return false }
        let me = World.shared.me
        guard let hello = encode(HelloMsg(id: World.shared.myID, name: me.displayName,
                                          look: World.myLook, room: room)),
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
    }

    func sendProfile() {
        let me = World.shared.me
        if let data = encode(ProfileMsg(name: me.displayName, look: World.myLook)) {
            Net.shared.broadcast(data)
        }
    }

    /// 낙하는 소유자가 자기 캐릭터에 대해 판정한다. 결과만 다른 화면에 알린다.
    func sendHit() {
        if let data = encode(HitMsg()) { Net.shared.broadcast(data) }
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
        guard let id = peerByKey.removeValue(forKey: key) else { return }
        World.shared.removePeer(id: id)
    }

    private func handle(_ data: Data, from key: String) {
        guard let message = try? decoder.decode(IncomingMessage.self, from: data) else { return }
        switch message {
        case let .hello(msg):
            greet(msg, key: key)
        case .full:
            // 들어가려던 방이 찼다. 이미 누군가와 인사했으면 서로 명단이 어긋난 것이라 이 연결만 끊는다
            guard peerByKey[key] == nil else { return }
            guard peerByKey.isEmpty else { Net.shared.dropLink(key); return }
            World.leaveRoom()
            tellRoomIsFull()
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
              let room = World.myRoom,
              msg.room == room,
              msg.id != World.shared.myID,
              // 내가 연 연결이면 광고한 사람이 답해야 한다
              dialed[key].map({ $0 == msg.id }) ?? true,
              !idIsTaken(msg.id, by: key, in: peerByKey)
        else {
            Net.shared.dropLink(key)
            return
        }
        let isNew = peerByKey[key] == nil
        if isNew, isFull(for: msg.id) {
            // 받은 연결이면 알리기만 한다. 확정하지 않은 연결은 악수 기한이 지나면 정리된다.
            // 연 연결은 이미 인사해 상대가 안내를 받아 주지 않는다. 다시 열 때 linkReady 가 알린다
            if dialed[key] != nil { Net.shared.dropLink(key) }
            else if let data = encode(FullMsg()) { Net.shared.send(data, to: key) }
            return
        }
        peerByKey[key] = msg.id
        Net.shared.identify(key, as: msg.id)
        World.shared.addPeer(id: msg.id, name: sanitizeName(msg.name), look: msg.look.sanitized)
        if isNew, dialed[key] == nil {
            _ = sendHello(to: key)
            inviteUDP(key)
        }
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
                                       facing: msg.f, sent: msg.m.map { Double($0) / 1000 })
        case let .say(msg):
            guard let body = validChat(msg.msg) else { return }
            World.shared.showBubble(id: id, text: body)
        case let .profile(msg):
            World.shared.addPeer(id: id, name: sanitizeName(msg.name), look: msg.look.sanitized)
        case .hit:
            World.shared.peerWasHit(id: id)
        case .hello, .full, .udp:
            break
        }
    }
}
