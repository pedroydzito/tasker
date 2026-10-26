import SwiftUI

/// Eventos do Google Calendar do dia: um cartão com uma linha por evento.
struct EventsCard: View {
    let events: [CalendarEvent]
    var compacto = false
    @AppStorage("eventsCollapsed") private var collapsed = false

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(collapsed ? Array(events.prefix(1)) : events) { EventRow(event: $0, compacto: compacto) }
                if events.count > 1 {
                    Button {
                        withAnimation(DS.curva) { collapsed.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(collapsed ? "mais \(events.count - 1) evento\(events.count > 2 ? "s" : "")" : "mostrar menos")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8.5, weight: .bold))
                                .rotationEffect(.degrees(collapsed ? 0 : 180))
                        }
                        .txt(.xs, .medium)
                        .foregroundStyle(DS.texto3)
                        .padding(.horizontal, DS.e3)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(Pressionavel(raio: DS.raioM))
                    .padding(.leading, DS.e1)
                    .padding(.bottom, DS.e1)
                }
            }
            .padding(DS.e1)
            .background(DS.superficie, in: RoundedRectangle(cornerRadius: compacto ? DS.raioG : DS.raioCartao, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: compacto ? DS.raioG : DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
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
                Capsule().fill(Color(hex: event.colorHex)).frame(width: 3, height: compacto ? 16 : 20)
                Text(event.timeLabel).txt(.xs, .medium).monospacedDigit().foregroundStyle(DS.texto3)
                    .frame(minWidth: 76, alignment: .leading)
                Text(event.title).txt(compacto ? .sm : .md, .medium).foregroundStyle(DS.texto).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.e3)
            .padding(.vertical, compacto ? 7 : 10)
            .opacity(event.end < .now ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressionavel(raio: compacto ? DS.raioM : DS.raioG, escala: 0.995))
        .help("Abrir no Google Calendar")
    }
}
