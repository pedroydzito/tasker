import SwiftUI

/// Todas as tarefas abertas, agrupadas por prazo (atrasadas, hoje, em breve, sem data).
struct AllTasksView: View {
    @Environment(TaskStore.self) private var store
    @State private var groupByList = false

    var body: some View {
        PageScaffold(title: "Todas") {
            HStack {
                QuickAddField(style: .inline)
                Picker("", selection: $groupByList) {
                    Text("Por data").tag(false)
                    Text("Por lista").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 1) {
                if groupByList {
                    ForEach(store.lists) { list in
                        let items = store.hierarchy(store.tasks(inList: list.id))
                        if !items.isEmpty {
                            SectionHeader(title: list.title, count: items.count, tint: store.color(forList: list.id))
                            ForEach(items) { TaskRow(task: $0.task, showList: false, depth: $0.depth) }
                        }
                    }
                } else {
                    let all = store.tasks.values.filter { !$0.isCompleted }
                    let today = store.today
                    let overdue = store.overdueTasks
                    let todays = store.todayTasks
                    let later = all.filter { ($0.dueDay ?? .distantPast) > today }
                        .sorted { ($0.dueDay ?? .distantFuture) < ($1.dueDay ?? .distantFuture) }
                    let undated = store.undatedTasks

                    group("Em atraso", overdue, tint: .red)
                    group("Hoje", todays)
                    group("Em breve", later)
                    group("Sem data", undated)
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [TaskItem], tint: Color = .secondary) -> some View {
        if !items.isEmpty {
            SectionHeader(title: title, count: items.count, tint: tint)
            ForEach(items) { TaskRow(task: $0) }
        }
    }
}

/// Uma lista do Google Tasks, com subtarefas indentadas.
struct ListDetailView: View {
    @Environment(TaskStore.self) private var store
    let listID: String

    var body: some View {
        let list = store.list(listID)
        PageScaffold(title: list?.title ?? "Lista") {
            HStack(spacing: 10) {
                QuickAddField(fixedListID: listID, style: .inline)
                if list != nil {
                    ColorPicker("", selection: Binding(
                        get: { store.color(forList: listID) },
                        set: { store.setColor($0, forList: listID) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .help("Cor da lista")
                }
            }
            let items = store.hierarchy(store.tasks(inList: listID))
            VStack(alignment: .leading, spacing: 1) {
                if items.isEmpty {
                    EmptyState(symbol: "checklist", title: "Lista vazia")
                } else {
                    ForEach(items) { TaskRow(task: $0.task, showList: false, depth: $0.depth) }
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
                let items = store.tasks(withTag: tagID)
                VStack(alignment: .leading, spacing: 1) {
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
    @State private var limit = 100

    var body: some View {
        let items = Array(store.completedTasks.prefix(limit))
        let groups = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.completedDate ?? .distantPast) }
        PageScaffold(title: "Concluídas", subtitle: "\(store.completedTasks.count) tarefas") {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    SectionHeader(title: day == .distantPast ? "Sem data" : DayLabel.short(day, today: store.today),
                                  count: groups[day]?.count ?? 0)
                    ForEach(groups[day] ?? []) { TaskRow(task: $0, showDate: false) }
                }
                if store.completedTasks.count > limit {
                    Button("Ver mais") { limit += 100 }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .padding(10)
                }
            }
        }
    }
}
