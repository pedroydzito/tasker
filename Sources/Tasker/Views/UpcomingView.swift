import SwiftUI

/// Próximos 14 dias, dia a dia, com eventos e tarefas.
struct UpcomingView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        PageScaffold(title: "Próximas", subtitle: "Os próximos 14 dias") {
            QuickAddField(defaultDue: Calendar.current.adding(days: 1, to: store.today), style: .inline)

            ForEach(1..<15, id: \.self) { offset in
                let day = Calendar.current.adding(days: offset, to: store.today)
                let tasks = store.tasks(on: day)
                let events = store.events(on: day)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(DayLabel.short(day, today: store.today)).font(.system(size: 16, weight: .semibold))
                        Text(day.formatted(.dateTime.day().month(.abbreviated))).font(.system(size: 13)).foregroundStyle(.secondary)
                        if !tasks.isEmpty {
                            Text("\(tasks.count)").font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                    }
                    EventsCard(events: events)
                    ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                    if tasks.isEmpty && events.isEmpty {
                        Text("Livre").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.leading, 2)
                    }
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }
}
