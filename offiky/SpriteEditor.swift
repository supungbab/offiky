import AppKit
import SwiftUI

struct SpriteEditorView: View {
    /// 각 칸은 "RRGGBB" 또는 Sprite.transparent
    @State private var rows: [[String]]
    @State private var selected: String = "000000"
    @State private var picked: Color = .black
    @State private var undoStack: [[[String]]] = []
    @State private var strokeOpen = false

    private let cell: CGFloat = 22

    init() {
        _rows = State(initialValue: World.mySprite.rows.map { Sprite.chunks(of: $0) })
    }

    var body: some View {
        VStack(spacing: 12) {
            designs
            grid
            presets
            HStack(spacing: 10) {
                ColorPicker("색", selection: $picked, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: picked) { _, value in selected = Self.hex(value) }
                swatch(Sprite.transparent, fill: .clear, label: "지우개")
                Spacer()
                Text("#\(selected.uppercased())")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("되돌리기") { undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Spacer()
                Button("저장") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private var designs: some View {
        HStack(spacing: 4) {
            ForEach(0..<Sprite.designCount, id: \.self) { index in
                let sprite = Sprite.design(at: index)
                Button {
                    push()
                    rows = sprite.rows.map { Sprite.chunks(of: $0) }
                } label: {
                    if let cg = sprite.cgImage() {
                        Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: 32, height: 32)))
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 32, height: 32)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<16, id: \.self) { y in
                HStack(spacing: 0) {
                    ForEach(0..<16, id: \.self) { x in
                        Rectangle()
                            .fill(Self.color(rows[y][x]))
                            .frame(width: cell, height: cell)
                            .border(Color.gray.opacity(0.3), width: 0.5)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { paint(at: $0.location) }
                .onEnded { _ in strokeOpen = false })
    }

    private func paint(at point: CGPoint) {
        let x = Int(point.x / cell), y = Int(point.y / cell)
        guard (0..<16).contains(x), (0..<16).contains(y) else { return }
        if !strokeOpen { push(); strokeOpen = true }
        rows[y][x] = selected
    }

    private var presets: some View {
        HStack(spacing: 4) {
            ForEach(Palette.presets, id: \.self) { rgb in
                let hex = String(format: "%06x", rgb)
                swatch(hex, fill: Self.color(hex), label: nil)
            }
        }
    }

    private func swatch(_ value: String, fill: Color, label: String?) -> some View {
        Rectangle()
            .fill(fill)
            .frame(width: 20, height: 20)
            .overlay(Rectangle().stroke(
                selected == value ? Color.accentColor : .gray.opacity(0.4),
                lineWidth: selected == value ? 3 : 1))
            .help(label ?? "#\(value.uppercased())")
            .onTapGesture {
                selected = value
                if value != Sprite.transparent { picked = Self.color(value) }
            }
    }

    private static func color(_ value: String) -> Color {
        guard value != Sprite.transparent, let rgb = UInt32(value, radix: 16) else { return .clear }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }

    private static func hex(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "%02x%02x%02x",
                      Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()),
                      Int((ns.blueComponent * 255).rounded()))
    }

    private func push() {
        undoStack.append(rows)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    private func undo() { if let last = undoStack.popLast() { rows = last } }

    private func save() {
        let lines = rows.map { $0.joined() }
        guard let sprite = Sprite(encoded: lines.joined(separator: "\n")) else { return }
        UserDefaults.standard.set(sprite.encoded, forKey: "sprite")
        World.shared.me.apply(sprite: sprite)
        Session.shared.sendProfile()
    }
}

private var editorWindow: NSWindow?

func openSpriteEditor() {
    if let window = editorWindow {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 520),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "내 캐릭터"
    window.contentView = NSHostingView(rootView: SpriteEditorView())
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    editorWindow = window
}
