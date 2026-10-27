import AppKit
import SwiftUI

private final class KeyPanel: NSPanel {
    var aoCancelar: (() -> Void)?
    override var canBecomeKey: Bool { true }
    /// ESC fecha o painel, de qualquer lugar dentro dele.
    override func cancelOperation(_ sender: Any?) { aoCancelar?() }
}

/// Janela flutuante de "adicionar tarefa" aberta pelo atalho global.
@MainActor
final class QuickAddPanelController {
    private let store: TaskStore
    private let caderno: Caderno
    private var panel: KeyPanel?
    private var resignObserver: NSObjectProtocol?

    init(store: TaskStore, caderno: Caderno) {
        self.store = store
        self.caderno = caderno
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        guard store.hasAccount else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let root = QuickAddPanelView { [weak self] in self?.close() }
            .environment(store)
            .environment(caderno)
        let hosting = NSHostingView(rootView: root)
        panel.contentView = hosting

        if let screen = NSScreen.main {
            // Altura com folga para o dropdown de listas; a área vazia é transparente.
            // Altura com folga para o calendário e o dropdown de listas; a área vazia é
            // transparente e os cliques nela passam para o que está atrás.
            let size = NSSize(width: 580, height: 640)
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - frame.height * 0.22 - size.height + 380,
                                  width: size.width, height: size.height), display: true)
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // Já pronto para digitar: o campo recebe o foco assim que a janela vira principal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            panel.makeKey()
            if let campo = Self.primeiroCampo(em: hosting) { panel.makeFirstResponder(campo) }
        }
    }

    func close() {
        panel?.orderOut(nil)
    }

    private static func primeiroCampo(em view: NSView) -> NSView? {
        if view is NSTextField || view is NSTextView { return view }
        for sub in view.subviews {
            if let achado = primeiroCampo(em: sub) { return achado }
        }
        return nil
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.aoCancelar = { [weak self] in self?.close() }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        return panel
    }
}

struct QuickAddPanelView: View {
    @Environment(TaskStore.self) private var store
    @AppStorage("atalho.modoDespejo", store: Pastas.defaults) private var modoDespejo = false
    let onClose: () -> Void

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: DS.e2) {
                Segmentado(selecao: $modoDespejo, opcoes: [(false, "Tarefa"), (true, "Despejo")])
                    .padding(.leading, DS.e2)
                    .padding(.top, DS.e1)
                Group {
                    if modoDespejo {
                        CampoDespejo(style: .large, onEscape: onClose)
                    } else {
                        QuickAddField(defaultDue: store.today, style: .large, onAdded: onClose, onEscape: onClose)
                    }
                }
                .id(modoDespejo)
            }
            .padding(DS.e2)
            .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
            .sombraAlta()
            .padding(DS.e5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(DS.acento)
        .onExitCommand(perform: onClose)
    }
}
