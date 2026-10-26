import Foundation
import Observation

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconAndNumber, numberInSquare
    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconAndNumber: "Ícone + número"
        case .numberInSquare: "Número no quadrado"
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
            "menuBarStyle": MenuBarStyle.iconAndNumber.rawValue,
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
            return MenuBarStyle(rawValue: d.string(forKey: "menuBarStyle") ?? "") ?? .iconAndNumber
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

    var hotkeyTipDismissed: Bool {
        get { access(keyPath: \.hotkeyTipDismissed); return d.bool(forKey: "hotkeyTipDismissed") }
        set { withMutation(keyPath: \.hotkeyTipDismissed) { d.set(newValue, forKey: "hotkeyTipDismissed") } }
    }
}
