import Observation
import SwiftUI

enum SidebarItem: Hashable {
    case today, tomorrow, upcoming, calendar, completed, all, settings
    case list(String)
    case tag(String)
}

@MainActor @Observable
final class Navigation {
    var selection: SidebarItem? = .today
    /// Tarefa aberta no painel de detalhes da janela principal.
    var selectedTaskID: String?
}

/// Objetos compartilhados entre a barra de menu, a janela principal e o atalho global.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let auth: GoogleAuth
    let prefs: Preferences
    let store: TaskStore
    let nav = Navigation()

    private init() {
        auth = GoogleAuth()
        prefs = Preferences()
        store = TaskStore(auth: auth, api: GoogleAPI(auth: auth), prefs: prefs)
    }
}
