import SwiftUI

/// Todas as tarefas abertas, por prazo ou por lista.
struct AllTasksView: View {
    @Environment(TaskStore.self) private var store
    @AppStorage("allGroupByList") private var groupByList = false

    var body: some View {
        PageScaffold(rotulo: taskCountText(store.activeCount), title: "Todas") {
            VStack(alignment: .leading, spacing: DS.e6) {
                Segmentado(selecao: $groupByList, opcoes: [(false, "Por data"), (true, "Por lista")])

                if groupByList {
                    ForEach(store.lists) { list in
                        let items = store.hierarchy(store.tasks(inList: list.id))
                        if !items.isEmpty {
                            SecaoTarefas(store.displayName(list.id), contagem: items.count, tom: store.color(forList: list.id)) {
                                ForEach(items) { TaskRow(task: $0.task, showList: false, depth: $0.depth) }
                            }
                        }
                    }
                } else {
                    grupo("Em atraso", store.overdueTasks, tom: DS.perigoTexto)
                    grupo("Hoje", store.todayTasks)
                    grupo("Em breve", store.laterTasks)
                    grupo("Sem data", store.undatedTasks)
                }
            }
        }
    }

    @ViewBuilder
    private func grupo(_ titulo: String, _ items: [TaskItem], tom: Color = DS.texto3) -> some View {
        if !items.isEmpty {
            SecaoTarefas(titulo, contagem: items.count, tom: tom) {
                ForEach(items) { TaskRow(task: $0) }
            }
        }
    }
}

/// Uma lista do Google Tasks. A foto ganha um anel na cor da lista, para identificar de relance.
struct ListDetailView: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    let listID: String

    var body: some View {
        let items = store.hierarchy(store.tasks(inList: listID))
        let done = store.completedTasks(inList: listID)
        let cor = store.color(forList: listID)
        PageScaffold(rotulo: taskCountText(items.count), title: store.displayName(listID)) {
            Button {
                folhas.abrir("Personalizar lista", largura: 440) { EditorDeLista(listID: listID) }
            } label: {
                ListIconView(listID: listID, size: 56)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 64 * 0.3, style: .continuous).strokeBorder(cor, lineWidth: 2.5))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(cor))
                            .overlay(Circle().strokeBorder(DS.fundo, lineWidth: 2))
                            .offset(x: 4, y: 4)
                    }
            }
            .buttonStyle(SoAfunda(escala: 0.94))
            .help("Personalizar ícone e cor")
        } content: {
            VStack(alignment: .leading, spacing: DS.e6) {
                SecaoTarefas("Tarefas", contagem: items.count, tom: cor) {
                    if items.isEmpty {
                        EstadoVazio(icone: "checklist", titulo: "Lista vazia", descricao: "Use a barra abaixo para criar a primeira tarefa.")
                    } else {
                        ForEach(items) { TaskRow(task: $0.task, showList: false, depth: $0.depth) }
                    }
                }
                if !done.isEmpty {
                    SecaoTarefas("Concluídas", contagem: done.count, recolhida: true) {
                        ForEach(done.prefix(30)) { TaskRow(task: $0, showList: false) }
                    }
                }
            }
        }
    }
}

/// Tarefas com uma etiqueta local.
struct TagDetailView: View {
    @Environment(TaskStore.self) private var store
    let tagID: String

    var body: some View {
        if let tag = store.tag(tagID) {
            let items = store.tasks(withTag: tagID)
            PageScaffold(rotulo: "Etiqueta · só no Tasker", title: "#\(tag.name)") {
                VStack(alignment: .leading, spacing: DS.e6) {
                    HStack(spacing: DS.e4) {
                        TextField("Nome", text: Binding(
                            get: { tag.name },
                            set: { var t = tag; t.name = $0; store.updateTag(t) }
                        ))
                        .campo()
                        .frame(maxWidth: 240)
                        AmostrasDeCor(selecao: Binding(
                            get: { tag.colorHex },
                            set: { var t = tag; t.colorHex = $0; store.updateTag(t) }
                        ))
                    }
                    SecaoTarefas("Tarefas", contagem: items.count) {
                        if items.isEmpty {
                            EstadoVazio(icone: "number", titulo: "Nenhuma tarefa aqui",
                                        descricao: "Clique com o botão direito numa tarefa → Etiquetas.")
                        } else {
                            ForEach(items) { TaskRow(task: $0) }
                        }
                    }
                }
            }
        } else {
            EstadoVazio(icone: "number", titulo: "Etiqueta não encontrada")
        }
    }
}

/// Histórico de concluídas, agrupado por dia, carregando aos poucos.
struct CompletedView: View {
    @Environment(TaskStore.self) private var store
    @State private var limit = 40

    var body: some View {
        let items = Array(store.completedTasks.prefix(limit))
        let groups = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.completedDate ?? .distantPast) }
        PageScaffold(rotulo: "\(store.completedTasks.count) tarefas até aqui", title: "Concluídas") {
            VStack(alignment: .leading, spacing: DS.e6) {
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    SecaoTarefas(day == .distantPast ? "Sem data" : DayLabel.short(day, today: store.today),
                                 contagem: groups[day]?.count ?? 0) {
                        ForEach(groups[day] ?? []) { TaskRow(task: $0, showDate: false) }
                    }
                }
                if store.completedTasks.count > limit {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(DS.e3)
                        .onAppear { limit += 40 }
                }
            }
        }
    }
}
