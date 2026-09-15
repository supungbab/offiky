import Foundation
import Network

private let serviceType = "_offiky._tcp"

final class Mesh {
    static let shared = Mesh()

    private let queue = DispatchQueue(label: "offiky.mesh")
    private var listener: NWListener?
    private var browser: NWBrowser?

    private var clients: [String: NWConnection] = [:]
    private var upstream: NWConnection?

    private var visible: Set<String> = []
    private var excluded: [String: Date] = [:]
    private var currentHost: String?
    private var debounce: DispatchWorkItem?
    private var buffers: [String: Data] = [:]

    var isHost: Bool { currentHost == World.shared.myID }

    var onLine: ((Data, String?) -> Void)?
    var onUpstreamReady: (() -> Void)?
    var onClientGone: ((String) -> Void)?

    private init() {}

    func start() {
        startListener()
        startBrowser()
    }

    func stop() {
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        cancelUpstream()
        clients.values.forEach { $0.stateUpdateHandler = nil; $0.cancel() }
        clients.removeAll()
        buffers.removeAll()
        visible.removeAll()
        currentHost = nil
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
        listener.start(queue: queue)
        self.listener = listener
    }

    /// 분열 구간에 호스트가 아닌 피어에게도 연결이 들어온다.
    /// 종료하면 상대가 재계산해 올바른 호스트로 이동한다.
    private func accept(_ connection: NWConnection) {
        guard isHost else { connection.cancel(); return }
        let key = UUID().uuidString
        clients[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.clients[key] = nil
                self?.buffers[key] = nil
                self?.onClientGone?(key)
            default: break
            }
        }
        connection.start(queue: queue)
        receiveLines(on: connection, from: key)
    }

    private func startBrowser() {
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var ids: Set<String> = []
            for result in results {
                if case let .bonjour(txt) = result.metadata, let id = txt["id"] {
                    ids.insert(id)
                }
            }
            self.visible = ids
            self.scheduleElection()
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func scheduleElection() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.elect() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func elect() {
        excluded = excluded.filter { Date().timeIntervalSince($0.value) < 10 }
        let host = electHost(candidates: visible,
                             excluded: Set(excluded.keys),
                             me: World.shared.myID)
        guard host != currentHost else { return }
        currentHost = host

        cancelUpstream()
        buffers["upstream"] = nil
        if !isHost { connectToHost(host) }
        DispatchQueue.main.async { Session.shared.hostChanged() }
    }

    /// 연결이 끊어진 피어는 Bonjour 목록에서 사라지기를 기다리지 않는다.
    /// 비정상 종료 시 mDNS TTL 만료까지 수십 초가 걸린다.
    private func exclude(_ id: String) {
        excluded[id] = Date()
        DispatchQueue.main.async { Session.shared.peerGone(id) }
        scheduleElection()
    }

    /// 우리가 끊는 것이므로 실패 처리가 돌면 안 된다. 살아 있는 호스트를 나간 것으로 지운다
    private func cancelUpstream() {
        upstream?.stateUpdateHandler = nil
        upstream?.cancel()
        upstream = nil
    }

    private func connectToHost(_ id: String) {
        let endpoint = NWEndpoint.service(name: id, type: serviceType,
                                          domain: "local.", interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async { self?.onUpstreamReady?() }
            case .failed, .cancelled:
                self?.exclude(id)
            default: break
            }
        }
        connection.start(queue: queue)
        upstream = connection
        receiveLines(on: connection, from: nil)
    }

    private func receiveLines(on connection: NWConnection, from key: String?) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            let bufferKey = key ?? "upstream"

            if let data, !data.isEmpty {
                var buffer = self.buffers[bufferKey, default: Data()]
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<newline])
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if line.count > Limits.maxMessageBytes {
                        self.buffers[bufferKey] = nil
                        connection.cancel()
                        return
                    }
                    if !line.isEmpty { self.onLine?(line, key) }
                }
                self.buffers[bufferKey] = buffer
            }

            if isComplete || error != nil {
                connection.cancel()
                if key == nil, let host = self.currentHost { self.exclude(host) }
                return
            }
            self.receiveLines(on: connection, from: key)
        }
    }

    func sendToHost(_ data: Data) {
        var line = data; line.append(0x0A)
        upstream?.send(content: line, completion: .idempotent)
    }

    func broadcast(_ data: Data) {
        var line = data; line.append(0x0A)
        for connection in clients.values {
            connection.send(content: line, completion: .idempotent)
        }
    }

    func send(_ data: Data, toClient key: String) {
        var line = data; line.append(0x0A)
        clients[key]?.send(content: line, completion: .idempotent)
    }
}
