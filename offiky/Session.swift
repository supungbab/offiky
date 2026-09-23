import CoreGraphics
import Foundation
import SpriteKit

/// 호스트는 클라이언트에게서 받은 것에 보낸 사람을 붙여 중계하고, 클라이언트는 호스트하고만 주고받는다.
final class Session {
    static let shared = Session()

    /// 호스트일 때 연결 → 그 너머 클라이언트
    private var clientByKey: [String: String] = [:]
    /// 클라이언트일 때 호스트로 이어진 연결 하나
    private var hostKey: String?
    private var hostID: String?
    /// 방에 혼자면 내가 호스트다
    private(set) var amHost = true

    /// 지금 중계를 맡은 사람. 방에 없거나 아직 연결되지 않았으면 nil
    var hostPeer: String? {
        guard World.myRoom != nil else { return nil }
        return amHost ? World.shared.myID : hostID
    }
    private var posTimer: Timer?
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

        // 기본 모드 타이머는 대화상자나 메뉴를 열어 두면 멈춘다.
        // 그동안 좌표가 끊겨 동료 쪽 15초 판정에 해당해 내 캐릭터가 사라진다
        let timer = Timer(timeInterval: positionInterval, repeats: true) {
            [weak self] _ in self?.sendPosition()
        }
        RunLoop.main.add(timer, forMode: .common)
        posTimer = timer
    }

    private func encode<T: Encodable>(_ value: T) -> Data? {
        guard let data = try? encoder.encode(value), data.count <= Limits.maxMessageBytes
        else { return nil }
        return data
    }

    /// 호스트가 바뀌었다. 이전 구성에서 알던 사람은 전부 다시 받아야 한다
    func roleChanged(amHost: Bool) {
        self.amHost = amHost
        Presence.shared.amHost = amHost && World.myRoom != nil
        reset()
    }

    private func reset() {
        clientByKey.removeAll()
        hostKey = nil
        hostID = nil
        lastSent = nil
        // 명단은 새 호스트가 곧 다시 보낸다. 화면에서 지우지 않는다 —
        // 지우면 교체할 때마다 모두의 캐릭터가 한 번씩 사라진다.
        // 정말 나간 사람은 좌표가 끊겨 15초 판정이 정리한다
        ChatLog.shared.regrouping()
    }

    private func linkReady(_ key: String, peerID: String?) {
        // 호스트는 클라이언트가 인사한 뒤에 답한다 — 방과 버전을 확인해야 명단을 준다
        guard !amHost else { return }
        guard let room = World.myRoom else { Net.shared.dropLink(key); return }
        hostKey = key
        hostID = peerID
        let me = World.shared.me
        guard let hello = encode(HelloMsg(id: World.shared.myID, name: me.displayName,
                                          look: World.myLook, room: room)),
              let position = encode(stamped(snapshot(of: me)))
        else { Net.shared.dropLink(key); return }
        Net.shared.send(hello, to: key)
        // 서 있으면 다음 좌표가 몇 초 뒤다. 그때까지 내가 띠 왼쪽 끝에 서 있는 것으로 보인다
        Net.shared.send(position, to: key)
    }

    private func snapshot(of node: CharacterNode) -> PosMsg {
        PosMsg(id: amHost ? node.id : nil,
               x: Double(node.x),
               y: node.y > 0 ? Double(node.y) : nil,
               b: node.isBowing ? true : nil,
               d: node.isDragging ? true : nil,
               f: Int(node.facingSign))
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
        if shouldSend(msg, last: lastSent, since: 0) {
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
        guard let body = validChat(text) else { return }
        guard let data = encode(SayMsg(id: amHost ? World.shared.myID : nil, msg: body))
        else { return }
        Net.shared.broadcast(data)
        World.shared.showBubble(id: World.shared.myID, text: body)
    }

    func sendProfile() {
        let me = World.shared.me
        if let data = encode(ProfileMsg(id: amHost ? World.shared.myID : nil,
                                        name: me.displayName, look: World.myLook)) {
            Net.shared.broadcast(data)
        }
    }

    /// 낙하는 소유자가 자기 캐릭터에 대해 판정한다. 결과만 다른 화면에 알린다.
    func sendHit() {
        if let data = encode(HitMsg(id: amHost ? World.shared.myID : nil)) {
            Net.shared.broadcast(data)
        }
    }

    /// 좌표가 끊겨 없는 것으로 판정했을 때 World 가 부른다.
    /// 연결을 끊어 두면 다시 연결하면서 hello 가 오가고 그때 되살아난다
    func peerGone(_ id: String) {
        World.shared.removePeer(id: id)
        Net.shared.dropLinks(to: id)
    }

    private func linkGone(_ key: String) {
        // 호스트가 끊겼다. 알던 사람은 전부 그 연결로 받은 것이라 같이 제거한다
        if key == hostKey {
            hostKey = nil
            hostID = nil
            ChatLog.shared.regrouping()
            return
        }
        guard let id = clientByKey.removeValue(forKey: key) else { return }
        World.shared.removePeer(id: id)
        if let data = encode(ByeMsg(id: id)) { Net.shared.broadcast(data) }
    }

    private func handle(_ data: Data, from key: String) {
        guard let message = try? decoder.decode(IncomingMessage.self, from: data) else { return }
        if amHost {
            handleFromClient(message, key: key)
        } else if key == hostKey {
            handleFromHost(message)
        } else {
            Net.shared.dropLink(key)
        }
    }

    // MARK: 호스트

    private func handleFromClient(_ message: IncomingMessage, key: String) {
        if case let .hello(msg) = message { admit(msg, key: key); return }
        // 보낸 사람은 연결이 정한다. 클라이언트가 보낸 id 는 쓰지 않는다
        guard let id = clientByKey[key] else { return }
        apply(message, from: id)
        relay(message, from: id, except: key)
    }

    private func admit(_ msg: HelloMsg, key: String) {
        guard msg.pv == protocolVersion,
              let room = World.myRoom,
              msg.room == room,
              msg.id != World.shared.myID,
              !idIsTaken(msg.id, by: key, in: clientByKey)
        else {
            Net.shared.dropLink(key)
            return
        }
        // 정원이 차면 알리기만 한다. 확정하지 않은 연결은 악수 기한이 지나면 정리된다
        if clientByKey[key] == nil, World.shared.peers.count >= Limits.maxRoomMembers - 1 {
            if let data = encode(FullMsg()) { Net.shared.send(data, to: key) }
            return
        }
        let name = sanitizeName(msg.name)
        let look = msg.look.sanitized
        clientByKey[key] = msg.id
        Net.shared.identify(key, as: msg.id)
        World.shared.addPeer(id: msg.id, name: name, look: look)
        introduceEveryone(to: key)
        inviteUDP(key)
        if let data = encode(HelloMsg(id: msg.id, name: name, look: look, room: room)) {
            Net.shared.broadcast(data, except: key)
        }
    }

    /// 포트를 모르면 알리지 않는다. 그 클라이언트는 TCP 로만 주고받는다
    private func inviteUDP(_ key: String) {
        guard let port = Net.shared.udpPort else { return }
        let token = UUID().uuidString
        Net.shared.allowUDP(token, for: key)
        if let data = encode(UDPMsg(port: Int(port), token: token)) { Net.shared.send(data, to: key) }
    }

    /// 방금 연결한 클라이언트에게 지금 있는 사람을 한 번에 알린다. 좌표를 같이 보내지 않으면
    /// 다음 생존 신호까지 모두가 띠 왼쪽 끝에 서 있는 것으로 보인다
    private func introduceEveryone(to key: String) {
        guard let room = World.myRoom else { return }
        let newcomer = clientByKey[key]
        introduce(World.shared.me, room: room, to: key)
        for node in World.shared.peers.values where node.id != newcomer {
            introduce(node, room: room, to: key)
        }
    }

    private func introduce(_ node: CharacterNode, room: String, to key: String) {
        guard let hello = encode(HelloMsg(id: node.id, name: node.displayName,
                                          look: node.look, room: room)),
              let position = encode(snapshot(of: node))
        else { return }
        Net.shared.send(hello, to: key)
        Net.shared.send(position, to: key)
    }

    /// 받은 것을 그대로 중계하되 보낸 사람을 붙인다
    private func relay(_ message: IncomingMessage, from id: String, except key: String) {
        let data: Data?
        switch message {
        case .position(var msg):
            msg.id = id
            if let data = encode(msg) { Net.shared.broadcast(data, except: key, fast: true) }
            return
        case .say(var msg):      msg.id = id; data = encode(msg)
        case .profile(var msg):  msg.id = id; data = encode(msg)
        case .hit(var msg):      msg.id = id; data = encode(msg)
        case .hello, .bye, .full, .udp: return
        }
        if let data { Net.shared.broadcast(data, except: key) }
    }

    // MARK: 클라이언트

    private func handleFromHost(_ message: IncomingMessage) {
        switch message {
        case let .hello(msg):
            greet(msg)
        case let .bye(msg):
            World.shared.removePeer(id: msg.id)
        case .full:
            World.leaveRoom()
            tellRoomIsFull()
        case let .udp(msg):
            guard let key = hostKey, msg.token.utf8.count <= 64 else { return }
            Net.shared.openUDP(port: msg.port, token: msg.token, via: key)
        default:
            guard let id = message.senderID, id != World.shared.myID else { return }
            apply(message, from: id)
        }
    }

    private func greet(_ msg: HelloMsg) {
        guard let key = hostKey else { return }
        guard msg.pv == protocolVersion,
              let room = World.myRoom,
              msg.room == room,
              msg.id != World.shared.myID
        else {
            Net.shared.dropLink(key)
            return
        }
        // 호스트가 자기를 소개할 때 연결을 확정한다. 나머지는 호스트가 중계한 남이다
        if msg.id == hostID { Net.shared.identify(key, as: msg.id) }
        World.shared.addPeer(id: msg.id, name: sanitizeName(msg.name), look: msg.look.sanitized)
    }

    // MARK: 공통

    private func apply(_ message: IncomingMessage, from id: String) {
        switch message {
        case let .position(msg):
            guard abs(msg.x) <= Limits.maxX,
                  msg.y == nil || (msg.y! >= 0 && msg.y! <= Limits.maxY)
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
        case .hello, .bye, .full, .udp:
            break
        }
    }
}
