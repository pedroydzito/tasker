import SwiftUI

/// Moldura de página: cabeçalho (sobrancelha + título display) e conteúdo encadeado.
struct PageScaffold<Leading: View, Content: View>: View {
    let rotulo: String?
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.e6) {
                CabecalhoTela(rotulo: rotulo, titulo: title) { leading }
                    .padding(.bottom, DS.e2)
                    .encadeado(0)
                VStack(alignment: .leading, spacing: DS.e3) {
                    CalendarIssueBanner()
                    ErrorBanner()
                }
                content.encadeado(1)
            }
            .padding(.horizontal, 48)
            .padding(.top, 56)
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

func taskCountText(_ count: Int) -> String {
    count == 0 ? "nada pendente" : "\(count) tarefa\(count == 1 ? "" : "s") para concluir"
}

struct TodayView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        let overdue = store.overdueTasks
        let today = store.todayTasks
        let done = store.completedToday
        PageScaffold(rotulo: "\(DayLabel.long(store.today)) · \(taskCountText(overdue.count + today.count))", title: "hoje") {
            VStack(alignment: .leading, spacing: DS.e6) {
                EventsCard(events: store.events(on: store.today))

                if !overdue.isEmpty {
                    SecaoTarefas("em atraso", contagem: overdue.count, tom: DS.acentoTexto,
                                 acao: ("Mover para hoje", { store.postponeOverdue() })) {
                        ForEach(overdue) { TaskRow(task: $0) }
                    }
                }

                SecaoTarefas("hoje", contagem: today.count) {
                    if today.isEmpty {
                        EstadoVazio(icone: "sun.max", titulo: "nada pendente", descricao: "As tarefas com data de hoje aparecem aqui.")
                    } else {
                        ForEach(today) { TaskRow(task: $0, showDate: false) }
                    }
                }

                if !done.isEmpty {
                    SecaoTarefas("concluídas hoje", contagem: done.count, recolhida: true) {
                        ForEach(done) { TaskRow(task: $0, showDate: false) }
                    }
                }
            }
            .animation(DS.curva, value: today.map(\.id))
        }
    }
}

/// Tarefas e eventos de um único dia (usado em "amanhã").
struct DayView: View {
    @Environment(TaskStore.self) private var store
    let title: String
    let day: Date

    var body: some View {
        let tasks = store.tasks(on: day)
        PageScaffold(rotulo: "\(DayLabel.long(day)) · \(taskCountText(tasks.count))", title: title) {
            VStack(alignment: .leading, spacing: DS.e6) {
                EventsCard(events: store.events(on: day))
                SecaoTarefas(title, contagem: tasks.count) {
                    if tasks.isEmpty {
                        EstadoVazio(icone: "sunrise", titulo: "dia livre", descricao: "Nenhuma tarefa marcada para \(title).")
                    } else {
                        ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                    }
                }
            }
        }
    }
}
