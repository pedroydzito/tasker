import Foundation
import UserNotifications

/// Lembrete gentil do despejo: uma notificação por dia, no horário escolhido, só se houver algo
/// na caixa. Sem cobrança: o texto convida a organizar poucas coisas.
@MainActor
enum LembreteDespejo {
    static let identificador = "tasker.lembrete.despejo"
    static let categoria = "TASKER_DESPEJO"

    /// Próximo horário do lembrete: hoje, se ainda não passou; senão, amanhã.
    nonisolated static func proximoDisparo(hora: Int, agora: Date = .now, calendario: Calendar = .current) -> Date {
        let hoje = calendario.date(bySettingHour: min(max(hora, 0), 23), minute: 0, second: 0, of: agora) ?? agora
        return hoje > agora ? hoje : calendario.date(byAdding: .day, value: 1, to: hoje) ?? hoje
    }

    nonisolated static func texto(quantidade: Int) -> String {
        quantidade == 1
            ? "Tem 1 coisa no despejo. Quer olhar para ela com calma?"
            : "Tem \(quantidade) coisas no despejo. Que tal organizar só 3?"
    }

    /// Reagenda (ou cancela) o lembrete conforme o despejo e os ajustes.
    static func agendar(quantidade: Int, prefs: Preferences, agora: Date = .now) {
        // No autoteste e nas capturas não mexe nas notificações do sistema.
        guard Pastas.isolado == nil else { return }
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(withIdentifiers: [identificador])
        guard prefs.lembreteDespejo, quantidade > 0 else { return }
        centro.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let quando = proximoDisparo(hora: prefs.horaLembrete, agora: agora)
        let conteudo = UNMutableNotificationContent()
        conteudo.title = "Despejo"
        conteudo.body = texto(quantidade: quantidade)
        conteudo.categoryIdentifier = categoria
        let partes = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: quando)
        let gatilho = UNCalendarNotificationTrigger(dateMatching: partes, repeats: false)
        centro.add(UNNotificationRequest(identifier: identificador, content: conteudo, trigger: gatilho))
    }
}
