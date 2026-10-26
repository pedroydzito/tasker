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
    @ObservationIgnored private let d = UserDefaults.standard

    init() {
        d.register(defaults: [
            "showCount": true,
            "includeOverdue": true,
            "syncInterval": 30.0,
            "menuBarStyle": MenuBarStyle.badge.rawValue,
            "appearance": AppAppearance.system.rawValue,
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

    /// Emoji escolhido por lista ("" = sem emoji).
    var listEmojis: [String: String] {
        get { access(keyPath: \.listEmojis); return d.dictionary(forKey: "listEmojis") as? [String: String] ?? [:] }
        set { withMutation(keyPath: \.listEmojis) { d.set(newValue, forKey: "listEmojis") } }
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
