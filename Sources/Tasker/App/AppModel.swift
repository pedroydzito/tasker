import Observation
import SwiftUI

enum SidebarItem: Hashable {
    case today, tomorrow, upcoming, calendar, completed, all, settings
    case despejo, notas
    case list(String)
    case tag(String)
}

@MainActor @Observable
final class Navigation {
    var selection: SidebarItem? = .today
    /// Tarefa aberta no painel de detalhes da janela principal.
    var selectedTaskID: String?
    /// Tarefas-mãe com as subtarefas abertas embaixo (vale para o menu e para a janela).
    var subtarefasAbertas: Set<String> = []
    /// Nota aberta na tela de Notas.
    var notaAberta: AlvoNota?
}

/// Uma nota solta (pelo id) ou a nota de um dia (existindo ou não).
enum AlvoNota: Hashable {
    case nota(String)
    case dia(Date)
}

/// Objetos compartilhados entre a barra de menu, a janela principal e o atalho global.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let auth: GoogleAuth
    let prefs: Preferences
    let store: TaskStore
    let caderno: Caderno
    let nav = Navigation()
    let updater = Updater()

    private init() {
        auth = GoogleAuth()
        prefs = Preferences()
        store = TaskStore(auth: auth, api: GoogleAPI(auth: auth), prefs: prefs)
        caderno = Caderno(store: store)
    }
}
