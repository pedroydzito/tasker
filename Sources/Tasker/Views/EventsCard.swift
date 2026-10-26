import SwiftUI

/// Eventos do Google Calendar: o mesmo desenho em todas as telas (app e menu).
/// Sem fundo — cor, horário e título alinhados com o início dos cartões de tarefa.
/// Com mais de um evento, a seta à direita recolhe/expande (pode ser desligada).
struct EventsCard: View {
    let events: [CalendarEvent]
    var compacto = false
    var recolhivel = true
    @AppStorage("eventsCollapsed") private var collapsed = false

    var body: some View {
        if !events.isEmpty {
            let fechado = recolhivel && collapsed
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(fechado ? Array(events.prefix(1)) : events) { EventRow(event: $0, compacto: compacto) }
                }
                if recolhivel && events.count > 1 {
                    BotaoIcone(simbolo: collapsed ? "chevron.down" : "chevron.up",
                               rotulo: collapsed ? "Mostrar todos os eventos" : "Mostrar menos",
                               tamanho: 26, tamanhoIcone: 11) {
                        withAnimation(DS.curva) { collapsed.toggle() }
                    }
                    .padding(.top, compacto ? 1 : 3)
                }
            }
        }
    }
}

/// Uma linha de evento. Hover sem fundo: a barra engrossa e aparece a seta de "abrir".
struct EventRow: View {
    let event: CalendarEvent
    var compacto = false
    @State private var hovering = false

    var body: some View {
        let cor = Color(hex: event.colorHex)
        Button {
            if let url = event.htmlLink.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: DS.e3) {
                Capsule()
                    .fill(cor)
                    .frame(width: hovering ? 5 : 3, height: hovering ? 18 : 16)
                    .frame(width: 5, alignment: .leading)
                Text(event.timeLabel).txt(.xs, .medium).monospacedDigit().foregroundStyle(DS.texto3)
                    .frame(minWidth: 74, alignment: .leading)
                Text(event.title).txt(.sm, .medium).foregroundStyle(DS.texto).lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(cor)
                    .opacity(hovering ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
                Spacer(minLength: 0)
            }
            .padding(.vertical, compacto ? 6 : 7)
            .opacity(event.end < .now ? (hovering ? 0.75 : 0.45) : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoAfunda(escala: 0.99))
        .onHover { hovering = $0 }
        .animation(DS.curvaRapida, value: hovering)
        .help("Abrir no Google Calendar")
    }
}
