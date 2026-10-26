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

/// Um dia: cabeçalho com seta para recolher o dia inteiro; eventos e o cartão de tarefas.
struct DiaComItens: View {
    @Environment(TaskStore.self) private var store
    let day: Date
    @State private var recolhido = false

    var body: some View {
        let events = store.events(on: day)
        let tasks = store.tasks(on: day)
        VStack(alignment: .leading, spacing: DS.e2) {
            Button {
                withAnimation(DS.curva) { recolhido.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(DayLabel.short(day, today: store.today)).txt(.lg, .semibold).foregroundStyle(DS.texto)
                    Text(day.formatted(.dateTime.day().month(.abbreviated))).txt(.sm).foregroundStyle(DS.texto3)
                    Spacer()
                    if recolhido {
                        Text(resumo(events: events.count, tasks: tasks.count)).txt(.xs).foregroundStyle(DS.texto3)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.texto3)
                        .rotationEffect(.degrees(recolhido ? -90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SoAfunda(escala: 0.99))

            if !recolhido {
                VStack(alignment: .leading, spacing: DS.e2) {
                    EventsCard(events: events, recolhivel: false)
                    if !tasks.isEmpty {
                        CartaoDeLinhas {
                            ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                        }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }

    private func resumo(events: Int, tasks: Int) -> String {
        var partes: [String] = []
        if events > 0 { partes.append("\(events) evento\(events == 1 ? "" : "s")") }
        if tasks > 0 { partes.append("\(tasks) tarefa\(tasks == 1 ? "" : "s")") }
        return partes.joined(separator: " · ")
    }
}
