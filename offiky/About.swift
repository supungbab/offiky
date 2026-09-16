import AppKit
import SwiftUI

/// 버전이 다르면 서로 보이지 않으므로 동료끼리 대조할 수 있어야 한다.
/// 빌드 번호는 배포마다 버전과 함께 올라가므로 보여줄 것이 없다.
var appVersion: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String ?? "?"
    #if DEBUG
    return "\(version) · 디버그"
    #else
    return version
    #endif
}

struct AboutView: View {
    private let repo = URL(string: "https://github.com/supungbab/offiky")!
    private let goatPack = URL(string: "https://chaoswitchnikol.itch.io/goat-characters")!
    private let animalPack = URL(string: "https://chaoswitchnikol.itch.io/animal-characters")!
    private let license = URL(string: "https://creativecommons.org/licenses/by/4.0/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offiky").font(.title2).bold()
                    Text(appVersion).foregroundStyle(.secondary)
                    Link("저장소", destination: repo).font(.callout)
                }
            }

            Text("같은 네트워크에 있는 동료들의 캐릭터가 화면 바닥을 돌아다닌다.\n서버도 중계자도 없이 서로 직접 연결한다.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // CC BY 4.0 은 출처 표기가 조건이다
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                Text("캐릭터 그림: ChaosWitchNikol")
                Link("Goat Characters", destination: goatPack)
                Link("Animal Characters", destination: animalPack)
                Link("CC BY 4.0 — 색을 바꿔 사용합니다", destination: license)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
    }
}

private var aboutWindow: NSWindow?

func openAbout() {
    if let window = aboutWindow {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    let view = NSHostingView(rootView: AboutView())
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: view.fittingSize),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Offiky 정보"
    window.contentView = view
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    aboutWindow = window
}
