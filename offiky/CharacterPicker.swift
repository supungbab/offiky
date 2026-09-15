import AppKit
import SwiftUI

struct CharacterPickerView: View {
    @State private var look = World.myLook

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("캐릭터").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 6), count: 5),
                      spacing: 6) {
                ForEach(0..<Sprite.designCount, id: \.self) { index in
                    thumbnail(index)
                }
            }

            Divider()

            Text("색").font(.headline)
            slider("색상", value: $look.hue, range: -0.5...0.5)
            slider("채도", value: $look.saturation, range: 0...2)
            slider("밝기", value: $look.brightness, range: 0.5...1.5)

            HStack {
                Button("색 초기화") {
                    look.hue = 0; look.saturation = 1; look.brightness = 1
                }
                Spacer()
                preview
            }
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
            image(Sprite.design(at: index, frame: 0, tint: candidate), size: 44)
                .padding(2)
                .background(look.design == index ? Color.accentColor.opacity(0.25) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        HStack(spacing: 4) {
            ForEach(0..<Sprite.frameCount, id: \.self) { frame in
                image(Sprite.design(at: look.design, frame: frame, tint: look), size: 48)
            }
        }
    }

    private func image(_ sprite: Sprite, size: CGFloat) -> some View {
        Group {
            if let cg = sprite.cgImage() {
                Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: size, height: size)))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>,
                        range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).frame(width: 28, alignment: .leading)
            Slider(value: value, in: range)
        }
    }

    private func apply(_ value: Look) {
        World.myLook = value
        Session.shared.sendProfile()
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
