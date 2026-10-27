import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private var quickAdd: QuickAddPanelController?
    private var monitorBotaoDireito: Any?

    static let abrirJanelaPrincipal = Notification.Name("tasker.abrirJanelaPrincipal")

    func applicationDidFinishLaunching(_ notification: Notification) {
        DSFonts.register()
        RolagemSuave.shared.instalar()
        FocoFora.instalar()
        NSApp.applicationIconImage = AppIcon.make()
        let model = AppModel.shared
        NSApp.appearance = model.prefs.appearance.nsAppearance
        model.store.start()
        model.updater.start()

        // Botão direito no ícone da barra: menu com "Abrir em janela expandida" e "Fechar".
        monitorBotaoDireito = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] evento in
            guard let janela = evento.window,
                  String(describing: type(of: janela)).contains("StatusBar"),
                  let view = janela.contentView else { return evento }
            self?.mostrarMenuDeContexto(em: view)
            return nil
        }

        let panel = QuickAddPanelController(store: model.store, caderno: model.caderno)
        quickAdd = panel
        // ⌥Espaço: adicionar tarefa de qualquer lugar.
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) {
            MainActor.assumeIsolated { panel.toggle() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // O caderno grava com atraso enquanto se digita; ao sair, grava na hora.
        AppModel.shared.caderno.salvarAgora(sincrono: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func mostrarMenuDeContexto(em view: NSView) {
        let menu = NSMenu()
        let abrir = NSMenuItem(title: "Abrir em janela expandida", action: #selector(abrirJanela), keyEquivalent: "")
        abrir.target = self
        menu.addItem(abrir)
        menu.addItem(.separator())
        let fechar = NSMenuItem(title: "Fechar o Tasker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(fechar)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 6), in: view)
    }

    @objc private func abrirJanela() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NotificationCenter.default.post(name: Self.abrirJanelaPrincipal, object: nil)
    }
}
