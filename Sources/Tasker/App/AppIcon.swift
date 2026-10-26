import SwiftUI

/// Ícone do app desenhado em código (aparece no Dock quando a janela está aberta).
enum AppIcon {
    @MainActor
    static func make() -> NSImage? {
        let view = ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#6C8CFF"), Color(hex: "#3D5AFE")],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            Image(systemName: "checkmark.circle")
                .font(.system(size: 470, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 1024, height: 1024)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage
    }
}
