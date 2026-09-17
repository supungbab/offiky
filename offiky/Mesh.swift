import Foundation
import Network

private let serviceType = "_offiky._tcp"

/// 모두가 모두에게 직접 붙는다. 중계하는 사람이 없으므로 한 사람에게 부담이 몰리지 않고,
/// 호스트 선출·교체와 그에 딸린 상태가 전부 없다.
final class Mesh {
    static let shared = Mesh()

    private let queue = DispatchQueue(label: "offiky.mesh")
    private var listener: NWListener?
    private var browser: NWBrowser?

    /// 연결 하나. 내가 건 쪽은 상대를 알고 시작하고, 받은 쪽은 hello 를 받아야 안다
    private final class Link {
        let connection: NWConnection
        var peerID: String?
        var buffer = Data()
        init(_ connection: NWConnection, peerID: String?) {
            self.connection = connection
            self.peerID = peerID
        }
    }

    private var links: [String: Link] = [:]
    private var visible: Set<String> = []
    /// 실패한 상대는 쉬었다 다시 건다. 바로 다시 걸면 실패가 반복되며 회전한다
    private var retryAfter: [String: Date] = [:]
    private var dialWork: DispatchWorkItem?
    private var monitor: NWPathMonitor?
    private var restartWork: DispatchWorkItem?
    private var lastPath = ""
    private var running = false

    static let retryDelay: TimeInterval = 5

    var onLine: ((Data, String) -> Void)?
    var onReady: ((String) -> Void)?
    var onGone: ((String) -> Void)?

    private init() {}

    /// 절전 알림과 앱 시작은 메인에서 온다. 상태는 전부 메시 큐 것이므로 넘겨서 만진다
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
        dialWork?.cancel()
        listener?.stateUpdateHandler = nil
        listener?.cancel(); listener = nil
        browser?.stateUpdateHandler = nil
        browser?.cancel(); browser = nil
        for link in links.values {
            link.connection.stateUpdateHandler = nil
            link.connection.cancel()
        }
        links.removeAll()
        visible.removeAll()
        retryAfter.removeAll()
        DispatchQueue.main.async {
            Presence.shared.otherVersions = 0
            Session.shared.reset()
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

    private func startListener() {
        guard let listener = try? NWListener(using: .tcp) else { return }
        listener.service = NWListener.Service(
            name: World.shared.myID, type: serviceType,
            txtRecord: NWTXTRecord([
                "id": World.shared.myID,
                "pv": String(protocolVersion),
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
            var entries: [(id: String, pv: String?)] = []
            for result in results {
                if case let .bonjour(txt) = result.metadata, let id = txt["id"] {
                    entries.append((id, txt["pv"]))
                }
            }
            let peers = compatiblePeers(entries)
            self.visible = peers.ids
            // 메뉴가 관찰하는 값으로 밀어 넣는다. 여기서 읽어 가게 두면
            // 값이 바뀌어도 메뉴를 다시 그릴 이유가 없어 경고가 뜨지 않는다
            DispatchQueue.main.async { Presence.shared.otherVersions = peers.mismatched }
            self.dial()
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.restart() }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    /// 한 쌍에 연결이 하나만 생기도록 id 가 큰 쪽에만 내가 건다. 상대는 받기만 한다
    private func dial() {
        dialWork?.cancel()
        let now = Date()
        var wakeAt: Date?
        for id in visible where id > World.shared.myID {
            if links.values.contains(where: { $0.peerID == id }) { continue }
            if let at = retryAfter[id], at > now {
                wakeAt = min(wakeAt ?? at, at)
                continue
            }
            connect(to: id)
        }
        guard let wakeAt else { return }
        let work = DispatchWorkItem { [weak self] in self?.dial() }
        dialWork = work
        queue.asyncAfter(deadline: .now() + max(0.1, wakeAt.timeIntervalSinceNow), execute: work)
    }

    private func connect(to id: String) {
        let endpoint = NWEndpoint.service(name: id, type: serviceType,
                                          domain: "local.", interface: nil)
        add(NWConnection(to: endpoint, using: .tcp), peerID: id)
    }

    private func accept(_ connection: NWConnection) {
        add(connection, peerID: nil)
    }

    private func add(_ connection: NWConnection, peerID: String?) {
        let key = UUID().uuidString
        let link = Link(connection, peerID: peerID)
        links[key] = link
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.links[key] === link else { return }
            switch state {
            case .ready:
                if let peerID { self.retryAfter[peerID] = nil }
                DispatchQueue.main.async { self.onReady?(key) }
            // .waiting 은 기한이 없다. 남겨 두면 dial 이 연결된 것으로 보고 다시 걸지 않는다
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
        link.connection.stateUpdateHandler = nil
        link.connection.cancel()
        if let id = link.peerID {
            retryAfter[id] = Date().addingTimeInterval(Mesh.retryDelay)
            dial()
        }
        DispatchQueue.main.async { self.onGone?(key) }
    }

    /// hello 를 받아 상대를 알게 됐다. 먼저 자리를 잡은 연결이 이긴다 —
    /// 나중에 온 쪽은 남의 id 를 대도 그 자리를 밀어내지 못하고 자기가 끊긴다
    func identify(_ key: String, as id: String) {
        queue.async {
            guard let link = self.links[key] else { return }
            // 내가 건 연결은 상대를 알고 시작했다. 다른 이름을 대면 그 연결이 아니다
            if let known = link.peerID, known != id { self.drop(key); return }
            if self.links.contains(where: { $0.key != key && $0.value.peerID == id }) {
                self.drop(key)
                return
            }
            link.peerID = id
        }
    }

    /// 쓸 수 없는 hello 를 보낸 연결을 끊는다. 두면 인사도 못 한 채 방송만 받아 간다
    func dropLink(_ key: String) {
        queue.async { self.drop(key) }
    }

    /// 좌표가 끊겨 없는 것으로 판정했다. 연결이 살아 있어도 쓸모없으므로 끊는다.
    /// 그냥 두면 상대가 다시 보내기 시작해도 hello 를 다시 받을 일이 없어 안 보인다
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
                    if line.count > Limits.maxMessageBytes { self.drop(key); return }
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
    func broadcast(_ data: Data) {
        var line = data; line.append(0x0A)
        queue.async {
            for link in self.links.values {
                link.connection.send(content: line, completion: .idempotent)
            }
        }
    }

    func send(_ data: Data, to key: String) {
        var line = data; line.append(0x0A)
        queue.async { self.links[key]?.connection.send(content: line, completion: .idempotent) }
    }
}
