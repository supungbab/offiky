import AppKit
import Observation

/// GitHub 릴리스에서 새 버전을 확인한다.
/// 샌드박스 안에서는 외부 프로그램을 실행할 수 없어 brew 를 직접 부르지 못한다.
/// 명령을 클립보드에 넣고 터미널을 열어 주는 선까지 한다 — 붙여 넣고 엔터는 본인이 한다.
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
    enum Result: Equatable { case upToDate, found(String), failed(Failure) }

    /// 실패를 뭉뚱그리면 한도에 걸린 것을 네트워크 탓으로 잘못 알린다
    enum Failure {
        case offline, busy, unexpected

        var reason: String {
            switch self {
            case .offline:
                "네트워크 상태를 확인해 주세요."
            case .busy:
                "GitHub 이 잠시 요청을 받지 않습니다. 조금 뒤 다시 시도해 주세요."
            case .unexpected:
                "GitHub 응답을 읽지 못했습니다. 릴리스 페이지에서 직접 확인해 주세요."
            }
        }
    }

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
                // 문장마다 줄을 나눈다. 한 줄로 두면 대화상자 폭에 맞춰 아무 데서나 끊긴다
                alert.informativeText = "현재 버전은 \(current) 입니다.\n터미널에 ⌘V 로 붙여 넣으세요."
                alert.addButton(withTitle: "복사하고 터미널 열기")
                alert.addButton(withTitle: "릴리스 페이지")
                alert.addButton(withTitle: "나중에")
            case .failed(let why):
                alert.alertStyle = .warning
                alert.messageText = "확인하지 못했습니다"
                alert.informativeText = why.reason
                alert.addButton(withTitle: "확인")
            }
            NSApp.activate(ignoringOtherApps: true)
            let clicked = alert.runModal()
            if case .found = result {
                if clicked == .alertFirstButtonReturn { copyCommand(); openTerminal() }
                if clicked == .alertSecondButtonReturn { openReleasePage() }
            }
        }
    }

    /// api.github.com 은 인증 없이 IP 당 시간당 60회다. 사무실은 NAT 뒤라 전원이
    /// 그 60회를 나눠 쓰고, 다 쓰면 아무 잘못 없이 모두가 403 을 받는다.
    /// 이 피드는 일반 github.com 이라 그 한도를 받지 않는다 —
    /// 대신 사전 배포판도 목록에 들어오므로, 올리면 그것도 새 버전으로 알린다
    @discardableResult
    func check(force: Bool = false) async -> Result {
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 1800 {
            return newVersion.map { Result.found($0) } ?? .upToDate
        }
        lastCheck = Date()

        var request = URLRequest(url: URL(string: "https://github.com/\(repo)/releases.atom")!,
                                 timeoutInterval: 15)
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request)
        else { return .failed(.offline) }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            return .failed(status == 403 || status == 429 || status >= 500 ? .busy : .unexpected)
        }
        guard let tag = UpdateChecker.latestTag(inFeed: String(decoding: data, as: UTF8.self))
        else { return .failed(.unexpected) }

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        // 받아 온 값을 주소에 넣지 않고 내가 아는 저장소로 조립한다
        releaseURL = URL(string: "https://github.com/\(repo)/releases/tag/\(tag)")
        newVersion = UpdateChecker.isNewer(latest, than: current) ? latest : nil
        return newVersion.map { Result.found($0) } ?? .upToDate
    }

    /// 피드는 새것부터 나열되므로 첫 항목이 최신이다.
    /// 태그는 주소에도 쓰므로 쓸 수 있는 글자만 받는다 — 그 밖이면 못 읽은 것으로 본다
    nonisolated static func latestTag(inFeed xml: String) -> String? {
        let pattern = "<id>tag:github\\.com,[0-9]+:Repository/[0-9]+/([A-Za-z0-9._-]+)</id>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml)
        else { return nil }
        return String(xml[range])
    }

    /// 터미널에 붙여넣기만 하면 되도록 클립보드에 넣는다
    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew update && brew upgrade --cask \(cask)",
                                     forType: .string)
    }

    /// Homebrew 로 받지 않았으면 이 명령이 듣지 않는다. 그때는 릴리스 페이지로 간다
    private func openTerminal() {
        guard let terminal = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return }
        NSWorkspace.shared.openApplication(at: terminal,
                                           configuration: NSWorkspace.OpenConfiguration())
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
