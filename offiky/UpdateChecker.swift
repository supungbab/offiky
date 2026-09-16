import AppKit
import Observation

/// GitHub 릴리스에서 새 버전을 확인한다.
/// 샌드박스 안에서는 외부 프로그램을 실행할 수 없어 brew 를 직접 부르지 못한다.
/// 명령을 클립보드에 넣어 주는 선까지 한다.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    private(set) var newVersion: String?

    private let repo = "supungbab/offiky"
    private let cask = "offiky"
    private var releaseURL: URL?
    private var lastCheck: Date?

    private init() {}

    var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 조회에 실패하면 조용히 넘기지 않는다. 사내망에서 GitHub 이 막혀 있어도
    /// 사용자는 최신인 줄 알게 되기 때문이다.
    enum Result { case upToDate, found(String), failed }

    /// 메뉴는 누르는 순간 닫히므로 결과를 대화상자로 알린다
    func checkAndTell() {
        Task {
            let result = await check(force: true)
            let alert = NSAlert()
            switch result {
            case .upToDate:
                alert.messageText = "최신 버전입니다"
                alert.informativeText = "Offiky \(current) 를 사용 중입니다."
                alert.addButton(withTitle: "확인")
            case .found(let version):
                alert.messageText = "새 버전 \(version) 이 있습니다"
                alert.informativeText = "현재 \(current) 를 사용 중입니다."
                alert.addButton(withTitle: "업데이트 명령 복사")
                alert.addButton(withTitle: "릴리스 페이지")
                alert.addButton(withTitle: "나중에")
            case .failed:
                alert.alertStyle = .warning
                alert.messageText = "확인하지 못했습니다"
                alert.informativeText = "네트워크 상태를 확인해 주세요."
                alert.addButton(withTitle: "확인")
            }
            NSApp.activate(ignoringOtherApps: true)
            let clicked = alert.runModal()
            if case .found = result {
                if clicked == .alertFirstButtonReturn { copyCommand() }
                if clicked == .alertSecondButtonReturn { openReleasePage() }
            }
        }
    }

    /// 인증 없이 시간당 60회가 한도라 너무 자주 묻지 않는다
    @discardableResult
    func check(force: Bool = false) async -> Result {
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 1800 {
            return newVersion.map { Result.found($0) } ?? .upToDate
        }
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
        else { return .failed }

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        releaseURL = url
        newVersion = UpdateChecker.isNewer(latest, than: current) ? latest : nil
        return newVersion.map { Result.found($0) } ?? .upToDate
    }

    /// 터미널에 붙여넣기만 하면 되도록 클립보드에 넣는다
    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew upgrade --cask \(cask)", forType: .string)
    }

    private func openReleasePage() {
        if let releaseURL { NSWorkspace.shared.open(releaseURL) }
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
}
