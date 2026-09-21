import AppKit
import SwiftUI

/// 메뉴에서 여는 작은 창. 채팅창처럼 다른 곳을 클릭하면 사라져서
/// 열어 둔 채 잊어버릴 일이 없다.
final class Panel {
    private var window: NSWindow?
    /// 띄우는 동안 잠깐 키를 놓치는 것을 닫으라는 뜻으로 읽지 않는다
    private var presenting = false

    func show(title: String, content: some View) {
        let isNew = window == nil
        let window = self.window ?? {
            let created = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                                   backing: .buffered, defer: false)
            created.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: created, queue: .main
            ) { [weak self] _ in
                if self?.presenting == false { created.orderOut(nil) }
            }
            self.window = created
            return created
        }()

        window.title = title
        let view = NSHostingView(rootView: content)
        window.contentView = view
        window.setContentSize(view.fittingSize)
        // 크기를 정한 뒤에 가운데로 옮긴다. 처음 열 때만이고 그 뒤엔 놓아둔 자리를 지킨다
        if isNew { window.center() }

        presenting = true
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.presenting = false
            // 그 사이에 다른 곳을 클릭했으면 알림이 무시됐다. 여기서 확인한다
            if !window.isKeyWindow { window.orderOut(nil) }
        }
    }
}
