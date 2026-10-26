import SwiftUI

/// Eventos do Google Calendar: o mesmo desenho em todas as telas (app e menu).
/// Sem fundo de cartão — cor, horário e título alinhados à esquerda.
/// Com mais de um evento, a seta à direita recolhe/expande.
struct EventsCard: View {
    let events: [CalendarEvent]
    var compacto = false
    @AppStorage("eventsCollapsed") private var collapsed = false

    var body: some View {
        if !events.isEmpty {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(collapsed ? Array(events.prefix(1)) : events) { EventRow(event: $0, compacto: compacto) }
                }
                if events.count > 1 {
                    BotaoIcone(simbolo: collapsed ? "chevron.down" : "chevron.up",
                               rotulo: collapsed ? "Mostrar todos os eventos" : "Mostrar menos",
                               tamanho: 26, tamanhoIcone: 11) {
                        withAnimation(DS.curva) { collapsed.toggle() }
                    }
                    .padding(.top, compacto ? 2 : 4)
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
            .padding(.vertical, compacto ? 6 : 7)
            .opacity(event.end < .now ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressionavel(raio: DS.raioM, escala: 0.995))
        .help("Abrir no Google Calendar")
    }
}
