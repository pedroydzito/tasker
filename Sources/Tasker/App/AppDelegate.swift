import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private var quickAdd: QuickAddPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIcon.make()
        let model = AppModel.shared
        model.store.start()
        model.updater.start()

        let panel = QuickAddPanelController(store: model.store)
        quickAdd = panel
        // ⌥Espaço: adicionar tarefa de qualquer lugar.
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) {
            MainActor.assumeIsolated { panel.toggle() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
