import AppKit
import Observation

/// GitHub 릴리스에서 새 버전을 확인하고, brew 로 설치했으면 그대로 업그레이드한다.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    private(set) var newVersion: String?
    private(set) var busy = false

    private let repo = "supungbab/offiky"
    private let cask = "offiky"
    private var releaseURL: URL?
    private var lastCheck: Date?

    private init() {}

    var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 인증 없이 시간당 60회가 한도라 너무 자주 묻지 않는다
    func check(force: Bool = false) async {
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 1800 { return }
        lastCheck = Date()

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!,
                                 timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = json["html_url"] as? String,
              // 이 주소를 그대로 브라우저에 넘기므로 출처를 확인한다
              let url = URL(string: page), url.scheme == "https", url.host == "github.com"
        else { return }

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        releaseURL = url
        newVersion = UpdateChecker.isNewer(latest, than: current) ? latest : nil
    }

    /// brew 로 깔았으면 앱을 끄고 업그레이드한 뒤 다시 연다. 아니면 릴리스 페이지를 연다.
    func update() {
        guard newVersion != nil, !busy else { return }
        busy = true
        Task {
            let brew = await Task.detached { UpdateChecker.brewPath() }.value
            if let brew {
                UpdateChecker.runUpgrade(brew: brew, cask: cask)
                NSApp.terminate(nil)
            } else {
                busy = false
                if let releaseURL { NSWorkspace.shared.open(releaseURL) }
            }
        }
    }

    /// "2.0.10" 이 "2.0.9" 보다 높다. 문자열로 비교하면 반대로 나온다.
    nonisolated static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(left.count, right.count) {
            let a = i < left.count ? left[i] : 0
            let b = i < right.count ? right[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// 이 cask 로 설치된 경우에만 brew 경로를 돌려준다
    private nonisolated static func brewPath() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brew = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return nil }

        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: brew)
        probe.arguments = ["list", "--cask", "offiky"]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        guard (try? probe.run()) != nil else { return nil }
        probe.waitUntilExit()
        return probe.terminationStatus == 0 ? brew : nil
    }

    /// 앱이 종료된 뒤에 돌아야 하므로 떼어 놓고 실행한다
    private nonisolated static func runUpgrade(brew: String, cask: String) {
        let script = """
        sleep 2
        "\(brew)" update >/dev/null 2>&1
        "\(brew)" upgrade --cask \(cask) >/dev/null 2>&1
        open -a offiky
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try? process.run()
    }
}
