import CoreGraphics
import Foundation

final class Session {
    static let shared = Session()

    private var seq = 0
    private var pending: [SayMsg] = []
    private var tracker = SeqTracker()
    private var profiles: [String: (name: String, look: Look)] = [:]
    private var positions: [String: PeerPos] = [:]
    private var clientIDs: [String: String] = [:]
    /// 호스트가 부여한 번호. 스냅샷에서 36자 UUID 대신 이걸 싣는다
    private var indexes: [String: Int] = [:]
    private var idByIndex: [Int: String] = [:]

    private var posTimer: Timer?
    private var snapTimer: Timer?

    private init() {}

    func start() {
        Mesh.shared.onLine = { [weak self] data, key in
            DispatchQueue.main.async { self?.handle(data, from: key) }
        }
        Mesh.shared.onUpstreamReady = { [weak self] in
            self?.sendHello()
        }
        Mesh.shared.onClientGone = { [weak self] key in
            DispatchQueue.main.async { self?.clientGone(key) }
        }

        posTimer = Timer.scheduledTimer(withTimeInterval: snapshotInterval, repeats: true) {
            [weak self] _ in self?.sendPosition()
        }
        snapTimer = Timer.scheduledTimer(withTimeInterval: snapshotInterval, repeats: true) {
            [weak self] _ in self?.sendSnapshotIfHost()
        }
    }

    fileprivate func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private func sendHello() {
        let me = World.shared.me
        Mesh.shared.sendToHost(encode(HelloMsg(
            id: World.shared.myID, name: me.displayName, look: World.myLook)))
        pending.forEach { Mesh.shared.sendToHost(encode($0)) }
    }

    private func index(for id: String) -> Int {
        if let n = indexes[id] { return n }
        let used = Set(indexes.values)
        var n = 0
        while used.contains(n) { n += 1 }
        indexes[id] = n
        return n
    }

    private func sendPosition() {
        let me = World.shared.me
        let msg = PosMsg(x: Double(me.x), y: me.y > 0 ? Double(me.y) : nil)
        if Mesh.shared.isHost {
            positions[World.shared.myID] = PeerPos(id: World.shared.myID, x: msg.x, y: msg.y)
        } else {
            Mesh.shared.sendToHost(encode(msg))
        }
    }

    private func sendSnapshotIfHost() {
        guard Mesh.shared.isHost else { return }
        let me = World.shared.me
        positions[World.shared.myID] = PeerPos(
            id: World.shared.myID, x: Double(me.x), y: me.y > 0 ? Double(me.y) : nil)

        var entries: [[Int]] = []
        entries.reserveCapacity(positions.count)
        for (peer, p) in positions {
            var entry = [index(for: peer), Int(p.x.rounded())]
            if let y = p.y, y > 0 { entry.append(Int(y.rounded())) }
            entries.append(entry)
        }
        Mesh.shared.broadcast(encode(SnapMsg(p: entries)))
    }

    func sendSay(_ text: String) {
        guard let body = validChat(text) else { return }
        seq += 1
        let msg = SayMsg(id: World.shared.myID, seq: seq, msg: body)
        if Mesh.shared.isHost {
            Mesh.shared.broadcast(encode(msg))
        } else {
            pending.append(msg)
            Mesh.shared.sendToHost(encode(SayMsg(seq: seq, msg: body)))
        }
        World.shared.showBubble(id: World.shared.myID, text: body)
    }

    func sendProfile() {
        let me = World.shared.me
        let look = World.myLook
        if Mesh.shared.isHost {
            Mesh.shared.broadcast(encode(
                ProfileMsg(id: World.shared.myID, name: me.displayName, look: look)))
        } else {
            Mesh.shared.sendToHost(encode(ProfileMsg(name: me.displayName, look: look)))
        }
    }

    /// 대기열을 가진 클라이언트가 스스로 호스트가 되면 재전송할 상대가 없다.
    func hostChanged() {
        // 번호는 호스트가 부여하므로 호스트가 바뀌면 체계가 새로 시작된다
        indexes.removeAll()
        idByIndex.removeAll()
        guard Mesh.shared.isHost else { return }
        pending.forEach { Mesh.shared.broadcast(encode($0)) }
        pending.removeAll()
    }

    /// 나간 피어의 흔적을 지운다. 호스트가 사라졌을 때도 여기로 온다.
    func peerGone(_ id: String) {
        profiles[id] = nil
        positions[id] = nil
        if let n = indexes.removeValue(forKey: id) { idByIndex[n] = nil }
        idByIndex = idByIndex.filter { $0.value != id }
        tracker.forget(id: id)
        World.shared.removePeer(id: id)
    }

