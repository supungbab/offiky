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
    private var udpListener: NWListener?
    /// 호스트가 나눠 준 토큰 → 그 클라이언트의 연결
    private var udpTokens: [String: String] = [:]
    /// 호스트일 때 알려 줄 UDP 포트. 메인에서만 읽고 쓴다
    var udpPort: UInt16?
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
        /// 좌표용 흐름. 호스트는 클라이언트가 토큰을 대고 연 흐름을, 클라이언트는 호스트로 연 흐름을 쥔다
        var udp: NWConnection?
        /// 클라이언트가 데이터그램 첫 줄에 적는 토큰
        var udpToken = Data()
        /// 상대의 데이터그램을 받아 양방향으로 통하는 것을 확인했다. 그 전에는 TCP 로도 보낸다
        var udpConfirmed = false
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
    /// 호스트라고 광고하는 사람들. 현직이 보이면 그대로 둔다
    private var claims: Set<String> = []
    /// 호스트 연결이 실패하면 쉬었다 다시 연결한다. 바로 다시 하면 실패가 반복되며 회전한다
    private var hostRetryAt: Date?
    private var dialWork: DispatchWorkItem?
    private var monitor: NWPathMonitor?
    private var restartWork: DispatchWorkItem?
    private var lastPath = ""
    private var running = false
    private var trafficWindowStart: TimeInterval = 0
    private var totalLines = 0
    /// 연결마다 flushDelay 동안 모아 둔다. 건마다 보내면 호스트의 send 가 인원의 제곱으로 는다
    private var pending: [String: Data] = [:]
    /// 좌표. UDP 가 통하면 그쪽으로 보낸다
    private var pendingFast: [String: Data] = [:]
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
        udpListener?.stateUpdateHandler = nil
        udpListener?.cancel(); udpListener = nil
        udpTokens.removeAll()
        browser?.stateUpdateHandler = nil
        browser?.cancel(); browser = nil
        visible.removeAll()
        claims.removeAll()
        host = nil
        dropAllLinks()
        flushWork?.cancel(); flushWork = nil
        pending.removeAll()
        pendingFast.removeAll()
        trafficWindowStart = 0
        totalLines = 0
        DispatchQueue.main.async {
            Presence.shared.otherVersions = 0
            self.udpPort = nil
        }
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
    /// 실행 중인 리스너의 service 를 다시 넣으면 광고가 갱신된다. 역할이 바뀔 때마다 부른다
    private func advertise() {
        guard let room = World.myRoom else { return }
        listener?.service = advertisement(room: room)
    }

    private func advertisement(room: String) -> NWListener.Service {
        NWListener.Service(
            name: World.shared.myID, type: serviceType,
            txtRecord: NWTXTRecord([
                "id": World.shared.myID,
                "pv": String(protocolVersion),
                "room": room,
                "rname": World.myRoomName ?? room,
                // 지금 중계를 맡고 있다는 표시. 새로 들어온 사람이 이걸 보고 현직에 붙는다
                "h": amHost ? "1" : "0",
            ]).data)
    }

    private func startListener() {
        guard let room = World.myRoom else { return }
        guard let listener = try? NWListener(using: Net.tcp) else { return }
        listener.service = advertisement(room: room)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.restart() }
        }
        listener.start(queue: queue)
        self.listener = listener
        startUDPListener()
    }

    /// UDP 가 막혀 있어도 TCP 만으로 동작하므로 실패하면 열지 않은 채로 둔다
    private func startUDPListener() {
        guard let udp = try? NWListener(using: .udp) else { return }
        udp.newConnectionHandler = { [weak self] flow in self?.acceptUDP(flow) }
        udp.stateUpdateHandler = { [weak self, weak udp] state in
            guard case .ready = state, let port = udp?.port?.rawValue else { return }
            DispatchQueue.main.async { self?.udpPort = port }
        }
        udp.start(queue: queue)
        udpListener = udp
    }

    /// 보낸 쪽마다 흐름이 하나씩 생긴다. 첫 데이터그램의 토큰으로 어느 클라이언트인지 판정한다
    private func acceptUDP(_ flow: NWConnection) {
        guard amHost else { flow.cancel(); return }
        flow.start(queue: queue)
        receiveDatagrams(flow, key: nil)
    }

    /// 호스트가 준 토큰을 이 연결에 묶는다. 같은 연결의 옛 토큰은 무효가 된다
    func allowUDP(_ token: String, for key: String) {
        queue.async {
            self.udpTokens = self.udpTokens.filter { $0.value != key }
            self.udpTokens[token] = key
        }
    }

    /// 클라이언트가 호스트의 UDP 포트로 흐름을 연다. 주소는 TCP 연결의 상대 주소를 쓴다
    func openUDP(port: Int, token: String, via key: String) {
        queue.async {
            guard let link = self.links[key], link.peerID != nil,
                  case let .hostPort(host, _)? = link.connection.currentPath?.remoteEndpoint,
                  let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port.rawValue > 0
            else { return }
            link.udp?.cancel()
            let flow = NWConnection(host: host, port: port, using: .udp)
            link.udp = flow
            link.udpToken = Data((token + "\n").utf8)
            link.udpConfirmed = false
            flow.stateUpdateHandler = { [weak link] state in
                guard case .failed = state, let link, link.udp === flow else { return }
                link.udp = nil
                link.udpConfirmed = false
            }
            flow.start(queue: self.queue)
            self.receiveDatagrams(flow, key: key)
        }
    }

    /// `key` 가 nil 이면 호스트가 받은 흐름이라 첫 줄이 토큰이다
    private func receiveDatagrams(_ flow: NWConnection, key known: String?) {
        flow.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            var lines = data ?? Data()
            let key: String
            if let known {
                key = known
            } else {
                guard let newline = lines.firstIndex(of: 0x0A),
                      let token = String(data: lines[..<newline], encoding: .utf8),
                      let bound = self.udpTokens[token]
                else { flow.cancel(); return }
                key = bound
                lines = Data(lines[lines.index(after: newline)...])
            }
            guard let link = self.links[key] else { flow.cancel(); return }
            if link.udp !== flow {
                // 클라이언트가 흐름을 다시 열었다. 받는 쪽은 호스트뿐이다
                guard known == nil else { flow.cancel(); return }
                link.udp?.cancel()
                link.udp = flow
            }
            link.udpConfirmed = true
            for line in lines.split(separator: 0x0A) {
                guard self.deliver(Data(line), from: link, key: key) else { return }
            }
            if error == nil { self.receiveDatagrams(flow, key: known) }
        }
    }

    private func startBrowser() {
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var entries: [(id: String, pv: String?, room: String?, roomName: String?)] = []
            var claiming: Set<String> = []
            for result in results {
                if case let .bonjour(txt) = result.metadata, let id = txt["id"] {
                    entries.append((id, txt["pv"], txt["room"], txt["rname"]))
                    if txt["h"] == "1" { claiming.insert(id) }
                }
            }
            self.claims = claiming
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
            : electHost(among: visible, claiming: claims, me: World.shared.myID)
        if elected != host {
            host = elected
            hostRetryAt = nil
            dropAllLinks()
            advertise()
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
        pendingFast[key] = nil
        udpTokens = udpTokens.filter { $0.value != key }
        link.udp?.cancel()
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
            link.udp?.cancel()
            link.handshakeWork?.cancel()
            link.connection.stateUpdateHandler = nil
            link.connection.cancel()
        }
        links.removeAll()
        pending.removeAll()
        pendingFast.removeAll()
        udpTokens.removeAll()
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
                while let newline = link.buffer.firstIndex(of: 0x0A) {
                    let line = Data(link.buffer[link.buffer.startIndex..<newline])
                    link.buffer.removeSubrange(link.buffer.startIndex...newline)
                    guard self.deliver(line, from: link, key: key) else { return }
                }
                // 개행이 없으면 위 검사에 닿지 않는다. 한 줄이 될 수 없는 조각이면 끊는다
                if link.buffer.count > Limits.maxMessageBytes { self.drop(key); return }
            }

            if isComplete || error != nil { self.drop(key); return }
            self.receiveLines(key: key)
        }
    }

    /// TCP 와 UDP 가 같은 한도를 쓴다. false 면 연결을 끊었다
    private func deliver(_ line: Data, from link: Link, key: String) -> Bool {
        if line.count > Limits.maxMessageBytes { drop(key); return false }
        let now = ProcessInfo.processInfo.systemUptime
        if now - link.windowStart >= 1 { link.windowStart = now; link.lines = 0 }
        if now - trafficWindowStart >= 1 {
            trafficWindowStart = now
            totalLines = 0
        }
        link.lines += 1
        totalLines += 1
        switch link.traffic.decision(linkLines: link.lines, totalLines: totalLines) {
        case .disconnect:
            drop(key)
            return false
        case .discard:
            return true
        case .forward:
            break
        }
        if !line.isEmpty { onLine?(line, key) }
        return true
    }

    /// 연결 목록은 이 큐에서만 바뀐다. 메인에서 바로 읽으면 바뀌는 중에 읽을 수 있다.
    /// `fast` 는 잃어도 다음 것이 대신하는 좌표다
    func broadcast(_ data: Data, except excluded: String? = nil, fast: Bool = false) {
        guard data.count <= Limits.maxMessageBytes else { return }
        var line = data; line.append(0x0A)
        queue.async {
            // hello 를 끝내지 않은 연결은 방과 버전을 증명하지 않았다. 이쪽 좌표와
            // 채팅을 받아 가게 두지 않고, 느린 연결에 송신 버퍼가 쌓이는 것도 막는다.
            for (key, link) in self.links
            where key != excluded && link.traffic.canReceiveBroadcast {
                self.enqueue(line, to: key, fast: fast)
            }
        }
    }

    func send(_ data: Data, to key: String) {
        guard data.count <= Limits.maxMessageBytes else { return }
        var line = data; line.append(0x0A)
        queue.async { self.enqueue(line, to: key) }
    }

    /// 줄은 개행으로 나뉘므로 이어 붙인 것을 한 번에 보내도 받는 쪽은 그대로 읽는다.
    /// 좌표 주기만큼 모으면 한 사람의 연속 좌표 두 건이 한 번에 나가 200ms 마다 도착한다
    static let flushDelay: TimeInterval = 0.02

    private func enqueue(_ line: Data, to key: String, fast: Bool = false) {
        if fast { pendingFast[key, default: Data()].append(line) }
        else { pending[key, default: Data()].append(line) }
        guard flushWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        flushWork = work
        queue.asyncAfter(deadline: .now() + Net.flushDelay, execute: work)
    }

    private func flush() {
        flushWork = nil
        for (key, data) in pending {
            links[key]?.connection.send(content: data, completion: .idempotent)
        }
        pending.removeAll(keepingCapacity: true)
        for (key, data) in pendingFast {
            guard let link = links[key] else { continue }
            let viaUDP = link.udp?.state == .ready
            if let udp = link.udp, viaUDP {
                // 호스트가 받은 흐름은 이미 누구인지 안다. 클라이언트만 토큰을 적는다
                let prefix = amHost ? Data() : link.udpToken
                for datagram in datagrams(data, prefix: prefix) {
                    udp.send(content: datagram, completion: .idempotent)
                }
            }
            if !viaUDP || !link.udpConfirmed {
                link.connection.send(content: data, completion: .idempotent)
            }
        }
        pendingFast.removeAll(keepingCapacity: true)
    }
}
