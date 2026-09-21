import Foundation
import Network

private let serviceType = "_offiky._tcp"

/// 방에서 id 가 가장 작은 사람이 호스트다. 클라이언트는 호스트에게만 연결하고 호스트가 중계한다.
final class Net {
    static let shared = Net()

    private let queue = DispatchQueue(label: "offiky.net")

    /// 좌표는 30바이트씩 초당 열 번 간다. Nagle 이 켜져 있으면 앞 패킷의 ACK 를
    /// 기다렸다 뭉쳐 보내, 상대의 지연 ACK 와 맞물리면 수십 ms 씩 늦는다
    private static let tcp: NWParameters = {
        let options = NWProtocolTCP.Options()
        options.noDelay = true
        return NWParameters(tls: nil, tcp: options)
    }()
    private var listener: NWListener?
    private var browser: NWBrowser?

    /// 연결 하나. 내가 시작한 쪽은 상대를 알고 시작하고, 받은 쪽은 hello 를 받아야 안다
    private final class Link {
        let connection: NWConnection
        var peerID: String?
        var traffic: LinkTrafficPolicy
        var buffer = Data()
        var windowStart: TimeInterval = 0
        var lines = 0
        var handshakeWork: DispatchWorkItem?
        init(_ connection: NWConnection, peerID: String?, maxLines: Int, maxPending: Int) {
            self.connection = connection
            self.peerID = peerID
            self.traffic = LinkTrafficPolicy(
                startedAt: ProcessInfo.processInfo.systemUptime,
                maxLines: maxLines, maxPending: maxPending)
        }
    }

    private var links: [String: Link] = [:]
    private var visible: Set<String> = []
    /// 지금 호스트로 판정한 사람. 방에 없으면 nil
    private var host: String?
    /// 호스트 연결이 실패하면 쉬었다 다시 연결한다. 바로 다시 하면 실패가 반복되며 회전한다
    private var hostRetryAt: Date?
    private var dialWork: DispatchWorkItem?
    private var monitor: NWPathMonitor?
    private var restartWork: DispatchWorkItem?
    private var lastPath = ""
    private var running = false
    private var trafficWindowStart: TimeInterval = 0
    private var totalLines = 0
    /// 연결마다 한 틱 분량을 모아 둔다. 건마다 보내면 호스트의 send 가 인원의 제곱으로 는다
    private var pending: [String: Data] = [:]
    private var flushWork: DispatchWorkItem?

    static let retryDelay: TimeInterval = 5
    static let handshakeTimeout: TimeInterval = 5

    var onLine: ((Data, String) -> Void)?
    /// 연결이 열렸다. 내가 연 연결이면 상대 id 를 이미 안다
    var onReady: ((String, String?) -> Void)?
    var onGone: ((String) -> Void)?

    private init() {}

    private var amHost: Bool { host == World.shared.myID }

