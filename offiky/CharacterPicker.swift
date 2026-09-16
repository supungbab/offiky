import AppKit
import SpriteKit
import SwiftUI

struct CharacterPickerView: View {
    /// 고르는 동안은 이 창 안에서만 바뀐다. 적용해야 화면과 동료에게 간다
    @State private var design = World.myLook.design
    @State private var applied = World.myLook.design

    private static let thumb: CGFloat = 44
    private static let gap: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 한 줄이 한 모양이고 가로가 색이다
            Grid(horizontalSpacing: Self.gap, verticalSpacing: Self.gap) {
                ForEach(0..<Characters.count / Characters.colorCount, id: \.self) { shape in
                    GridRow {
                        ForEach(0..<Characters.colorCount, id: \.self) { color in
                            button(shape * Characters.colorCount + color)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("적용") {
                    applied = design
                    World.myLook = Look(design: design)
                    Session.shared.sendProfile()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                // 바꾼 것이 없으면 누를 수 없다. 연타해도 한 번만 나간다
                .disabled(design == applied)
            }
        }
        .padding(16)
    }

    private func button(_ index: Int) -> some View {
        Button {
            design = index
        } label: {
            thumbnail(Look(design: index), size: Self.thumb)
                .padding(2)
                .background(design == index ? Color.accentColor.opacity(0.25) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func thumbnail(_ look: Look, size: CGFloat) -> some View {
        Group {
            if let image = Characters.thumbnail(look) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }
}

private var pickerWindow: NSWindow?

func openCharacterPicker() {
    if let window = pickerWindow {
        // 적용하지 않고 닫았던 초안을 버리고 지금 모습에서 다시 시작한다
        let view = NSHostingView(rootView: CharacterPickerView())
        window.contentView = view
        window.setContentSize(view.fittingSize)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    // 격자가 색 개수만큼 넓어지므로 크기를 내용에 맞춘다
    let view = NSHostingView(rootView: CharacterPickerView())
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: view.fittingSize),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "내 캐릭터"
    window.contentView = view
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    pickerWindow = window
}
