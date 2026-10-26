import AppKit
import CoreText
import SwiftUI

// Tokens do design system (ver design-system.md do appdocs).
// Regra 1: nenhum hexadecimal, duração ou raio escrito à mão fora deste arquivo.

// MARK: Cor

enum DS {
    // Superfícies e texto — papel quente no claro, preto de verdade no escuro.
    static let fundo = cor("#f5f4f0", "#0a0a0a")
    static let superficie = cor("#fffefb", "#141414")
    static let superficie2 = cor("#eceae3", "#1c1c1c")
    static let superficie3 = cor("#e2dfd6", "#262626")
    static let borda = cor("#e0ddd4", "#242424")
    static let bordaForte = cor("#cdc9bd", "#363636")
    static let texto = cor("#16130f", "#fafaf9")
    static let texto2 = cor("#4a453e", "#b8b5b0")
    static let texto3 = cor("#6b645b", "#8b8781")

    // Acento: identidade, não semântica.
    static let acento = Color(nsColor: NSColor(hex: "#f43a2b"))
    static let acentoSolido = acento
    static let acentoSolidoTexto = Color.white
    static let acentoTexto = cor("#b9190c", "#f55b4f")
    static let anelFoco = cor("#f43a2b66", "#f43a2b80")

    // Papéis.
    static let perigo = acento
    static let perigoTenue = cor("#f43a2b1a", "#f43a2b29")
    static let sucesso = cor("#0f7a52", "#4ade9b")
    static let sucessoTenue = cor("#0f7a521a", "#4ade9b24")
    static let aviso = cor("#9a5b12", "#e0a458")
    static let avisoTenue = cor("#9a5b121a", "#e0a45824")
    static let link = cor("#1f5fd0", "#7cb2ff")

    // Véu de hover: preto no claro, branco no escuro — a superfície se aproxima do ponteiro.
    static let veuHover = cor("#0000000e", "#ffffff12")
    static let veuAtivo = cor("#00000017", "#ffffff1c")
    static let veuModal = Color.black.opacity(0.4)

    /// Quanto da cor de categoria entra no fundo de um chip tingido.
    static let chipTinta = 0.10

    static func cor(_ claro: String, _ escuro: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: escuro) : NSColor(hex: claro)
        })
    }

    // MARK: Raio

    static let raioP: CGFloat = 8       // ladrilho de ícone
    static let raioM: CGFloat = 12      // botão, campo
    static let raioG: CGFloat = 16      // painel interno
    static let raioCartao: CGFloat = 20 // cartão, folha, menu

    // MARK: Espaço (passos 1–8)

    static let e1: CGFloat = 4
    static let e2: CGFloat = 8
    static let e3: CGFloat = 12
    static let e4: CGFloat = 16
    static let e5: CGFloat = 20
    static let e6: CGFloat = 24
    static let e8: CGFloat = 32

    // MARK: Movimento — duas durações e duas curvas

    static let tempoRapido = 0.15
    static let tempoNormal = 0.28
    /// Tudo que ENTRA.
    static let curva = Animation.timingCurve(0.22, 1, 0.36, 1, duration: tempoNormal)
    static let curvaRapida = Animation.timingCurve(0.22, 1, 0.36, 1, duration: tempoRapido)
    /// Tudo que SAI.
    static let curvaSaida = Animation.timingCurve(0.4, 0, 1, 1, duration: tempoRapido)
    static let toque = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.08)
}

extension NSColor {
    /// Aceita #RRGGBB ou #RRGGBBAA.
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        if s.count == 8 {
            self.init(srgbRed: CGFloat((value >> 24) & 0xFF) / 255, green: CGFloat((value >> 16) & 0xFF) / 255,
                      blue: CGFloat((value >> 8) & 0xFF) / 255, alpha: CGFloat(value & 0xFF) / 255)
        } else {
            self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                      blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

/// Paleta de cores das listas (cor de categoria) e emojis sugeridos.
enum Palette {
    static let lists = ["#E8553F", "#E08A1E", "#C9A21B", "#3FA35B", "#1FA6A0", "#3B82E0", "#6E5CE6", "#C255C9", "#D9467A", "#7A7468"]
    static let emojis = ["🎨", "💼", "🏠", "📚", "💪", "🎬", "🛒", "✈️", "💡", "🧠", "📈", "🧾",
                         "🎵", "❤️", "⭐️", "🔥", "🧑‍💻", "📷", "🗂️", "🌱", "🍽️", "🎯", "📞", "🚀"]
}

// MARK: Tipografia

/// Fontes embutidas: Bricolage Grotesque (títulos) e Geist (interface).
enum DSFonts {
    @MainActor private static var registered = false

    @MainActor
    static func register() {
        guard !registered else { return }
        registered = true
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in files where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private nonisolated(unsafe) static var cache: [String: NSFont] = [:]

    /// Fonte variável com o eixo de peso ajustado; cai na fonte do sistema se a família não existir.
    static func font(_ family: String, size: CGFloat, weight: CGFloat, fallback: NSFont.Weight) -> Font {
        let key = "\(family)-\(size)-\(weight)"
        if let cached = cache[key] { return Font(cached) }
        let wght = 0x7767_6874 // 'wght'
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .variation: [NSNumber(value: wght): NSNumber(value: Double(weight))],
        ])
        let font: NSFont
        if let custom = NSFont(descriptor: descriptor, size: size), custom.familyName == family {
            font = custom
        } else {
            font = .systemFont(ofSize: size, weight: fallback)
        }
        cache[key] = font
        return Font(font)
    }
}

/// A escala de oito degraus.
enum Txt {
    case xs, sm, md, lg, xl, titulo, display2, display

    var size: CGFloat {
        switch self {
        case .xs: 11
        case .sm: 13
        case .md: 15
        case .lg: 17
        case .xl: 19
        case .titulo: 24
        case .display2: 34
        case .display: 44
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .xs: 4
        case .sm, .md: 5
        case .lg: 6
        case .xl, .titulo: 4
        case .display2, .display: 0
        }
    }
}

enum Peso {
    case regular, medium, semibold, bold

    var wght: CGFloat {
        switch self {
        case .regular: 400
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        }
    }

    var system: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

extension View {
    /// Texto de interface (Geist) num degrau da escala.
    func txt(_ step: Txt, _ peso: Peso = .regular) -> some View {
        font(DSFonts.font("Geist", size: step.size, weight: peso.wght, fallback: peso.system))
    }

    /// Título: display (Bricolage), caixa baixa, tracking apertado.
    func display(_ step: Txt = .display) -> some View {
        font(DSFonts.font("Bricolage Grotesque", size: step.size, weight: 700, fallback: .bold))
            .tracking(-0.035 * step.size)
    }

    /// Sobrancelha: contexto acima do título.
    func rotulo() -> some View {
        txt(.xs, .medium)
            .textCase(.uppercase)
            .tracking(0.08 * 11)
            .foregroundStyle(DS.texto3)
    }

    /// Cartão: superfície, borda e raio de cartão.
    func cartao(padding: CGFloat? = DS.e5) -> some View {
        self.padding(padding ?? 0)
            .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
    }

    /// Cartão plano: sem borda, um degrau acima do fundo.
    func cartaoPlano(padding: CGFloat = DS.e5) -> some View {
        self.padding(padding)
            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
    }

    /// Sombra "alta": o que flutua (folha, menu, barra).
    func sombraAlta() -> some View {
        shadow(color: .black.opacity(0.05), radius: 2, y: 2)
            .shadow(color: .black.opacity(0.14), radius: 16, y: 12)
    }

    func sombra() -> some View {
        shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}