    /// 절전 알림과 앱 시작은 메인에서 온다. 상태는 전부 이 큐 것이므로 넘겨서 만진다
    func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.startListener()
            self.startBrowser()
            self.startPathMonitor()
        }
    }

    func stop() {
        queue.async {
            guard self.running else { return }
            self.running = false
            self.monitor?.cancel(); self.monitor = nil
            self.lastPath = ""
            self.teardown()
        }
    }

    /// 경로 감시는 남겨 둔다. 다시 시작할 때 이걸 쓴다
    private func teardown() {
        restartWork?.cancel()
        listener?.stateUpdateHandler = nil
        listener?.cancel(); listener = nil
        browser?.stateUpdateHandler = nil
        browser?.cancel(); browser = nil
        visible.removeAll()
        host = nil
        dropAllLinks()
        flushWork?.cancel(); flushWork = nil
        pending.removeAll()
        trafficWindowStart = 0
        totalLines = 0
        DispatchQueue.main.async { Presence.shared.otherVersions = 0 }
    }

    /// 방이 바뀌면 붙어 있던 사람들과 헤어지고 새 이름으로 다시 광고한다
    func roomChanged() {
        queue.async {
            guard self.running else { return }
            self.teardown()
            self.startListener()
            self.startBrowser()
        }
    }

    /// 전환 중에는 알림이 여러 번 오므로 잦아들기를 기다린다
    private func restart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.teardown()
            self.startListener()
            self.startBrowser()
        }
        restartWork = work
        queue.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Wi-Fi 를 바꾸거나 이더넷을 뽑으면 열어 둔 리스너와 연결이 쓸모없어진다.
    /// 절전 복귀와 달리 알려 주는 알림이 없으므로 직접 감시한다.
    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let key = "\(path.status)|"
                + path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            guard key != self.lastPath else { return }
            let firstReport = self.lastPath.isEmpty
            self.lastPath = key
            if !firstReport { self.restart() }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    /// 클라이언트도 리스너를 연다 — 이게 광고 수단이고, 언제든 호스트가 될 수 있기 때문이다
    private func startListener() {
        guard let room = World.myRoom else { return }
        let roomName = World.myRoomName ?? room
        guard let listener = try? NWListener(using: Net.tcp) else { return }
        listener.service = NWListener.Service(
            name: World.shared.myID, type: serviceType,
            txtRecord: NWTXTRecord([
                "id": World.shared.myID,
                "pv": String(protocolVersion),
                "room": room,
                "rname": roomName,
            ]).data)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.restart() }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func startBrowser() {
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var entries: [(id: String, pv: String?, room: String?, roomName: String?)] = []
            for result in results {
                if case let .bonjour(txt) = result.metadata, let id = txt["id"] {
                    entries.append((id, txt["pv"], txt["room"], txt["rname"]))
                }
            }
            // 방에 없어도 듣기는 한다. 참여할 방 목록을 보여줘야 하기 때문이다
            let peers = compatiblePeers(entries, myRoom: World.myRoom)
            self.visible = peers.ids
            // 메뉴가 관찰하는 값으로 밀어 넣는다. 여기서 읽어 가게 두면
            // 값이 바뀌어도 메뉴를 다시 그릴 이유가 없어 경고가 뜨지 않는다
            DispatchQueue.main.async {
                Presence.shared.otherVersions = peers.mismatched
                if Presence.shared.rooms != peers.rooms { Presence.shared.rooms = peers.rooms }
            }
            self.elect()
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.restart() }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    /// 광고를 볼 때마다 다시 판정한다. 호스트가 사라지면 남은 사람 중 가장 작은 id 가 호스트가 된다
    private func elect() {
        let elected = World.myRoom == nil
            ? nil
            : electHost(among: visible, me: World.shared.myID)
        if elected != host {
            host = elected
            hostRetryAt = nil
            dropAllLinks()
        }
        dial()
    }

    /// 호스트는 연결하지 않는다 — 받기만 한다
    private func dial() {
        dialWork?.cancel()
        guard let host, host != World.shared.myID else { return }
        guard !links.values.contains(where: { $0.peerID == host }) else { return }
        if let at = hostRetryAt, at > Date() {
            let work = DispatchWorkItem { [weak self] in self?.dial() }
            dialWork = work
            queue.asyncAfter(deadline: .now() + max(0.1, at.timeIntervalSinceNow), execute: work)
            return
        }
        let endpoint = NWEndpoint.service(name: host, type: serviceType,
                                          domain: "local.", interface: nil)
        add(NWConnection(to: endpoint, using: Net.tcp), peerID: host)
    }

    private func accept(_ connection: NWConnection) {
        // 클라이언트는 받지 않는다. 호스트가 아닌 동안 들어온 연결은 옛 판정에서 온 것이다
        guard amHost, links.count < Limits.maxLinks else { connection.cancel(); return }
        add(connection, peerID: nil)
    }

    private func add(_ connection: NWConnection, peerID: String?) {
        // Bonjour 결과를 위조해 대량으로 광고해도 연결 수가 끝없이 늘어나면 안 된다
        guard links.count < Limits.maxLinks else { connection.cancel(); return }
        let key = UUID().uuidString
        // 호스트 연결 하나에는 전원 몫이 중계되어 온다. 클라이언트 하나가 보내는 양과 다르다
        let toHost = peerID != nil
        let link = Link(connection, peerID: peerID,
                        maxLines: toHost
                            ? Limits.maxRelayedLinesPerSecond : Limits.maxLinesPerSecond,
                        maxPending: toHost
                            ? Limits.maxRosterLines : Limits.maxPendingLines)
        links[key] = link
        let handshakeWork = DispatchWorkItem { [weak self, weak link] in
            guard let self, let link, self.links[key] === link,
                  link.traffic.handshakeExpired(
                    at: ProcessInfo.processInfo.systemUptime,
                    timeout: Net.handshakeTimeout)
            else { return }
            self.drop(key)
        }
        link.handshakeWork = handshakeWork
        queue.asyncAfter(deadline: .now() + Net.handshakeTimeout, execute: handshakeWork)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.links[key] === link else { return }
            switch state {
            case .ready:
                if peerID != nil { self.hostRetryAt = nil }
                DispatchQueue.main.async { self.onReady?(key, peerID) }
            // .waiting 은 기한이 없다. 남겨 두면 dial 이 연결된 것으로 보고 다시 하지 않는다
            case .failed, .cancelled, .waiting:
                self.drop(key)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveLines(key: key)
    }

    private func drop(_ key: String) {
        guard let link = links.removeValue(forKey: key) else { return }
        pending[key] = nil
        link.handshakeWork?.cancel()
        link.connection.stateUpdateHandler = nil
        link.connection.cancel()
        // 내가 시작한 연결만 다시 연결한다. 받은 연결은 저쪽에서 다시 온다
        if link.peerID != nil {
            hostRetryAt = Date().addingTimeInterval(Net.retryDelay)
            dial()
        }
        DispatchQueue.main.async { self.onGone?(key) }
    }

    /// 호스트가 바뀌면 이전 구성의 연결은 전부 쓸모없다
    private func dropAllLinks() {
        dialWork?.cancel()
        for link in links.values {
            link.handshakeWork?.cancel()
            link.connection.stateUpdateHandler = nil
            link.connection.cancel()
        }
        links.removeAll()
        pending.removeAll()
        let amHost = self.amHost
        DispatchQueue.main.async { Session.shared.roleChanged(amHost: amHost) }
    }

    /// hello 를 받아 상대를 알게 됐다. 먼저 자리를 잡은 연결이 이긴다 —
    /// 나중에 온 쪽은 남의 id 를 대도 그 자리를 밀어내지 못하고 자기가 끊긴다
    func identify(_ key: String, as id: String) {
        queue.async {
            guard let link = self.links[key] else { return }
            // 내가 시작한 연결은 상대를 알고 있다. 다른 이름을 대면 그 연결이 아니다
            if let known = link.peerID, known != id { self.drop(key); return }
            if self.links.contains(where: { $0.key != key && $0.value.peerID == id }) {
                self.drop(key)
                return
            }
            link.peerID = id
            link.traffic.identify()
            link.handshakeWork?.cancel()
            link.handshakeWork = nil
        }
    }

    /// 쓸 수 없는 hello 를 보낸 연결을 끊는다. 두면 인사도 못 한 채 방송만 받아 간다
    func dropLink(_ key: String) {
        queue.async { self.drop(key) }
    }

    /// 좌표가 끊겨 없는 것으로 판정했다. 연결이 살아 있어도 쓸모없으므로 끊는다
    func dropLinks(to id: String) {
        queue.async {
            for (key, link) in self.links where link.peerID == id { self.drop(key) }
        }
    }

    private func receiveLines(key: String) {
        guard let link = links[key] else { return }
        let connection = link.connection
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            // 취소한 연결도 마지막 콜백이 한 번 온다. 버린 연결이면 무시한다
            guard self.links[key] === link else { return }

            if let data, !data.isEmpty {
                link.buffer.append(data)
                let now = ProcessInfo.processInfo.systemUptime
                if now - link.windowStart >= 1 { link.windowStart = now; link.lines = 0 }
                if now - self.trafficWindowStart >= 1 {
                    self.trafficWindowStart = now
                    self.totalLines = 0
                }
                while let newline = link.buffer.firstIndex(of: 0x0A) {
                    let line = Data(link.buffer[link.buffer.startIndex..<newline])
                    link.buffer.removeSubrange(link.buffer.startIndex...newline)
                    if line.count > Limits.maxMessageBytes { self.drop(key); return }
                    link.lines += 1
                    self.totalLines += 1
                    switch link.traffic.decision(linkLines: link.lines,
                                                 totalLines: self.totalLines) {
                    case .disconnect:
                        self.drop(key)
                        return
                    case .discard:
                        continue
                    case .forward:
                        break
                    }
                    if !line.isEmpty { self.onLine?(line, key) }
                }
                // 개행이 없으면 위 검사에 닿지 않는다. 한 줄이 될 수 없는 조각이면 끊는다
                if link.buffer.count > Limits.maxMessageBytes { self.drop(key); return }
            }

            if isComplete || error != nil { self.drop(key); return }
            self.receiveLines(key: key)
        }
    }

    /// 연결 목록은 이 큐에서만 바뀐다. 메인에서 바로 읽으면 바뀌는 중에 읽을 수 있다
    func broadcast(_ data: Data, except excluded: String? = nil) {
        guard data.count <= Limits.maxMessageBytes else { return }
        var line = data; line.append(0x0A)
        queue.async {
            // hello 를 끝내지 않은 연결은 방과 버전을 증명하지 않았다. 이쪽 좌표와
            // 채팅을 받아 가게 두지 않고, 느린 연결에 송신 버퍼가 쌓이는 것도 막는다.
            for (key, link) in self.links
            where key != excluded && link.traffic.canReceiveBroadcast {
                self.enqueue(line, to: key)
            }
        }
    }

    func send(_ data: Data, to key: String) {
        guard data.count <= Limits.maxMessageBytes else { return }
        var line = data; line.append(0x0A)
        queue.async { self.enqueue(line, to: key) }
    }

    /// 줄은 개행으로 나뉘므로 이어 붙인 것을 한 번에 보내도 받는 쪽은 그대로 읽는다.
    /// 좌표를 보내는 주기와 같이 모으면 사람마다 한 틱에 한 건씩 정확히 담긴다
    private func enqueue(_ line: Data, to key: String) {
        pending[key, default: Data()].append(line)
        guard flushWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        flushWork = work
        queue.asyncAfter(deadline: .now() + positionInterval, execute: work)
    }

    private func flush() {
        flushWork = nil
        for (key, data) in pending {
            links[key]?.connection.send(content: data, completion: .idempotent)
        }
        pending.removeAll(keepingCapacity: true)
    }
}
