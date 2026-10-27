import AppKit

/// Clicar fora de um campo de texto encerra a edição (como o ESC), em qualquer janela do app.
/// O SwiftUI no macOS não tira o foco sozinho ao clicar numa área vazia.
@MainActor
enum FocoFora {
    private static var monitor: Any?

    static func instalar() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { evento in
            guard let janela = evento.window,
                  let editor = janela.firstResponder as? NSTextView,
                  let raiz = janela.contentView
            else { return evento }
            let ponto = raiz.superview?.convert(evento.locationInWindow, from: nil) ?? evento.locationInWindow
            var view = raiz.hitTest(ponto)
            while let v = view {
                // Clique dentro de um campo: deixa o AppKit cuidar (mover o cursor, selecionar...).
                if v is NSTextView || v is NSTextField { return evento }
                view = v.superview
            }
            // Depois do clique ser entregue (um botão ainda recebe o clique normalmente).
            DispatchQueue.main.async {
                if janela.firstResponder === editor { janela.makeFirstResponder(nil) }
            }
            return evento
        }
    }
}
