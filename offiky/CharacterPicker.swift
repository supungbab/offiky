import AppKit
import SpriteKit
import SwiftUI

struct CharacterPickerView: View {
    @State private var look = World.myLook
    @State private var sendTask: Task<Void, Never>?

    private let goatPack = URL(string: "https://chaoswitchnikol.itch.io/goat-characters")!
    private let animalPack = URL(string: "https://chaoswitchnikol.itch.io/animal-characters")!
    private let license = URL(string: "https://creativecommons.org/licenses/by/4.0/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("캐릭터").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 6), count: 5),
                      spacing: 6) {
                ForEach(0..<Characters.count, id: \.self) { index in
                    thumbnail(index)
                }
            }

            Divider()

            HStack {
                Text("색").font(.headline)
                Spacer()
                Button {
                    look.hue = 0; look.saturation = 1; look.brightness = 1
                } label: {
                    Label("초기화", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isNeutral)
            }

            slider("색상", value: $look.hue, range: -0.5...0.5)
            slider("채도", value: $look.saturation, range: 0...2)
            slider("밝기", value: $look.brightness, range: 0.5...1.5)

            Divider()
            HStack {
                Spacer()
                preview
                Spacer()
            }

            // CC BY 4.0 은 출처 표기가 조건이다
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("캐릭터 그림: ChaosWitchNikol")
                Link("Goat Characters", destination: goatPack)
                Link("Animal Characters", destination: animalPack)
                Link("CC BY 4.0 — 색을 조정해 사용합니다", destination: license)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
        .onChange(of: look) { _, value in apply(value) }
    }

    private func thumbnail(_ index: Int) -> some View {
        var candidate = look
        candidate.design = index
        return Button {
            look.design = index
        } label: {
            thumb(candidate, animation: .idle, frame: 0, size: 44)
                .padding(2)
                .background(look.design == index ? Color.accentColor.opacity(0.25) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        HStack(spacing: 2) {
            ForEach(0..<Animation.walk.frameCount, id: \.self) { frame in
                thumb(look, animation: .walk, frame: frame, size: 40)
            }
        }
    }

    private func thumb(_ look: Look, animation: Animation,
                       frame: Int, size: CGFloat) -> some View {
        let sheet = Characters.sheet(look)
        let textures = sheet.frames[animation] ?? []
        let scale = size / max(sheet.size.width, sheet.size.height)
        return Group {
            if frame < textures.count,
               let cg = textures[frame].cgImage() as CGImage? {
                Image(nsImage: NSImage(cgImage: cg, size: NSSize(
                    width: sheet.size.width * scale, height: sheet.size.height * scale)))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: sheet.size.width * scale, height: sheet.size.height * scale)
            }
        }
        .frame(width: size, height: size)
    }

    private var isNeutral: Bool {
        look.hue == 0 && look.saturation == 1 && look.brightness == 1
    }

    private func slider(_ title: String, value: Binding<Double>,
                        range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).frame(width: 28, alignment: .leading)
            Slider(value: value, in: range)
        }
    }

    /// 화면은 즉시 바꾸고 전송만 늦춘다. 슬라이더를 한 번 끌면
    /// 전원에게 가는 브로드캐스트가 수십 개 나간다.
    private func apply(_ value: Look) {
        World.myLook = value
        sendTask?.cancel()
        sendTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            Session.shared.sendProfile()
        }
    }
}

private var pickerWindow: NSWindow?

func openCharacterPicker() {
    if let window = pickerWindow {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 400),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "내 캐릭터"
    window.contentView = NSHostingView(rootView: CharacterPickerView())
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    pickerWindow = window
}
