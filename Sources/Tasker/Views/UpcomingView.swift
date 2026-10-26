import SwiftUI

/// Próximos 14 dias com eventos e tarefas (dias livres ficam de fora).
struct UpcomingView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        let days = (1..<15).map { Calendar.current.adding(days: $0, to: store.today) }
            .filter { !store.tasks(on: $0).isEmpty || !store.events(on: $0).isEmpty }
        PageScaffold(title: "Próximas", subtitle: "Os próximos 14 dias") {
            if days.isEmpty {
                EmptyState(symbol: "calendar", title: "Nada nos próximos 14 dias")
            }
            ForEach(days, id: \.self) { day in
                let tasks = store.tasks(on: day)
                TaskSection("\(DayLabel.short(day, today: store.today)) · \(day.formatted(.dateTime.day().month(.abbreviated)))",
                            count: tasks.count) {
                    EventsCard(events: store.events(on: day))
                    ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                }
            }
        }
    }
}
