import SwiftUI

struct TaskRow: View {
    enum Style { case compact, full }

    @Environment(TaskStore.self) private var store
    @Environment(Navigation.self) private var nav
    let task: TaskItem
    var style: Style = .full
    var showDate = true
    var showList = true
    var depth = 0

    @State private var checking = false
    @State private var hovering = false
    @State private var editing = false

    private var checked: Bool { task.isCompleted || checking }
    private var isSelected: Bool { style == .full && nav.selectedTaskID == task.id }

    var body: some View {
        HStack(spacing: 10) {
            CheckCircle(color: store.color(forList: task.listID), checked: checked, action: toggle)

            Text(task.displayTitle)
                .font(.system(size: style == .compact ? 13.5 : 14))
                .strikethrough(checked, color: .secondary)
                .foregroundStyle(checked ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            ForEach(store.tags(for: task)) { tag in
                TagChip(name: tag.name, color: Color(hex: tag.colorHex))
            }
            if task.hasNotes {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            if showList, style == .full, let list = store.list(task.listID) {
                ListBadge(title: list.title, color: store.color(forList: list.id))
            }
            if showDate, let day = task.dueDay {
                DueBadge(day: day, today: store.today, filled: style == .full)
            }
        }
        .padding(.leading, 10 + CGFloat(depth) * 24)
        .padding(.trailing, 10)
        .padding(.vertical, style == .compact ? 7 : 9)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovering || editing ? 0.045 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            // Na janela principal abre o painel lateral; no popover da barra de menu, um popover.
            if style == .full { nav.selectedTaskID = task.id } else { editing = true }
        }
        .popover(isPresented: $editing, arrowEdge: .trailing) {
            TaskEditor(task: task) { editing = false }
        }
        .contextMenu { contextMenu }
        .opacity(task.isLocal ? 0.6 : 1)
    }

    private func toggle() {
        if task.isCompleted {
            store.setCompleted(task, false)
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { checking = true }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeInOut(duration: 0.25)) { store.setCompleted(task, true) }
            checking = false
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Button(task.isCompleted ? "Reabrir" : "Concluir") { store.setCompleted(task, !task.isCompleted) }
        Divider()
        Button("Hoje") { store.setDue(task, store.today) }
        Button("Amanhã") { store.setDue(task, Calendar.current.adding(days: 1, to: store.today)) }
        Button("Próxima semana") { store.setDue(task, Calendar.current.adding(days: 7, to: store.today)) }
        Button("Sem data") { store.setDue(task, nil) }
        if !store.tags.isEmpty {
            Menu("Etiquetas") {
                ForEach(store.tags) { tag in
                    let has = store.tags(for: task).contains(tag)
                    Button { store.toggleTag(tag, on: task) } label: {
                        if has { Label(tag.name, systemImage: "checkmark") } else { Text(tag.name) }
                    }
                }
            }
        }
        Divider()
        if let link = task.webViewLink.flatMap(URL.init(string:)) {
            Button("Abrir no Google") { NSWorkspace.shared.open(link) }
        }
        Button("Excluir", role: .destructive) { store.delete(task) }
    }
}
