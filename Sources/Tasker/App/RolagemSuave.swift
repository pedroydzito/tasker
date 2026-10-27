import AppKit
import QuartzCore

/// Rolagem suave para a roda do mouse. O trackpad já é suave e passa direto;
/// a roda (que pula de linha em linha) vira um deslizamento animado até o alvo.
@MainActor
final class RolagemSuave: NSObject {
    static let shared = RolagemSuave()

    private var monitor: Any?
    /// Sincronizado com a taxa de atualização da tela em que o ScrollView está (60, 75, 120 Hz...).
    private var link: CADisplayLink?
    private var ultimoQuadro: CFTimeInterval = 0
    private weak var alvoScroll: NSScrollView?
    private var destinoY: CGFloat = 0

    /// Pixels por "dente" da roda.
    private let passo: CGFloat = 46
    /// Velocidade do deslize (independe da taxa da tela: conta o tempo real entre quadros).
    private let rapidez: Double = 16

    func instalar() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] evento in
            guard let self else { return evento }
            return self.tratar(evento) ? nil : evento
        }
    }

    /// true = o evento foi consumido aqui.
    private func tratar(_ evento: NSEvent) -> Bool {
        guard !evento.hasPreciseScrollingDeltas, evento.phase.isEmpty, evento.momentumPhase.isEmpty,
              abs(evento.scrollingDeltaY) > abs(evento.scrollingDeltaX),
              let janela = evento.window, let raiz = janela.contentView,
              let scroll = rolavelVertical(em: raiz.hitTest(raiz.convert(evento.locationInWindow, from: nil)))
        else { return false }

        let clip = scroll.contentView
        let limites = faixa(scroll)
        if scroll !== alvoScroll || link == nil {
            alvoScroll = scroll
            destinoY = clip.bounds.origin.y
        }
        // Roda para cima (delta > 0) mostra o que está acima.
        let sentido: CGFloat = clip.isFlipped ? -1 : 1
        destinoY += evento.scrollingDeltaY * passo * sentido
        destinoY = min(max(destinoY, limites.lowerBound), limites.upperBound)
        iniciarAnimacao(em: scroll)
        return true
    }

    private func faixa(_ scroll: NSScrollView) -> ClosedRange<CGFloat> {
        let clip = scroll.contentView
        let altura = scroll.documentView?.frame.height ?? 0
        let minimo = -scroll.contentInsets.top
        let maximo = max(minimo, altura - clip.bounds.height + scroll.contentInsets.bottom)
        return minimo...maximo
    }

    private func iniciarAnimacao(em scroll: NSScrollView) {
        guard link == nil else { return }
        let novo = scroll.displayLink(target: self, selector: #selector(quadro(_:)))
        novo.add(to: .main, forMode: .common)
        link = novo
        ultimoQuadro = 0
    }

    @objc private func quadro(_ link: CADisplayLink) {
        guard let scroll = alvoScroll else { parar(); return }
        // Tempo real desde o último quadro, limitado para não dar saltos após uma pausa.
        let dt = ultimoQuadro == 0 ? link.targetTimestamp - link.timestamp : min(link.timestamp - ultimoQuadro, 1.0 / 20)
        ultimoQuadro = link.timestamp
        let fator = CGFloat(1 - exp(-rapidez * max(dt, 0.001)))
        let clip = scroll.contentView
        let atual = clip.bounds.origin.y
        let falta = destinoY - atual
        let novo = abs(falta) < 0.5 ? destinoY : atual + falta * fator
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: novo))
        scroll.reflectScrolledClipView(clip)
        if novo == destinoY { parar() }
    }

    private func parar() {
        link?.invalidate()
        link = nil
    }

    /// O ScrollView mais próximo do cursor que de fato rola na vertical.
    private func rolavelVertical(em view: NSView?) -> NSScrollView? {
        var atual = view
        while let v = atual {
            if let scroll = v as? NSScrollView, let doc = scroll.documentView,
               doc.frame.height > scroll.contentView.bounds.height + 1 {
                return scroll
            }
            atual = v.superview
        }
        return nil
    }
}
