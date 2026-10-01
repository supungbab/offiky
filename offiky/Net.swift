import Foundation
import Network

private let serviceType = "_offiky._tcp"

/// 같은 방 사람끼리 모두 직접 연결한다. 두 사람 사이의 연결은 id 가 작은 쪽이 연다
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
    /// 내가 나눠 준 토큰 → 그 연결. 연결을 연 상대가 이 토큰을 대고 UDP 흐름을 연다
    private var udpTokens: [String: String] = [:]
    /// 받은 연결의 상대에게 알려 줄 UDP 포트. 메인에서만 읽고 쓴다
    var udpPort: UInt16? {
        didSet { if udpPort != nil, udpPort != oldValue { onUDPPort?() } }
    }
    private var browser: NWBrowser?

    /// 연결 하나. 내가 연 쪽은 상대를 알고 시작하고, 받은 쪽은 hello 를 받아야 안다
    private final class Link {
        let connection: NWConnection
        var peerID: String?
        /// 상대가 연 연결. UDP 흐름은 이쪽이 받는다
        let inbound: Bool
        var traffic = LinkTrafficPolicy(startedAt: ProcessInfo.processInfo.systemUptime)
        var buffer = Data()
        var windowStart: TimeInterval = 0
        var lines = 0
        var handshakeWork: DispatchWorkItem?
        /// 좌표용 흐름. 받은 쪽은 상대가 토큰을 대고 연 흐름을, 연 쪽은 상대에게 연 흐름을 가진다
        var udp: NWConnection?
        /// 연 쪽이 데이터그램 첫 줄에 적는 토큰
        var udpToken = ""
        /// 양방향으로 통하는 것을 확인했다. 그 전에는 TCP 로도 보낸다.
        /// 연 쪽은 상대 데이터그램을 받았을 때, 받은 쪽은 연 쪽이 그렇다고 알려 왔을 때다
        var udpConfirmed = false
        init(_ connection: NWConnection, peerID: String?) {
            self.connection = connection
            self.peerID = peerID
            self.inbound = peerID == nil
        }
    }

    private var links: [String: Link] = [:]
    /// 같은 방에서 광고가 보이는 사람
    private var visible: Set<String> = []
    /// 연결이 실패한 사람 → 다시 여는 시각. 광고만 남은 사람에게는 이 주기로만 시도한다
    private var retryAt: [String: Date] = [:]
    private var dialWork: DispatchWorkItem?
    private var monitor: NWPathMonitor?
    private var restartWork: DispatchWorkItem?
    private var lastPath = ""
    private var running = false
    private var trafficWindowStart: TimeInterval = 0
    private var totalLines = 0
    /// 연결마다 flushDelay 동안 모아 둔다. 건마다 보내면 send 가 그만큼 는다
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
    /// UDP 포트를 알게 됐다. 메인에서 호출된다
    var onUDPPort: (() -> Void)?

    private init() {}

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
        browser?.stateUpdateHandler = nil
        browser?.cancel(); browser = nil
        visible.removeAll()
        retryAt.removeAll()
        dropAllLinks()
        flushWork?.cancel(); flushWork = nil
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
                + "|" + path.gateways.map(\.debugDescription).sorted().joined(separator: ",")
            guard key != self.lastPath else { return }
            let firstReport = self.lastPath.isEmpty
            self.lastPath = key
            if !firstReport { self.restart() }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    private func advertisement(room: String) -> NWListener.Service {
        NWListener.Service(
            name: World.shared.myID, type: serviceType,
            txtRecord: NWTXTRecord([
                "id": World.shared.myID,
                "pv": String(protocolVersion),
                "room": room,
                "rname": World.myRoomName ?? room,
            ]).data)
    }

    /// 리스너가 광고 수단이기도 하다. 방에 없으면 열지 않는다
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

    /// 보낸 쪽마다 흐름이 하나씩 생긴다. 첫 데이터그램의 토큰으로 어느 연결인지 판정한다
    private func acceptUDP(_ flow: NWConnection) {
        flow.start(queue: queue)
        receiveDatagrams(flow, key: nil)
    }

    /// 내가 준 토큰을 이 연결에 묶는다. 같은 연결의 옛 토큰은 무효가 된다
    func allowUDP(_ token: String, for key: String) {
        queue.async {
            self.udpTokens = self.udpTokens.filter { $0.value != key }
            self.udpTokens[token] = key
        }
    }

    /// 내가 연 연결의 상대 UDP 포트로 흐름을 연다. 주소는 TCP 연결의 상대 주소를 쓴다
    func openUDP(port: Int, token: String, via key: String) {
        queue.async {
            guard let link = self.links[key], !link.inbound,
                  case let .hostPort(host, _)? = link.connection.currentPath?.remoteEndpoint,
                  let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port.rawValue > 0
            else { return }
            link.udp?.cancel()
            let flow = NWConnection(host: host, port: port, using: .udp)
            link.udp = flow
            link.udpToken = token
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

    /// `key` 가 nil 이면 받은 흐름이라 첫 줄이 토큰이다
    private func receiveDatagrams(_ flow: NWConnection, key known: String?) {
        flow.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            var lines = data ?? Data()
            let key: String
            // 연 쪽은 받은 쪽이 먼저 받아야 보내 오므로, 받았으면 양방향이 통한다
            var confirmed = true
            if let known {
                key = known
            } else {
                guard let newline = lines.firstIndex(of: 0x0A),
                      let prefix = readUDPPrefix(Data(lines[..<newline])),
                      let bound = self.udpTokens[prefix.token]
                else { flow.cancel(); return }
                key = bound
                confirmed = prefix.acked
                lines = Data(lines[lines.index(after: newline)...])
            }
            guard let link = self.links[key] else { flow.cancel(); return }
            if link.udp !== flow {
                // 상대가 흐름을 다시 열었다. 받는 쪽만 새 흐름으로 교체한다
                guard known == nil else { flow.cancel(); return }
                link.udp?.cancel()
                link.udp = flow
                link.udpConfirmed = false
            }
            if confirmed { link.udpConfirmed = true }
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
            self?.browsed(results)
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.restart() }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    /// 광고가 사라져도 연결은 끊지 않는다. 연결이 살아 있는지는 연결이 알려 준다
    private func browsed(_ results: Set<NWBrowser.Result>) {
        var entries: [(id: String, pv: String?, room: String?, roomName: String?)] = []
        for result in results {
            if case let .bonjour(txt) = result.metadata, let id = txt["id"] {
                entries.append((id, txt["pv"], txt["room"], txt["rname"]))
            }
        }
        // 방에 없어도 듣기는 한다. 참여할 방 목록을 보여줘야 하기 때문이다
        let peers = compatiblePeers(entries, myRoom: World.myRoom)
        visible = peers.ids.subtracting([World.shared.myID])
        retryAt = retryAt.filter { visible.contains($0.key) }
        // 메뉴가 관찰하는 값으로 밀어 넣는다. 여기서 읽어 가게 두면
        // 값이 바뀌어도 메뉴를 다시 그릴 이유가 없어 경고가 뜨지 않는다
        DispatchQueue.main.async {
            Presence.shared.otherVersions = peers.mismatched
            if Presence.shared.rooms != peers.rooms { Presence.shared.rooms = peers.rooms }
        }
        dial()
    }

    /// 나보다 id 가 큰 사람에게만 연다. 작은 사람은 저쪽에서 연다
    private func dial() {
        dialWork?.cancel()
        guard World.myRoom != nil else { return }
        let me = World.shared.myID
        let now = Date()
        var next: Date?
        for id in visible where me < id && !links.values.contains(where: { $0.peerID == id }) {
            if let at = retryAt[id], at > now { next = min(next ?? at, at); continue }
            guard links.count < Limits.maxLinks else { break }
            let endpoint = NWEndpoint.service(name: id, type: serviceType,
                                              domain: "local.", interface: nil)
            add(NWConnection(to: endpoint, using: Net.tcp), peerID: id)
        }
        guard let next else { return }
        let work = DispatchWorkItem { [weak self] in self?.dial() }
        dialWork = work
        queue.asyncAfter(deadline: .now() + max(0.1, next.timeIntervalSinceNow), execute: work)
    }

    private func accept(_ connection: NWConnection) {
        guard World.myRoom != nil, links.count < Limits.maxLinks else { connection.cancel(); return }
        add(connection, peerID: nil)
    }

    private func add(_ connection: NWConnection, peerID: String?) {
        // Bonjour 결과를 위조해 대량으로 광고해도 연결 수가 끝없이 늘어나면 안 된다
        guard links.count < Limits.maxLinks else { connection.cancel(); return }
        let key = UUID().uuidString
        let link = Link(connection, peerID: peerID)
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
        close(link)
        // 내가 연 연결만 다시 연다. 받은 연결은 저쪽에서 다시 온다
        if !link.inbound, let peer = link.peerID {
            retryAt[peer] = Date().addingTimeInterval(Net.retryDelay)
            dial()
        }
        DispatchQueue.main.async { self.onGone?(key) }
    }

    private func close(_ link: Link) {
        link.udp?.cancel()
        link.handshakeWork?.cancel()
        link.connection.stateUpdateHandler = nil
        link.connection.cancel()
    }

    /// 방을 옮기거나 망이 바뀌면 이전 연결은 전부 쓸모없다
    private func dropAllLinks() {
        dialWork?.cancel()
        let keys = Array(links.keys)
        links.values.forEach(close)
        links.removeAll()
        pending.removeAll()
        pendingFast.removeAll()
        udpTokens.removeAll()
        DispatchQueue.main.async { keys.forEach { self.onGone?($0) } }
    }

    /// hello 를 받아 상대를 알게 됐다. 먼저 자리를 잡은 연결이 이긴다 —
    /// 나중에 온 쪽은 남의 id 를 대도 그 자리를 밀어내지 못하고 자기가 끊긴다
    func identify(_ key: String, as id: String) {
        queue.async {
            guard let link = self.links[key] else { return }
            // 내가 연 연결은 상대를 알고 있다. 다른 이름을 대면 그 연결이 아니다
            if let known = link.peerID, known != id { self.drop(key); return }
            if self.links.contains(where: { $0.key != key && $0.value.peerID == id }) {
                self.drop(key)
                return
            }
            link.peerID = id
            link.traffic.identify()
            self.retryAt[id] = nil
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
    func broadcast(_ data: Data, fast: Bool = false) {
        guard data.count <= Limits.maxMessageBytes else { return }
        var line = data; line.append(0x0A)
        queue.async {
            // hello 를 끝내지 않은 연결은 방과 버전을 증명하지 않았다. 이쪽 좌표와
            // 채팅을 받아 가게 두지 않고, 느린 연결에 송신 버퍼가 쌓이는 것도 막는다.
            for (key, link) in self.links where link.traffic.isIdentified {
                self.enqueue(line, to: key, fast: fast)
            }
        }
    }

    func send(_ data: Data, to key: String) {
        guard data.count <= Limits.maxMessageBytes else { return }
        var line = data; line.append(0x0A)
        queue.async { self.enqueue(line, to: key) }
    }

    /// 줄은 개행으로 나뉘므로 합친 것을 한 번에 보내도 받는 쪽은 그대로 읽는다
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
                // 받은 흐름은 이미 누구인지 안다. 흐름을 연 쪽만 토큰을 적는다
                let prefix = link.inbound
                    ? Data() : udpPrefix(token: link.udpToken, acked: link.udpConfirmed)
                for datagram in datagrams(data, prefix: prefix) {
                    #if DEBUG
                    // `-netLoss 0.05 -netJitter 0.08` 로 나쁜 망을 모사한다
                    let defaults = UserDefaults.standard
                    if Double.random(in: 0..<1) < defaults.double(forKey: "netLoss") { continue }
                    let jitter = defaults.double(forKey: "netJitter")
                    if jitter > 0 {
                        queue.asyncAfter(deadline: .now() + .random(in: 0...jitter)) {
                            udp.send(content: datagram, completion: .idempotent)
                        }
                        continue
                    }
                    #endif
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
