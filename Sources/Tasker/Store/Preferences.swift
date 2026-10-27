import AppKit
import Observation

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case badge, iconAndNumber
    var id: String { rawValue }
    var title: String {
        switch self {
        case .badge: "Ícone com selo"
        case .iconAndNumber: "Ícone + número ao lado"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Escuro"
        }
    }

    /// Para a janela principal (nil = segue o sistema).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Para o popover: a barra de menu fica escura com papel de parede escuro, mas o popover
    /// deve seguir o tema do sistema (ou o escolhido), não a cor da barra.
    var resolved: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system:
            NSAppearance(named: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .darkAqua : .aqua)
        }
    }
}

/// Preferências do usuário, persistidas no UserDefaults e observáveis pela UI.
@MainActor @Observable
final class Preferences {
    @ObservationIgnored private let d = Pastas.defaults

    init() {
        d.register(defaults: [
            "showCount": true,
            "includeOverdue": true,
            "syncInterval": 30.0,
            "menuBarStyle": MenuBarStyle.badge.rawValue,
            "appearance": AppAppearance.system.rawValue,
            "showEventsInMenu": true,
            "showOverdueInMenu": true,
        ])
    }

    var showCountInMenuBar: Bool {
        get { access(keyPath: \.showCountInMenuBar); return d.bool(forKey: "showCount") }
        set { withMutation(keyPath: \.showCountInMenuBar) { d.set(newValue, forKey: "showCount") } }
    }

    /// Se tarefas atrasadas entram no contador da barra de menu.
    var includeOverdueInCount: Bool {
        get { access(keyPath: \.includeOverdueInCount); return d.bool(forKey: "includeOverdue") }
        set { withMutation(keyPath: \.includeOverdueInCount) { d.set(newValue, forKey: "includeOverdue") } }
    }

    var menuBarStyle: MenuBarStyle {
        get {
            access(keyPath: \.menuBarStyle)
            return MenuBarStyle(rawValue: d.string(forKey: "menuBarStyle") ?? "") ?? .badge
        }
        set { withMutation(keyPath: \.menuBarStyle) { d.set(newValue.rawValue, forKey: "menuBarStyle") } }
    }

    /// Intervalo de sincronização em segundos.
    var syncInterval: Double {
        get { access(keyPath: \.syncInterval); return d.double(forKey: "syncInterval") }
        set { withMutation(keyPath: \.syncInterval) { d.set(newValue, forKey: "syncInterval") } }
    }

    var defaultListID: String? {
        get { access(keyPath: \.defaultListID); return d.string(forKey: "defaultListID") }
        set { withMutation(keyPath: \.defaultListID) { d.set(newValue, forKey: "defaultListID") } }
    }

    var listColors: [String: String] {
        get { access(keyPath: \.listColors); return d.dictionary(forKey: "listColors") as? [String: String] ?? [:] }
        set { withMutation(keyPath: \.listColors) { d.set(newValue, forKey: "listColors") } }
    }

    /// Visibilidade escolhida no app; sem entrada, vale a do Google Calendar.
    var calendarVisibility: [String: Bool] {
        get { access(keyPath: \.calendarVisibility); return d.dictionary(forKey: "calendarVisibility") as? [String: Bool] ?? [:] }
        set { withMutation(keyPath: \.calendarVisibility) { d.set(newValue, forKey: "calendarVisibility") } }
    }

    var appearance: AppAppearance {
        get {
            access(keyPath: \.appearance)
            return AppAppearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        }
        set { withMutation(keyPath: \.appearance) { d.set(newValue.rawValue, forKey: "appearance") } }
    }

    /// Ícone (SF Symbol) escolhido por lista ("" = só a inicial).
    var listSymbols: [String: String] {
        get { access(keyPath: \.listSymbols); return d.dictionary(forKey: "listSymbols") as? [String: String] ?? [:] }
        set { withMutation(keyPath: \.listSymbols) { d.set(newValue, forKey: "listSymbols") } }
    }

    /// Usar sem conta: tudo fica só neste Mac.
    /// "Tô sem energia": o Hoje mostra uma coisa por vez, sem atrasadas e sem contagem.
    var energiaBaixa: Bool {
        get { access(keyPath: \.energiaBaixa); return d.bool(forKey: "energiaBaixa") }
        set { withMutation(keyPath: \.energiaBaixa) { d.set(newValue, forKey: "energiaBaixa") } }
    }

    /// Lembrete gentil do despejo, uma vez por dia.
    var lembreteDespejo: Bool {
        get { access(keyPath: \.lembreteDespejo); return d.bool(forKey: "lembreteDespejo") }
        set { withMutation(keyPath: \.lembreteDespejo) { d.set(newValue, forKey: "lembreteDespejo") } }
    }

    /// Hora do lembrete (0–23).
    var horaLembrete: Int {
        get { access(keyPath: \.horaLembrete); return d.object(forKey: "horaLembrete") as? Int ?? 18 }
        set { withMutation(keyPath: \.horaLembrete) { d.set(newValue, forKey: "horaLembrete") } }
    }

    var localMode: Bool {
        get { access(keyPath: \.localMode); return d.bool(forKey: "localMode") }
        set { withMutation(keyPath: \.localMode) { d.set(newValue, forKey: "localMode") } }
    }

    /// Som ao concluir uma tarefa.
    var completionSound: Bool {
        get { access(keyPath: \.completionSound); return d.bool(forKey: "completionSound") }
        set { withMutation(keyPath: \.completionSound) { d.set(newValue, forKey: "completionSound") } }
    }

    /// Mostrar os eventos do dia no menu da barra.
    var showEventsInMenu: Bool {
        get { access(keyPath: \.showEventsInMenu); return d.bool(forKey: "showEventsInMenu") }
        set { withMutation(keyPath: \.showEventsInMenu) { d.set(newValue, forKey: "showEventsInMenu") } }
    }

    /// Mostrar atrasadas no menu da barra.
    var showOverdueInMenu: Bool {
        get { access(keyPath: \.showOverdueInMenu); return d.bool(forKey: "showOverdueInMenu") }
        set { withMutation(keyPath: \.showOverdueInMenu) { d.set(newValue, forKey: "showOverdueInMenu") } }
    }

    /// Ordem das etiquetas escolhida arrastando na barra lateral.
    var tagOrder: [String] {
        get { access(keyPath: \.tagOrder); return d.stringArray(forKey: "tagOrder") ?? [] }
        set { withMutation(keyPath: \.tagOrder) { d.set(newValue, forKey: "tagOrder") } }
    }

    /// Ordem das listas escolhida arrastando na barra lateral.
    var listOrder: [String] {
        get { access(keyPath: \.listOrder); return d.stringArray(forKey: "listOrder") ?? [] }
        set { withMutation(keyPath: \.listOrder) { d.set(newValue, forKey: "listOrder") } }
    }

    var hotkeyTipDismissed: Bool {
        get { access(keyPath: \.hotkeyTipDismissed); return d.bool(forKey: "hotkeyTipDismissed") }
        set { withMutation(keyPath: \.hotkeyTipDismissed) { d.set(newValue, forKey: "hotkeyTipDismissed") } }
    }
}
