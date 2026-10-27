import AppKit
import QuartzCore

/// Rolagem suave para a roda do mouse (o trackpad já é suave e passa direto).
///
/// Cada dente da roda move o alvo; a posição segue uma curva de desaceleração com
/// duração fixa, calculada pelo horário do próximo quadro da tela. Assim a velocidade
/// não depende da taxa do monitor nem de quadros perdidos quando a tela tem muitos itens.
@MainActor
final class RolagemSuave: NSObject {
    static let shared = RolagemSuave()

    private var monitor: Any?
    /// Enquanto desliza, o hover das linhas não muda (evita redesenhar cada linha que passa sob o cursor).
    private(set) var rolando = false
    private var link: CADisplayLink?
    private weak var alvo: NSScrollView?

    private var origemY: CGFloat = 0
    private var destinoY: CGFloat = 0
    private var inicio: CFTimeInterval = 0

    /// Pixels por dente da roda.
    private let passo: CGFloat = 52
    /// Duração do deslize após cada dente.
    private let duracao: CFTimeInterval = 0.32

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
              evento.scrollingDeltaY != 0, abs(evento.scrollingDeltaY) >= abs(evento.scrollingDeltaX),
              let raiz = evento.window?.contentView,
              let scroll = rolavelVertical(em: raiz.hitTest(raiz.convert(evento.locationInWindow, from: nil)))
        else { return false }

        let clip = scroll.contentView
        let agora = CACurrentMediaTime()
        if scroll !== alvo || link == nil {
            alvo = scroll
            destinoY = clip.bounds.origin.y
        }
        // Recomeça a curva de onde está agora, sem tranco.
        origemY = clip.bounds.origin.y
        inicio = agora

        let sentido: CGFloat = clip.isFlipped ? -1 : 1
        let limites = faixa(scroll)
        destinoY = min(max(destinoY + evento.scrollingDeltaY * passo * sentido, limites.lowerBound), limites.upperBound)
        guard destinoY != origemY else { return true }

        if link == nil {
            let novo = scroll.displayLink(target: self, selector: #selector(quadro(_:)))
            novo.add(to: .main, forMode: .common)
            link = novo
            rolando = true
        }
        return true
    }

    @objc private func quadro(_ link: CADisplayLink) {
        guard let scroll = alvo else { parar(); return }
        // Posição para o instante em que este quadro aparece na tela.
        let t = min(max((link.targetTimestamp - inicio) / duracao, 0), 1)
        let curva = 1 - pow(1 - t, 3) // desacelera no fim
        let y = (origemY + (destinoY - origemY) * CGFloat(curva)).rounded(.toNearestOrAwayFromZero)
        let clip = scroll.contentView
        if clip.bounds.origin.y != y {
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: y))
            scroll.reflectScrolledClipView(clip)
        }
        if t >= 1 { parar() }
    }

    private func parar() {
        link?.invalidate()
        link = nil
        rolando = false
    }

    private func faixa(_ scroll: NSScrollView) -> ClosedRange<CGFloat> {
        let clip = scroll.contentView
        let altura = scroll.documentView?.frame.height ?? 0
        let minimo = -scroll.contentInsets.top
        return minimo...max(minimo, altura - clip.bounds.height + scroll.contentInsets.bottom)
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
