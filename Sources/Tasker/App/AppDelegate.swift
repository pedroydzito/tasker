import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private var quickAdd: QuickAddPanelController?
    private var monitorBotaoDireito: Any?
    /// WebView escondida desde o início: mantém o número da barra e a sincronização em dia.
    private var fundo: AnyObject?

    static func abrirJanelaWeb() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NotificationCenter.default.post(name: abrirJanelaPrincipal, object: nil)
    }

    static let abrirJanelaPrincipal = Notification.Name("tasker.abrirJanelaPrincipal")

    func applicationDidFinishLaunching(_ notification: Notification) {
        DSFonts.register()
        RolagemSuave.shared.instalar()
        FocoFora.instalar()
        NSApp.applicationIconImage = AppIcon.make()
        let model = AppModel.shared
        NSApp.appearance = model.prefs.appearance.nsAppearance
        // Com a interface web, Google, Supabase e o modo offline são cuidados por ela.
        if !WebPonte.disponivel || CommandLine.arguments.contains("--autoteste") || Pastas.isolado != nil { model.store.start() }
        LembreteDespejo.agendar(quantidade: model.caderno.despejo.count, prefs: model.prefs)
        model.updater.start()

        // Botão direito no ícone da barra: menu com "Abrir em janela expandida" e "Fechar".
        monitorBotaoDireito = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] evento in
            guard let janela = evento.window,
                  String(describing: type(of: janela)).contains("StatusBar"),
                  let view = janela.contentView else { return evento }
            self?.mostrarMenuDeContexto(em: view)
            return nil
        }

        if WebPonte.disponivel && Pastas.isolado == nil {
            // ⌥Espaço: abre a janela no Hoje, já no campo de nova tarefa.
            hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) {
                MainActor.assumeIsolated {
                    WebPonte.shared.abrirJanela(rota: "#/hoje")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        WebPonte.shared.janela?.evaluateJavaScript("window.taskerNovaTarefa && taskerNovaTarefa()")
                    }
                }
            }
            fundo = WebPonte.shared.novaWebView(rota: "menu")
            WebPonte.shared.vigiarAtualizacao()
        } else {
            let panel = QuickAddPanelController(store: model.store, caderno: model.caderno)
            quickAdd = panel
            // ⌥Espaço: adicionar tarefa de qualquer lugar.
            hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) {
                MainActor.assumeIsolated { panel.toggle() }
            }
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
        Self.abrirJanelaWeb()
    }
}
