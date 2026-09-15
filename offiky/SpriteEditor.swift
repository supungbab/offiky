import AppKit
import SwiftUI

struct SpriteEditorView: View {
    @State private var rows: [[Character]]
    @State private var selected: Character = "0"
    @State private var undoStack: [[[Character]]] = []
    @State private var strokeOpen = false

    private let cell: CGFloat = 22

    init() {
        _rows = State(initialValue: World.storedSprite(for: World.shared.myID).rows.map(Array.init))
    }

    var body: some View {
        VStack(spacing: 12) {
            grid
            palette
            HStack {
                Button("기본 캐릭터로 초기화") {
                    push()
                    rows = Sprite.standard(for: World.shared.myID).rows.map(Array.init)
                }
                Button("되돌리기") { undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Spacer()
                Button("저장") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<16, id: \.self) { y in
                HStack(spacing: 0) {
                    ForEach(0..<16, id: \.self) { x in
                        Rectangle()
                            .fill(color(rows[y][x]))
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

    private var palette: some View {
        HStack(spacing: 4) {
            ForEach(0..<16, id: \.self) { index in
                let ch = Character(String(index, radix: 16))
                swatch(ch, fill: color(ch))
            }
            swatch(".", fill: .clear)
        }
    }

    private func swatch(_ ch: Character, fill: Color) -> some View {
        Rectangle()
            .fill(fill)
            .frame(width: 20, height: 20)
            .overlay(Rectangle().stroke(
                selected == ch ? Color.accentColor : .gray.opacity(0.4),
                lineWidth: selected == ch ? 3 : 1))
            .onTapGesture { selected = ch }
    }

    private func color(_ ch: Character) -> Color {
        guard let index = ch.hexDigitValue, index < Palette.rgb.count else { return .clear }
        let rgb = Palette.rgb[index]
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }

    private func push() {
        undoStack.append(rows)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    private func undo() { if let last = undoStack.popLast() { rows = last } }

    private func save() {
        let lines: [String] = rows.map { String($0) }
        let encoded = lines.joined(separator: "\n")
        guard let sprite = Sprite(encoded: encoded) else { return }
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
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 500),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "내 캐릭터"
    window.contentView = NSHostingView(rootView: SpriteEditorView())
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    editorWindow = window
}
