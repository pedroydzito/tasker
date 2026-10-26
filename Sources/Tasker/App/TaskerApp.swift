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
        TaskerApp.main()
    }
}

struct TaskerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environment(model.store)
                .environment(model.auth)
                .environment(model.nav)
                .environment(model.updater)
        } label: {
            MenuBarLabel(store: model.store)
        }
        .menuBarExtraStyle(.window)

        Window("Tasker", id: WindowID.main) {
            MainWindow()
                .environment(model.store)
                .environment(model.auth)
                .environment(model.nav)
                .environment(model.updater)
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(model.store.hasAccount ? .suppressed : .presented)
    }
}
