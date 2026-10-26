import SwiftUI

/// Bloco de eventos do Google Calendar (como no KiteTasks), recolhível.
struct EventsCard: View {
    let events: [CalendarEvent]
    @AppStorage("eventsCollapsed") private var collapsed = false

    var body: some View {
        if !events.isEmpty {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(collapsed ? Array(events.prefix(1)) : events) { EventRow(event: $0) }
                    if collapsed, events.count > 1 {
                        Text("+ \(events.count - 1) evento\(events.count > 2 ? "s" : "")")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                            .padding(.vertical, 2)
                    }
                }
                if events.count > 1 {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { collapsed.toggle() }
                    } label: {
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(Color.accentColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct EventRow: View {
    let event: CalendarEvent
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: event.colorHex))
                .frame(width: 3, height: 15)
            Text(event.timeLabel).monospacedDigit()
            Text(event.title).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(Color.accentColor.opacity(hovering ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(event.end < .now ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let url = event.htmlLink.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
        }
        .help("Abrir no Google Calendar")
    }
}
