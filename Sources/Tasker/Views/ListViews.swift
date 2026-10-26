import SwiftUI

/// Todas as tarefas abertas, por prazo ou por lista.
struct AllTasksView: View {
    @Environment(TaskStore.self) private var store
    @AppStorage("allGroupByList") private var groupByList = false

    var body: some View {
        PageScaffold(title: "Todas", subtitle: taskCountText(store.activeCount)) {
            PillPicker(selection: $groupByList, options: [(false, "Por data"), (true, "Por lista")])

            if groupByList {
                ForEach(store.lists) { list in
                    let items = store.hierarchy(store.tasks(inList: list.id))
                    if !items.isEmpty {
                        TaskSection(store.displayName(list.id), count: items.count) {
                            ForEach(items) { TaskRow(task: $0.task, showList: false, depth: $0.depth) }
                        }
                    }
                }
            } else {
                group("Em atraso", store.overdueTasks, tint: .red)
                group("Hoje", store.todayTasks)
                group("Em breve", store.laterTasks)
                group("Sem data", store.undatedTasks)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [TaskItem], tint: Color? = nil) -> some View {
        if !items.isEmpty {
            TaskSection(title, count: items.count, tint: tint) {
                ForEach(items) { TaskRow(task: $0) }
            }
        }
    }
}

/// Uma lista do Google Tasks, com subtarefas indentadas e as concluídas recolhidas.
struct ListDetailView: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    @State private var editing = false

    var body: some View {
        let items = store.hierarchy(store.tasks(inList: listID))
        let done = store.completedTasks(inList: listID)
        PageScaffold(title: store.displayName(listID), subtitle: taskCountText(items.count)) {
            Button { editing = true } label: {
                ListIconView(listID: listID, size: 44)
                    .padding(6)
                    .background(store.color(forList: listID).opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Personalizar ícone e cor")
            .popover(isPresented: $editing) { ListAppearanceEditor(listID: listID) }
        } content: {
            TaskSection("Tarefas", count: items.count) {
                if items.isEmpty {
                    EmptyState(symbol: "checklist", title: "Lista vazia")
                } else {
                    ForEach(items) { TaskRow(task: $0.task, showList: false, depth: $0.depth) }
                }
            }
            if !done.isEmpty {
                TaskSection("Concluídas", count: done.count, startCollapsed: true) {
                    ForEach(done.prefix(30)) { TaskRow(task: $0, showList: false) }
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
            PageScaffold(title: tag.name, subtitle: "Etiqueta local — não aparece no Google Tasks") {
                HStack(spacing: 10) {
                    TextField("Nome", text: Binding(
                        get: { tag.name },
                        set: { var t = tag; t.name = $0; store.updateTag(t) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    ColorPicker("Cor", selection: Binding(
                        get: { Color(hex: tag.colorHex) },
                        set: { var t = tag; t.colorHex = $0.hexString; store.updateTag(t) }
                    ), supportsOpacity: false)
                }
                TaskSection("Tarefas", count: items.count) {
                    if items.isEmpty {
                        EmptyState(symbol: "tag", title: "Nenhuma tarefa com esta etiqueta",
                                   subtitle: "Clique com o botão direito numa tarefa → Etiquetas")
                    } else {
                        ForEach(items) { TaskRow(task: $0) }
                    }
                }
            }
        } else {
            EmptyState(symbol: "tag", title: "Etiqueta não encontrada")
        }
    }
}

/// Histórico de concluídas, agrupado por dia de conclusão.
struct CompletedView: View {
    @Environment(TaskStore.self) private var store
    @State private var limit = 40

    var body: some View {
        let items = Array(store.completedTasks.prefix(limit))
        let groups = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.completedDate ?? .distantPast) }
        PageScaffold(title: "Concluídas", subtitle: "\(store.completedTasks.count) tarefas") {
            ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                TaskSection(day == .distantPast ? "Sem data" : DayLabel.short(day, today: store.today),
                            count: groups[day]?.count ?? 0) {
                    ForEach(groups[day] ?? []) { TaskRow(task: $0, showDate: false) }
                }
            }
            if store.completedTasks.count > limit {
                // Paginação: carrega o próximo bloco quando chega ao fim da rolagem.
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .onAppear { limit += 40 }
            }
        }
    }
}
