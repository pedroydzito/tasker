import SwiftUI

/// Ícone do app: azulejo azul-violeta no formato do macOS, com um "check" branco
/// e o selo laranja — o mesmo conceito do ícone da barra de menu.
enum AppIcon {
    private static let blue = Color(hex: "#4C7DFF")
    private static let violet = Color(hex: "#6B4CF0")

    @MainActor
    static var artwork: some View {
        ZStack {
            // Grade padrão de ícones do macOS: 824pt de arte num canvas de 1024.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [blue, violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 22, y: 12)

            // Disco branco com o check.
            Circle()
                .fill(.white)
                .frame(width: 470, height: 470)
                .shadow(color: Color(hex: "#2A1E8C").opacity(0.35), radius: 26, y: 14)
            Image(systemName: "checkmark")
                .font(.system(size: 230, weight: .black))
                .foregroundStyle(LinearGradient(colors: [blue, violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                .offset(y: 6)

            // Selo laranja (contador).
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "#FFA23A"), Color(hex: "#FF6A2C")], startPoint: .top, endPoint: .bottom))
                .frame(width: 176, height: 176)
                .overlay(Circle().strokeBorder(.white, lineWidth: 18))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                .offset(x: 182, y: 182)
        }
        .frame(width: 1024, height: 1024)
    }

    @MainActor
    static func make() -> NSImage? {
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 1
        return renderer.nsImage
    }

    /// Usado pelo build (`Tasker --export-icon arquivo.png`) para gerar o .icns.
    @MainActor
    static func export(to path: String) -> Bool {
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 1
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
