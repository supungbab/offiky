import SwiftUI

@main
struct offikyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("offiky", systemImage: "person.2.fill") {
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        OverlayController.shared.start()
    }
}
