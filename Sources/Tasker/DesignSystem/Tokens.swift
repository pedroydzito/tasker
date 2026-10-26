import AppKit
import CoreText
import SwiftUI

// Tokens do design system (ver design-system.md do appdocs).
// Regra 1: nenhum hexadecimal, duração ou raio escrito à mão fora deste arquivo.

// MARK: Cor

enum DS {
    // Superfícies e texto — fundo branco-gelo, cartões brancos, divisórias cinza-claras.
    static let fundo = cor("#F7F7F7", "#151517")
    static let superficie = cor("#FFFFFF", "#1F1F22")
    static let superficie2 = cor("#F1F1F3", "#29292D")
    static let superficie3 = cor("#E4E4E8", "#333338")
    static let borda = cor("#ECECEF", "#2A2A2F")
    static let bordaForte = cor("#DADADF", "#3A3A40")
    static let texto = cor("#18181B", "#F4F4F5")
    static let texto2 = cor("#52525B", "#B4B4BB")
    static let texto3 = cor("#7C7C86", "#8E8E97")

    // Acento: identidade, não semântica.
    static let acento = Color(nsColor: NSColor(hex: "#0097FF"))
    static let acentoSolido = acento
    static let acentoSolidoTexto = Color.white
    static let acentoTexto = cor("#0071C2", "#4DB6FF")
    static let anelFoco = cor("#0097FF66", "#0097FF80")

    // Papéis. Como o acento não é vermelho, o perigo tem o vermelho próprio.
    static let perigo = cor("#E5484D", "#F2555A")
    static let perigoTexto = cor("#CE2C31", "#FF7A7E")
    static let perigoTenue = cor("#E5484D1a", "#F2555A29")
    static let sucesso = cor("#0F7A52", "#4ADE9B")
    static let sucessoTenue = cor("#0F7A521a", "#4ADE9B24")
    static let aviso = cor("#9A5B12", "#E0A458")
    static let avisoTenue = cor("#9A5B121a", "#E0A45824")
    static let link = cor("#0071C2", "#4DB6FF")

    // Véu de hover: preto no claro, branco no escuro — a superfície se aproxima do ponteiro.
    static let veuHover = cor("#0000000c", "#ffffff12")
    static let veuAtivo = cor("#00000016", "#ffffff1c")
    static let veuModal = Color.black.opacity(0.32)

    /// Quanto da cor de categoria entra no fundo de um chip tingido.
    static let chipTinta = 0.12

    static func cor(_ claro: String, _ escuro: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: escuro) : NSColor(hex: claro)
        })
    }

    // MARK: Raio

    static let raioP: CGFloat = 6       // ladrilho de ícone
    static let raioM: CGFloat = 10      // botão, campo, linha dentro de cartão
    static let raioG: CGFloat = 12      // painel interno
    static let raioCartao: CGFloat = 14 // cartão, folha, menu (= raioM + respiro de 4)

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
    /// Biblioteca de ícones para as listas (SF Symbols — nada de emoji).
    /// Biblioteca de ícones (contorno) com palavras de busca em português.
    static let icones: [(nome: String, busca: String)] = [
        ("person", "pessoa cliente perfil"), ("person.2", "pessoas dupla equipe"), ("person.3", "grupo time equipe"),
        ("briefcase", "trabalho maleta emprego"), ("building.2", "empresa prédio escritório"), ("house", "casa lar"),
        ("storefront", "loja comércio"), ("cart", "compras mercado carrinho"), ("bag", "sacola compras"),
        ("paintbrush.pointed", "design pincel arte"), ("paintpalette", "arte paleta cores"), ("pencil.and.ruler", "projeto régua"),
        ("pencil", "lápis escrever editar"), ("scissors", "tesoura corte"), ("camera", "câmera foto"), ("photo", "imagem foto"),
        ("film", "filme cinema vídeo"), ("video", "vídeo gravação"), ("music.note", "música som"), ("headphones", "fone podcast"),
        ("mic", "microfone áudio"), ("gamecontroller", "jogo game"), ("tv", "tv série"), ("book", "livro leitura"),
        ("books.vertical", "livros estudo biblioteca"), ("graduationcap", "estudo faculdade curso"), ("lightbulb", "ideia lâmpada"),
        ("brain", "mente cérebro"), ("heart", "coração amor saúde"), ("star", "estrela favorito"), ("flame", "fogo urgente"),
        ("bolt", "raio energia rápido"), ("leaf", "folha natureza"), ("tree", "árvore natureza"), ("sun.max", "sol dia"),
        ("moon", "lua noite"), ("cloud", "nuvem"), ("figure.run", "corrida exercício"), ("dumbbell", "academia treino"),
        ("bicycle", "bicicleta"), ("fork.knife", "comida restaurante"), ("cup.and.saucer", "café"), ("wineglass", "vinho festa"),
        ("airplane", "viagem avião"), ("car", "carro"), ("bus", "ônibus transporte"), ("map", "mapa"),
        ("mappin.and.ellipse", "lugar local"), ("globe.americas", "mundo internet"), ("creditcard", "cartão pagamento"),
        ("banknote", "dinheiro nota"), ("dollarsign.circle", "dinheiro finanças"), ("chart.bar", "gráfico métricas"),
        ("chart.line.uptrend.xyaxis", "crescimento vendas"), ("chart.pie", "gráfico pizza"), ("doc.text", "documento texto"),
        ("folder", "pasta arquivos"), ("tray", "caixa entrada"), ("archivebox", "arquivo caixa"), ("paperclip", "anexo clipe"),
        ("link", "link"), ("laptopcomputer", "notebook computador"), ("desktopcomputer", "computador"), ("iphone", "celular telefone"),
        ("chevron.left.forwardslash.chevron.right", "código programação dev"), ("terminal", "terminal dev"),
        ("megaphone", "marketing anúncio"), ("bubble.left", "conversa mensagem"), ("phone", "telefone ligação"),
        ("envelope", "email carta"), ("paperplane", "enviar"), ("calendar", "calendário agenda"), ("clock", "relógio hora"),
        ("alarm", "alarme lembrete"), ("flag", "bandeira meta"), ("bookmark", "marcador"), ("tag", "etiqueta"),
        ("target", "alvo meta objetivo"), ("checklist", "lista tarefas"), ("list.bullet", "lista"), ("square.grid.2x2", "grade apps"),
        ("sparkles", "brilho mágica"), ("wand.and.stars", "mágica"), ("gift", "presente aniversário"), ("pawprint", "pet animal"),
        ("stethoscope", "médico saúde"), ("cross.case", "saúde remédio"), ("hammer", "ferramenta obra"),
        ("wrench.and.screwdriver", "manutenção conserto"), ("gearshape", "configuração"), ("lock", "senha segurança"),
    ]

    static var simbolos: [String] { icones.map(\.nome) }
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
        case .sm: 12.5
        case .md: 13.5
        case .lg: 15
        case .xl: 17
        case .titulo: 20
        case .display2: 24
        case .display: 28
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

    /// Título: display (Bricolage), tracking apertado.
    func display(_ step: Txt = .display) -> some View {
        font(DSFonts.font("Bricolage Grotesque", size: step.size, weight: 700, fallback: .bold))
            .tracking(-0.025 * step.size)
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
