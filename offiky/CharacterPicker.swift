import SwiftUI

struct CharacterPickerView: View {
    /// 고르는 동안은 이 창 안에서만 바뀐다. 적용해야 화면과 동료에게 간다
    @State private var design = World.myLook.design
    @State private var applied = World.myLook.design

    private static let thumb: CGFloat = 44
    private static let gap: CGFloat = 6
    /// 프리셋 한 줄 길이. 넘치면 다음 줄로 내려가므로 모양마다 개수가 달라도 된다
    private static let perRow = 6

    /// 가장 프리셋이 많은 모양에 맞춰 자리를 비워 둔다. 모양을 옮길 때 창이 뛰지 않는다
    private static let maxRows = Characters.groups
        .map { ($0.designs.count + perRow - 1) / perRow }.max() ?? 1

    private var shape: Int {
        Characters.groups.firstIndex { $0.designs.contains(design) } ?? 0
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                shapes
                VStack(alignment: .leading, spacing: 12) {
                    preview
                    presets
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

    private var preview: some View {
        HStack(spacing: 10) {
            thumbnail(Look(design: design), size: 64)
            Text(Characters.preset(design))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var shapes: some View {
        VStack(spacing: 4) {
            ForEach(Array(Characters.groups.enumerated()), id: \.offset) { index, group in
                Button {
                    // 이미 그 모양이면 고른 프리셋을 지키고, 아니면 원본에서 시작한다
                    if index != shape { design = group.designs[0] }
                } label: {
                    VStack(spacing: 0) {
                        thumbnail(Look(design: group.designs[0]), size: 32)
                        Text(Characters.label(group.shape)).font(.system(size: 10))
                    }
                    .frame(width: 50)
                    .padding(.vertical, 3)
                    .background(index == shape ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var presets: some View {
        let designs = Characters.groups[shape].designs
        let cell = Self.thumb + 4
        return Grid(horizontalSpacing: Self.gap, verticalSpacing: Self.gap) {
            ForEach(Array(stride(from: 0, to: designs.count, by: Self.perRow)), id: \.self) { start in
                GridRow {
                    ForEach(designs[start ..< min(start + Self.perRow, designs.count)], id: \.self) {
                        button($0)
                    }
                }
            }
        }
        .frame(width: cell * CGFloat(Self.perRow) + Self.gap * CGFloat(Self.perRow - 1),
               height: cell * CGFloat(Self.maxRows) + Self.gap * CGFloat(Self.maxRows - 1),
               alignment: .topLeading)
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

private let pickerPanel = Panel()

/// 적용하지 않고 닫았던 초안을 버리고 지금 모습에서 다시 시작한다
func openCharacterPicker() {
    pickerPanel.show(title: "내 캐릭터", content: CharacterPickerView())
}
