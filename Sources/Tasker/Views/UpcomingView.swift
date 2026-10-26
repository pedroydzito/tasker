import SwiftUI

/// Próximos 14 dias com eventos e tarefas (dias livres ficam de fora).
struct UpcomingView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        let days = (1..<15).map { Calendar.current.adding(days: $0, to: store.today) }
            .filter { !store.tasks(on: $0).isEmpty || !store.events(on: $0).isEmpty }
        PageScaffold(rotulo: "os próximos 14 dias", title: "próximas") {
            VStack(alignment: .leading, spacing: DS.e8) {
                if days.isEmpty {
                    EstadoVazio(icone: "calendar", titulo: "duas semanas livres",
                                descricao: "Tarefas e eventos dos próximos dias aparecem aqui.")
                }
                ForEach(days, id: \.self) { day in
                    let tasks = store.tasks(on: day)
                    VStack(alignment: .leading, spacing: DS.e3) {
                        HStack(alignment: .firstTextBaseline, spacing: DS.e2) {
                            Text(DayLabel.short(day, today: store.today).lowercased()).display(.titulo).foregroundStyle(DS.texto)
                            Text(day.formatted(.dateTime.day().month(.abbreviated))).txt(.sm).foregroundStyle(DS.texto3)
                        }
                        EventsCard(events: store.events(on: day))
                        if !tasks.isEmpty {
                            SecaoTarefas("tarefas", contagem: tasks.count) {
                                ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                            }
                        }
                    }
                }
            }
        }
    }
}
