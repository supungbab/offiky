import AppKit
import SpriteKit
import SwiftUI

struct CharacterPickerView: View {
    /// 고르는 동안은 이 창 안에서만 바뀐다. 적용해야 화면과 동료에게 간다
    @State private var look = World.myLook
    @State private var applied = World.myLook

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

            HStack {
                Spacer()
                Button("적용") {
                    applied = look
                    World.myLook = look
                    Session.shared.sendProfile()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                // 바꾼 것이 없으면 누를 수 없다. 연타해도 한 번만 나간다
                .disabled(look == applied)
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
}

private var pickerWindow: NSWindow?

func openCharacterPicker() {
    if let window = pickerWindow {
        // 적용하지 않고 닫았던 초안을 버리고 지금 모습에서 다시 시작한다
        window.contentView = NSHostingView(rootView: CharacterPickerView())
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
