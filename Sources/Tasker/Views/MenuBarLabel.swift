import AppKit
import SwiftUI

/// Ícone da barra de menu: um ícone de tarefa com o número de pendências de hoje
/// num selo redondo no canto inferior. Desenhado como imagem "template" para
/// se adaptar à barra clara ou escura.
struct MenuBarLabel: View {
    let store: TaskStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = store.hasAccount ? store.badgeCount : 0
        let show = store.prefs.showCountInMenuBar && count > 0
        Group {
            if let ativo = store.cronometroAtivo {
                // Cronômetro rodando: o número de tarefas dá lugar ao tempo correndo.
                // Uma imagem só (ícone + tempo), de largura fixa: o item da barra não muda de
                // tamanho a cada segundo (mudar o conteúdo do label com o menu aberto travava a janela).
                Image(nsImage: Self.cronometro(Duracao.relogio(store.tempo(de: ativo, agora: store.tique))))
            } else {
                Image(nsImage: Self.icon(count: show ? count : nil, style: store.prefs.menuBarStyle))
            }
        }
            .onReceive(NotificationCenter.default.publisher(for: AppDelegate.abrirJanelaPrincipal)) { _ in
                openWindow(id: WindowID.main)
            }
    }

    /// Ícone da barra com o cronômetro: "◷ 12:34" desenhado numa imagem template.
    @MainActor static func cronometro(_ texto: String) -> NSImage {
        let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: "Cronômetro")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold)) ?? NSImage()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        // Largura do maior texto do mesmo formato: não varia de um segundo para o outro.
        let molde = texto.count > 5 ? "0:00:00" : "00:00"
        let largura = (molde as NSString).size(withAttributes: attrs).width
        let altura = max(symbol.size.height, font.boundingRectForFont.height)
        let size = NSSize(width: (symbol.size.width + 4 + largura).rounded(.up), height: max(18, altura.rounded(.up)))
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: NSRect(x: 0, y: (rect.height - symbol.size.height) / 2,
                                   width: symbol.size.width, height: symbol.size.height))
            let t = (texto as NSString).size(withAttributes: attrs)
            (texto as NSString).draw(at: NSPoint(x: symbol.size.width + 4, y: (rect.height - t.height) / 2),
                                     withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }

    @MainActor private static var iconCache: [String: NSImage] = [:]

    /// O label é redesenhado a cada mudança do store; a imagem só é refeita quando o número ou o estilo mudam.
    @MainActor static func icon(count: Int?, style: MenuBarStyle) -> NSImage {
        let chave = "\(count.map(String.init) ?? "-")|\(style)"
        if let pronta = iconCache[chave] { return pronta }
        let nova = desenharIcone(count: count, style: style)
        if iconCache.count > 40 { iconCache.removeAll() }
        iconCache[chave] = nova
        return nova
    }

    private static func desenharIcone(count: Int?, style: MenuBarStyle) -> NSImage {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let symbol = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Tarefas")?
            .withSymbolConfiguration(symbolConfig) ?? NSImage()
        let symbolSize = symbol.size

        guard let count else {
            symbol.isTemplate = true
            return symbol
        }

        let text = count > 99 ? "99+" : "\(count)"

        if style == .iconAndNumber {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let size = NSSize(width: symbolSize.width + 3 + textSize.width, height: max(symbolSize.height, textSize.height))
            let image = NSImage(size: size, flipped: false) { rect in
                symbol.draw(in: NSRect(x: 0, y: (rect.height - symbolSize.height) / 2,
                                       width: symbolSize.width, height: symbolSize.height))
                (text as NSString).draw(at: NSPoint(x: symbolSize.width + 3, y: (rect.height - textSize.height) / 2),
                                        withAttributes: attrs)
                return true
            }
            image.isTemplate = true
            return image
        }

        // Selo: cápsula preenchida no canto inferior direito, com o número "vazado".
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let badgeHeight: CGFloat = 11
        let badgeWidth = max(badgeHeight, textSize.width + 5)
        let gap: CGFloat = 1.5
        let size = NSSize(width: max(symbolSize.width, symbolSize.width * 0.55 + badgeWidth),
                          height: max(18, symbolSize.height + 2))

        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: NSRect(x: 0, y: rect.height - symbolSize.height,
                                   width: symbolSize.width, height: symbolSize.height))
            guard let ctx = NSGraphicsContext.current else { return true }
            let badge = NSRect(x: rect.maxX - badgeWidth, y: 0, width: badgeWidth, height: badgeHeight)

            // Abre um respiro em volta do selo para separá-lo do ícone.
            ctx.compositingOperation = .clear
            let ring = badge.insetBy(dx: -gap, dy: -gap)
            NSBezierPath(roundedRect: ring, xRadius: ring.height / 2, yRadius: ring.height / 2).fill()

            ctx.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(roundedRect: badge, xRadius: badgeHeight / 2, yRadius: badgeHeight / 2).fill()

            ctx.compositingOperation = .destinationOut
            (text as NSString).draw(at: NSPoint(x: badge.midX - textSize.width / 2,
                                                y: badge.midY - textSize.height / 2 + 0.3),
                                    withAttributes: attrs)
            ctx.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        return image
    }
}
