import SwiftUI

/// Eventos do Google Calendar do dia: um cartão com uma linha por evento.
/// Recolher/expandir é só a seta no canto superior direito.
struct EventsCard: View {
    let events: [CalendarEvent]
    var compacto = false
    @AppStorage("eventsCollapsed") private var collapsed = false

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(collapsed ? Array(events.prefix(1)) : events) { EventRow(event: $0, compacto: compacto) }
            }
            .padding(DS.e1)
            .padding(.trailing, events.count > 1 ? 30 : 0)
            .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
            .overlay(alignment: .topTrailing) {
                if events.count > 1 {
                    BotaoIcone(simbolo: collapsed ? "chevron.down" : "chevron.up",
                               rotulo: collapsed ? "Mostrar todos os eventos" : "Mostrar menos",
                               tamanho: 26, tamanhoIcone: 11) {
                        withAnimation(DS.curva) { collapsed.toggle() }
                    }
                    .padding(.top, compacto ? 6 : 8)
                    .padding(.trailing, 6)
                }
            }
        }
    }
}

struct EventRow: View {
    let event: CalendarEvent
    var compacto = false

    var body: some View {
        Button {
            if let url = event.htmlLink.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: DS.e3) {
                Capsule().fill(Color(hex: event.colorHex)).frame(width: 3, height: 16)
                Text(event.timeLabel).txt(.xs, .medium).monospacedDigit().foregroundStyle(DS.texto3)
                    .frame(minWidth: 74, alignment: .leading)
                Text(event.title).txt(.sm, .medium).foregroundStyle(DS.texto).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.e3)
            .padding(.vertical, compacto ? 7 : 9)
            .opacity(event.end < .now ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressionavel(raio: DS.raioM, escala: 0.995))
        .help("Abrir no Google Calendar")
    }
}

/// Evento dentro de uma lista de tarefas: sem círculo, com o fundo na cor do evento.
struct EventoNaLista: View {
    let event: CalendarEvent

    var body: some View {
        let cor = Color(hex: event.colorHex)
        Button {
            if let url = event.htmlLink.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: DS.e3) {
                Image(systemName: event.isAllDay ? "sun.max" : "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(cor)
                    .frame(width: 18)
                Text(event.title).txt(.md, .medium).foregroundStyle(DS.texto).lineLimit(1)
                Spacer(minLength: DS.e2)
                Text(event.timeLabel).txt(.xs, .medium).monospacedDigit().foregroundStyle(DS.texto2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(cor.opacity(0.14)))
            .opacity(event.end < .now ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoAfunda(escala: 0.995))
        .padding(.vertical, 2)
        .help("Abrir no Google Calendar")
    }
}
