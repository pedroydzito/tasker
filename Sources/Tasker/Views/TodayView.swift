import SwiftUI

/// Moldura de página: cabeçalho (sobrancelha + título display) e conteúdo encadeado.
struct PageScaffold<Leading: View, Content: View>: View {
    let rotulo: String?
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.e5) {
                CabecalhoTela(rotulo: rotulo, titulo: title) { leading }
                    .encadeado(0)
                Avisos()
                content.encadeado(1)
            }
            .padding(.horizontal, 40)
            .padding(.top, 44)
            .padding(.bottom, 120)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

extension PageScaffold where Leading == EmptyView {
    init(rotulo: String? = nil, title: String, @ViewBuilder content: () -> Content) {
        self.rotulo = rotulo
        self.title = title
        self.leading = EmptyView()
        self.content = content()
    }
}

/// Avisos do topo da tela — só ocupam espaço quando existem.
struct Avisos: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        if store.calendarIssue != nil || store.lastError != nil {
            VStack(alignment: .leading, spacing: DS.e3) {
                CalendarIssueBanner()
                ErrorBanner()
            }
        }
    }
}

func taskCountText(_ count: Int) -> String {
    count == 0 ? "Nada pendente" : "\(count) tarefa\(count == 1 ? "" : "s") para concluir"
}

struct TodayView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        let overdue = store.overdueTasks
        let today = store.todayTasks
        let done = store.completedToday
        PageScaffold(rotulo: "\(DayLabel.long(store.today)) · \(taskCountText(overdue.count + today.count))", title: "Hoje") {
            VStack(alignment: .leading, spacing: DS.e5) {
                EventsCard(events: store.events(on: store.today))

                if !overdue.isEmpty {
                    SecaoTarefas("Em atraso", contagem: overdue.count, tom: DS.perigoTexto,
                                 acao: ("Mover para hoje", { store.postponeOverdue() })) {
                        ForEach(overdue) { TaskRow(task: $0) }
                    }
                }

                SecaoTarefas("Hoje", contagem: today.count) {
                    if today.isEmpty {
                        EstadoVazio(icone: "sun.max", titulo: "Nada pendente", descricao: "As tarefas com data de hoje aparecem aqui.")
                    } else {
                        ForEach(today) { TaskRow(task: $0, showDate: false) }
                    }
                }

                if !done.isEmpty {
                    SecaoTarefas("Concluídas hoje", contagem: done.count, recolhida: true) {
                        ForEach(done) { TaskRow(task: $0, showDate: false) }
                    }
                }
            }
            .animation(DS.curva, value: today.map(\.id))
        }
    }
}

/// Tarefas e eventos de um único dia (usado em "Amanhã").
struct DayView: View {
    @Environment(TaskStore.self) private var store
    let title: String
    let day: Date

    var body: some View {
        let tasks = store.tasks(on: day)
        let empty = tasks.isEmpty && store.events(on: day).isEmpty
        PageScaffold(rotulo: "\(DayLabel.long(day)) · \(taskCountText(tasks.count))", title: title) {
            if empty {
                EstadoVazio(icone: "sunrise", titulo: "Dia livre", descricao: "Nada marcado para \(title.lowercased()).")
            } else {
                CartaoDeLinhas {
                    ForEach(store.events(on: day)) { EventoNaLista(event: $0) }
                    ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                }
            }
        }
    }
}
