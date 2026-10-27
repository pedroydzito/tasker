import SwiftUI

/// Moldura de página: cabeçalho (sobrancelha + título display) e conteúdo encadeado.
struct PageScaffold<Leading: View, Content: View>: View {
    let rotulo: String?
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var content: Content
    /// Ações discretas à direita do título (ex.: energia no Hoje).
    var acoes: AnyView?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.e5) {
                CabecalhoTela(rotulo: rotulo, titulo: title, leading: { leading }, trailing: { acoes ?? AnyView(EmptyView()) })
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
        .indicadorDeRolagem()
    }
}

extension PageScaffold where Leading == EmptyView {
    init(rotulo: String? = nil, title: String, acoes: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.rotulo = rotulo
        self.title = title
        self.leading = EmptyView()
        self.content = content()
        self.acoes = acoes
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
        let baixa = store.prefs.energiaBaixa
        // Sem energia: as mesmas linhas de sempre, mas sem atrasadas e sem números.
        let overdue = baixa ? [] : store.overdueTasks
        let today = store.todayTasks
        let done = store.completedToday
        PageScaffold(rotulo: baixa ? DayLabel.long(store.today) : "\(DayLabel.long(store.today)) · \(taskCountText(overdue.count + today.count))",
                     title: "Hoje", acoes: AnyView(BotaoEnergia())) {
            VStack(alignment: .leading, spacing: DS.e5) {
                EventsCard(events: store.events(on: store.today))

                if !overdue.isEmpty {
                    SecaoTarefas("Em atraso", contagem: overdue.count, tom: DS.perigoTexto,
                                 acao: ("Mover para hoje", { store.postponeOverdue() })) {
                        ForEach(overdue) { TaskRow(task: $0) }
                    }
                }

                let vazio = today.isEmpty && overdue.isEmpty
                // Sem pendências: as concluídas vêm logo abaixo dos eventos, antes do "Nada pendente".
                if vazio && !done.isEmpty { concluidas(done) }

                if today.isEmpty {
                    if overdue.isEmpty {
                        EstadoVazio(icone: "sun.max", titulo: "Nada pendente", descricao: "As tarefas com data de hoje aparecem aqui.")
                    }
                } else if overdue.isEmpty {
                    CartaoDeLinhas { ForEach(today) { TaskRow(task: $0, showDate: false) } }
                } else {
                    SecaoTarefas("Hoje", contagem: today.count) {
                        ForEach(today) { TaskRow(task: $0, showDate: false) }
                    }
                }

                if !vazio && !done.isEmpty { concluidas(done) }
            }
            .animation(DS.curva, value: today.map(\.id))
            .animation(DS.curva, value: baixa)
        }

    }

    private func concluidas(_ done: [TaskItem]) -> some View {
        SecaoTarefas("Concluídas", contagem: done.count, recolhida: true) {
            ForEach(done) { TaskRow(task: $0, showDate: false) }
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
                VStack(alignment: .leading, spacing: DS.e4) {
                    EventsCard(events: store.events(on: day))
                    if !tasks.isEmpty {
                        CartaoDeLinhas {
                            ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                        }
                    }
                }
            }
        }
    }
}
