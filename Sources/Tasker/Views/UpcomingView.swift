import SwiftUI

/// Próximos 14 dias: por dia, eventos e tarefas juntos no mesmo cartão.
struct UpcomingView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        let days = (1..<15).map { Calendar.current.adding(days: $0, to: store.today) }
            .filter { !store.tasks(on: $0).isEmpty || !store.events(on: $0).isEmpty }
        PageScaffold(rotulo: "Os próximos 14 dias", title: "Próximas") {
            VStack(alignment: .leading, spacing: DS.e6) {
                if days.isEmpty {
                    EstadoVazio(icone: "calendar", titulo: "Duas semanas livres",
                                descricao: "Tarefas e eventos dos próximos dias aparecem aqui.")
                }
                ForEach(days, id: \.self) { day in
                    DiaComItens(day: day)
                }
            }
        }
    }
}

/// Um dia: cabeçalho pequeno e um cartão com eventos (fundo na cor) e tarefas.
struct DiaComItens: View {
    @Environment(TaskStore.self) private var store
    let day: Date

    var body: some View {
        let events = store.events(on: day)
        let tasks = store.tasks(on: day)
        VStack(alignment: .leading, spacing: DS.e2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(DayLabel.short(day, today: store.today)).txt(.lg, .semibold).foregroundStyle(DS.texto)
                Text(day.formatted(.dateTime.day().month(.abbreviated))).txt(.sm).foregroundStyle(DS.texto3)
                Spacer()
                if !tasks.isEmpty {
                    Text(taskCountText(tasks.count)).txt(.xs).foregroundStyle(DS.texto3)
                }
            }
            .padding(.horizontal, DS.e1)
            EventsCard(events: events)
            if !tasks.isEmpty {
                CartaoDeLinhas {
                    ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                }
            }
        }
    }
}
