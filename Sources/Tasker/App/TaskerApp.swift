import SwiftUI

enum WindowID {
    static let main = "main"
}

@main
struct TaskerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environment(model.store)
                .environment(model.auth)
                .environment(model.nav)
        } label: {
            MenuBarLabel(store: model.store)
        }
        .menuBarExtraStyle(.window)

        Window("Tasker", id: WindowID.main) {
            MainWindow()
                .environment(model.store)
                .environment(model.auth)
                .environment(model.nav)
        }
        .defaultSize(width: 1040, height: 700)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultLaunchBehavior(model.auth.isSignedIn ? .suppressed : .presented)
    }
}
