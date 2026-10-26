import AppKit
import SwiftUI

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Janela flutuante de "adicionar tarefa" aberta pelo atalho global.
@MainActor
final class QuickAddPanelController {
    private let store: TaskStore
    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?

    init(store: TaskStore) {
        self.store = store
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        guard store.auth.isSignedIn else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let root = QuickAddPanelView { [weak self] in self?.close() }
            .environment(store)
        panel.contentView = NSHostingView(rootView: root)

        if let screen = NSScreen.main {
            let size = NSSize(width: 580, height: 96)
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - frame.height * 0.28,
                                  width: size.width, height: size.height), display: true)
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
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
        panel.hasShadow = true

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
    let onClose: () -> Void

    var body: some View {
        QuickAddField(defaultDue: store.today, style: .large, onAdded: onClose)
            .padding(DS.e2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
            .tint(DS.acento)
            .onExitCommand(perform: onClose)
    }
}
