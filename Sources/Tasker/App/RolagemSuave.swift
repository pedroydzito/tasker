import AppKit

/// Rolagem suave para a roda do mouse. O trackpad já é suave e passa direto;
/// a roda (que pula de linha em linha) vira um deslizamento animado até o alvo.
@MainActor
final class RolagemSuave {
    static let shared = RolagemSuave()

    private var monitor: Any?
    private var timer: Timer?
    private weak var alvoScroll: NSScrollView?
    private var destinoY: CGFloat = 0

    /// Pixels por "dente" da roda.
    private let passo: CGFloat = 46
    /// Fração da distância percorrida a cada quadro (maior = mais rápido).
    private let suavidade: CGFloat = 0.2

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
        if scroll !== alvoScroll || timer == nil {
            alvoScroll = scroll
            destinoY = clip.bounds.origin.y
        }
        // Roda para cima (delta > 0) mostra o que está acima.
        let sentido: CGFloat = clip.isFlipped ? -1 : 1
        destinoY += evento.scrollingDeltaY * passo * sentido
        destinoY = min(max(destinoY, limites.lowerBound), limites.upperBound)
        iniciarAnimacao()
        return true
    }

    private func faixa(_ scroll: NSScrollView) -> ClosedRange<CGFloat> {
        let clip = scroll.contentView
        let altura = scroll.documentView?.frame.height ?? 0
        let minimo = -scroll.contentInsets.top
        let maximo = max(minimo, altura - clip.bounds.height + scroll.contentInsets.bottom)
        return minimo...maximo
    }

    private func iniciarAnimacao() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.quadro() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func quadro() {
        guard let scroll = alvoScroll else { parar(); return }
        let clip = scroll.contentView
        let atual = clip.bounds.origin.y
        let falta = destinoY - atual
        let novo = abs(falta) < 0.5 ? destinoY : atual + falta * suavidade
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: novo))
        scroll.reflectScrolledClipView(clip)
        if novo == destinoY { parar() }
    }

    private func parar() {
        timer?.invalidate()
        timer = nil
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
