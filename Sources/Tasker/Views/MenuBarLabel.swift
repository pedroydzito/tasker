import SwiftUI

/// Ícone da barra de menu: símbolo de tarefa + contador do dia.
/// Renderizado como imagem "template" para se adaptar ao tema claro/escuro da barra.
struct MenuBarLabel: View {
    let store: TaskStore

    var body: some View {
        let count = store.auth.isSignedIn ? store.badgeCount : 0
        let showCount = store.prefs.showCountInMenuBar && count > 0

        if let image = render(count: count, showCount: showCount, style: store.prefs.menuBarStyle) {
            Image(nsImage: image)
        } else {
            Image(systemName: "checklist")
        }
    }

    @MainActor
    private func render(count: Int, showCount: Bool, style: MenuBarStyle) -> NSImage? {
        let content = Group {
            if showCount && style == .numberInSquare {
                Image(systemName: count <= 50 ? "\(count).square" : "square.fill")
                    .font(.system(size: 15, weight: .medium))
            } else {
                HStack(spacing: 3) {
                    Image(systemName: count == 0 ? "checkmark.circle" : "checklist")
                        .font(.system(size: 14, weight: .medium))
                    if showCount {
                        Text("\(count)")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 1)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}
