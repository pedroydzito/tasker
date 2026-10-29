import SwiftUI

enum WindowID {
    static let main = "main"
}

/// Ponto de entrada: `--export-icon <png>` só gera o ícone (usado no build); senão abre o app.
@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--export-icon"), index + 1 < args.count {
            let ok = MainActor.assumeIsolated {
                _ = NSApplication.shared
                return AppIcon.export(to: args[index + 1])
            }
            exit(ok ? 0 : 1)
        }
        if args.contains("--repro-exclusao-nota") {
            MainActor.assumeIsolated { Capturas.reproduzirExclusaoAntiga() }
        }
        if args.contains("--autoteste") {
            MainActor.assumeIsolated { Autoteste.iniciar() }
        }
        if let index = args.firstIndex(of: "--capturas"), index + 1 < args.count {
            MainActor.assumeIsolated { Capturas.iniciar(pasta: args[index + 1]) }
        }
        TaskerApp.main()
    }
}

struct TaskerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        // A interface é a mesma da web, embutida no app (funciona sem internet).
        // Sem o build web no pacote (build antigo), segue a interface nativa.
        MenuBarExtra {
            if WebPonte.disponivel {
                TelaWeb(rota: "menu")
                    .frame(width: MenuBarPopover.largura, height: MenuBarPopover.altura)
                    .onAppear { WebPonte.shared.menuAbriu() }
            } else {
                MenuBarPopover()
                    .environment(model.store)
                    .environment(model.auth)
                    .environment(model.nav)
                    .environment(model.updater)
                    .environment(model.caderno)
            }
        } label: {
            if WebPonte.disponivel {
                MenuBarLabelWeb()
            } else {
                MenuBarLabel(store: model.store)
            }
        }
        .menuBarExtraStyle(.window)

        Window("Tasker", id: WindowID.main) {
            if WebPonte.disponivel {
                TelaWeb(rota: "hoje", ehJanela: true)
                    .frame(minWidth: 900, minHeight: 580)
                    .ignoresSafeArea()
                    // Faixa de cima (onde ficam os botões da janela) arrasta a janela.
                    .overlay(alignment: .top) {
                        Color.clear.frame(height: 30).contentShape(Rectangle()).gesture(WindowDragGesture())
                            .ignoresSafeArea()
                    }
                    .onAppear { NSApp.setActivationPolicy(.regular) }
                    .onDisappear { NSApp.setActivationPolicy(.accessory) }
            } else {
                MainWindow()
                    .environment(model.store)
                    .environment(model.auth)
                    .environment(model.nav)
                    .environment(model.updater)
                    .environment(model.caderno)
            }
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(model.store.hasAccount ? .suppressed : .presented)
    }
}
