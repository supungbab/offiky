import CoreGraphics
import Foundation

/// 메시지를 주고받는다. 보내는 사람은 연결이 정하므로 좌표·채팅에 id 를 싣지 않는다.
final class Session {
    static let shared = Session()

    /// 연결 → 그 너머에 있는 사람
    private var peerByKey: [String: String] = [:]
    private var posTimer: Timer?
    private var lastSent: PosMsg?
    private var lastSentAt: TimeInterval = 0
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

    func start() {
        Mesh.shared.onLine = { [weak self] data, key in
            DispatchQueue.main.async { self?.handle(data, from: key) }
        }
        Mesh.shared.onReady = { [weak self] key in
            DispatchQueue.main.async { self?.sendHello(to: key) }
        }
        Mesh.shared.onGone = { [weak self] key in
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

    /// 양쪽 다 연결되자마자 보낸다. 받은 쪽이 따로 답할 필요가 없다
    private func sendHello(to key: String) {
        guard let room = World.myRoom else { Mesh.shared.dropLink(key); return }
        let me = World.shared.me
        guard let hello = encode(HelloMsg(id: World.shared.myID, name: me.displayName,
                                          look: World.myLook, room: room)),
              let position = encode(stamped(currentPosition()))
        else { Mesh.shared.dropLink(key); return }
        Mesh.shared.send(hello, to: key)
        // 서 있으면 다음 좌표가 몇 초 뒤다. 그때까지 내가 띠 왼쪽 끝에 서 있는 것으로 보인다
        Mesh.shared.send(position, to: key)
    }

    private func currentPosition() -> PosMsg {
        let me = World.shared.me
        return PosMsg(x: Double(me.x),
                      y: me.y > 0 ? Double(me.y) : nil,
                      b: me.isBowing ? true : nil,
                      d: me.isDragging ? true : nil,
                      f: Int(me.facingSign))
    }

    /// 받는 쪽이 도착 시각 대신 이걸로 표본을 놓는다. 망이 흔들려도 걸음이 고르다
    private func stamped(_ msg: PosMsg) -> PosMsg {
        var out = msg
        out.m = Int(ProcessInfo.processInfo.systemUptime * 1000)
        return out
    }

    private func sendPosition() {
        let msg = currentPosition()
        let now = ProcessInfo.processInfo.systemUptime
        guard shouldSend(msg, last: lastSent, since: now - lastSentAt) else { return }
        lastSent = msg
        lastSentAt = now
        if let data = encode(stamped(msg)) { Mesh.shared.broadcast(data) }
    }

    func sendSay(_ text: String) {
        guard let body = validChat(text) else { return }
        guard let data = encode(SayMsg(msg: body)) else { return }
        Mesh.shared.broadcast(data)
        World.shared.showBubble(id: World.shared.myID, text: body)
    }

    func sendProfile() {
        let me = World.shared.me
        if let data = encode(ProfileMsg(name: me.displayName, look: World.myLook)) {
            Mesh.shared.broadcast(data)
        }
    }

    /// 낙하는 소유자가 자기 캐릭터에 대해 판정한다. 결과만 다른 화면에 알린다.
    func sendHit() {
        if let data = encode(HitMsg()) { Mesh.shared.broadcast(data) }
    }

    /// 메시를 다시 시작할 때 이전 연결의 흔적을 전부 지운다.
    /// 남겨 두면 다시 붙을 때까지 멈춘 캐릭터가 화면에 남는다.
    func reset() {
        peerByKey.removeAll()
        lastSent = nil
        World.shared.removeAllPeers()
    }

    /// 좌표가 끊겨 없는 것으로 판정했을 때 World 가 부른다.
    /// 연결을 끊어 두면 다시 걸면서 hello 가 오가고 그때 되살아난다
    func peerGone(_ id: String) {
        World.shared.removePeer(id: id)
        Mesh.shared.dropLinks(to: id)
    }

    private func linkGone(_ key: String) {
        guard let id = peerByKey.removeValue(forKey: key) else { return }
        // 같은 사람과 두 경로로 붙는 일이 있다. 남은 연결이 있으면 지우지 않는다
        guard !peerByKey.values.contains(id) else { return }
        World.shared.removePeer(id: id)
    }

    private func handle(_ data: Data, from key: String) {
        guard let message = try? decoder.decode(IncomingMessage.self, from: data) else { return }
        switch message {
        case let .hello(msg):    handleHello(msg, key: key)
        case let .position(msg): handlePos(msg, key: key)
        case let .say(msg):      handleSay(msg, key: key)
        case let .profile(msg):  handleProfile(msg, key: key)
        case .hit:               handleHit(key: key)
        }
    }

    private func handleHello(_ msg: HelloMsg, key: String) {
        guard msg.pv == protocolVersion,
              let room = World.myRoom,
              msg.room == room,
              msg.id != World.shared.myID,
              !idIsTaken(msg.id, by: key, in: peerByKey)
        else {
            Mesh.shared.dropLink(key)
            return
        }
        peerByKey[key] = msg.id
        Mesh.shared.identify(key, as: msg.id)
        World.shared.addPeer(id: msg.id, name: sanitizeName(msg.name), look: msg.look.sanitized)
    }

    private func handlePos(_ msg: PosMsg, key: String) {
        guard let id = peerByKey[key],
              abs(msg.x) <= Limits.maxX,
              msg.y == nil || (msg.y! >= 0 && msg.y! <= Limits.maxY)
        else { return }
        World.shared.setPeerTarget(id: id, x: CGFloat(msg.x), y: CGFloat(msg.y ?? 0),
                                   bowing: msg.b == true, dragging: msg.d == true,
                                   facing: msg.f, sent: msg.m.map { Double($0) / 1000 })
    }

    private func handleSay(_ msg: SayMsg, key: String) {
        guard let id = peerByKey[key],
              let body = validChat(msg.msg)
        else { return }
        World.shared.showBubble(id: id, text: body)
    }

    private func handleProfile(_ msg: ProfileMsg, key: String) {
        guard let id = peerByKey[key] else { return }
        World.shared.addPeer(id: id, name: sanitizeName(msg.name), look: msg.look.sanitized)
    }

    private func handleHit(key: String) {
        guard let id = peerByKey[key] else { return }
        World.shared.peerWasHit(id: id)
    }
}
