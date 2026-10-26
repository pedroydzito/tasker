import SwiftUI

/// Ícone do app: o mesmo símbolo de dentro do app (quadrado no azul de acento com o check),
/// no formato e na grade padrão de ícones do macOS.
enum AppIcon {
    private static let topo = Color(hex: "#24A9FF")
    private static let base = Color(hex: "#0084E8")

    @MainActor
    static var artwork: some View {
        ZStack {
            // Grade padrão do macOS: 824pt de arte num canvas de 1024.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [topo, base], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 12)

            Image(systemName: "checkmark")
                .font(.system(size: 420, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: Color(hex: "#004F8C").opacity(0.35), radius: 14, y: 8)
                .offset(y: 8)
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