    private func clientGone(_ key: String) {
        guard let id = clientIDs.removeValue(forKey: key) else { return }
        peerGone(id)
        Mesh.shared.broadcast(encode(LeaveMsg(id: id)))
    }

    private func handle(_ data: Data, from key: String?) {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        switch envelope.t {
        case "hello":   handleHello(data, key: key)
        case "pos":     handlePos(data, key: key)
        case "say":     handleSay(data, key: key)
        case "profile": handleProfile(data, key: key)
        case "join":    handleJoin(data)
        case "leave":   handleLeave(data)
        case "snap":    handleSnap(data)
        case "ack":     handleAck(data)
        default: break
        }
    }

    private func handleHello(_ data: Data, key: String?) {
        guard Mesh.shared.isHost, let key,
              let msg = try? JSONDecoder().decode(HelloMsg.self, from: data),
              msg.pv == protocolVersion
        else { return }

        clientIDs[key] = msg.id
        let name = sanitizeName(msg.name)
        let look = msg.look.sanitized
        profiles[msg.id] = (name, look)

        let me = World.shared.me
        Mesh.shared.send(encode(JoinMsg(
            id: World.shared.myID, name: me.displayName, look: World.myLook,
            n: index(for: World.shared.myID))), toClient: key)
        for (id, profile) in profiles where id != msg.id {
            Mesh.shared.send(encode(JoinMsg(
                id: id, name: profile.name, look: profile.look,
                n: index(for: id))), toClient: key)
        }
        Mesh.shared.broadcast(encode(JoinMsg(
            id: msg.id, name: name, look: look, n: index(for: msg.id))))
        World.shared.addPeer(id: msg.id, name: name, look: look)
    }

    private func handlePos(_ data: Data, key: String?) {
        guard Mesh.shared.isHost, let key, let id = clientIDs[key],
              let msg = try? JSONDecoder().decode(PosMsg.self, from: data),
              abs(msg.x) <= Limits.maxX,
              msg.y == nil || (msg.y! >= 0 && msg.y! <= Limits.maxY)
        else { return }
        positions[id] = PeerPos(id: id, x: msg.x, y: msg.y)
        // 호스트는 자기가 보낸 스냅샷을 받지 않으므로 여기서 직접 반영한다
        World.shared.setPeerTarget(id: id, x: CGFloat(msg.x), y: CGFloat(msg.y ?? 0))
    }

    private func handleSnap(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(SnapMsg.self, from: data) else { return }
        for entry in msg.p {
            guard entry.count >= 2,
                  let id = idByIndex[entry[0]], id != World.shared.myID
            else { continue }
            let x = Double(entry[1])
            let y = entry.count > 2 ? Double(entry[2]) : 0
            guard abs(x) <= Limits.maxX, y >= 0, y <= Limits.maxY else { continue }
            World.shared.setPeerTarget(id: id, x: CGFloat(x), y: CGFloat(y))
        }
    }

    private func handleSay(_ data: Data, key: String?) {
        guard var msg = try? JSONDecoder().decode(SayMsg.self, from: data),
              let body = validChat(msg.msg) else { return }

        if Mesh.shared.isHost, let key, let id = clientIDs[key] {
            msg.id = id
            Mesh.shared.send(encode(AckMsg(seq: msg.seq)), toClient: key)
            Mesh.shared.broadcast(encode(SayMsg(id: id, seq: msg.seq, msg: body)))
        }
        guard let id = msg.id, id != World.shared.myID,
              tracker.accept(id: id, seq: msg.seq) else { return }
        World.shared.showBubble(id: id, text: body)
    }

    private func handleAck(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(AckMsg.self, from: data) else { return }
        pending.removeAll { $0.seq <= msg.seq }
    }

    private func handleProfile(_ data: Data, key: String?) {
        guard var msg = try? JSONDecoder().decode(ProfileMsg.self, from: data) else { return }
        if Mesh.shared.isHost, let key, let id = clientIDs[key] {
            msg.id = id
            Mesh.shared.broadcast(encode(
                ProfileMsg(id: id, name: msg.name, look: msg.look)))
        }
        guard let id = msg.id, id != World.shared.myID else { return }
        let name = sanitizeName(msg.name)
        let look = msg.look.sanitized
        profiles[id] = (name, look)
        World.shared.addPeer(id: id, name: name, look: look)
    }

    private func handleJoin(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(JoinMsg.self, from: data),
              msg.id != World.shared.myID else { return }
        if let n = msg.n { idByIndex[n] = msg.id }
        let name = sanitizeName(msg.name)
        let look = msg.look.sanitized
        profiles[msg.id] = (name, look)
        World.shared.addPeer(id: msg.id, name: name, look: look)
    }

    private func handleLeave(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(LeaveMsg.self, from: data) else { return }
        peerGone(msg.id)
    }
}
