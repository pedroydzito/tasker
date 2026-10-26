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
        Group {
            if style == .compact { compactBody } else { cardBody }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            // Na janela principal abre o painel de detalhes; no popover da barra de menu, um popover.
            if style == .full { nav.selectedTaskID = task.id } else { editing = true }
        }
        .popover(isPresented: $editing, arrowEdge: .trailing) {
            TaskEditor(task: task) { editing = false }
        }
        .contextMenu { contextMenu }
        .opacity(task.isLocal ? 0.6 : 1)
    }

    // MARK: Popover (linha simples, como no KiteTasks)

    private var compactBody: some View {
        HStack(spacing: 10) {
            CheckCircle(color: store.color(forList: task.listID), checked: checked, action: toggle)
            Text(task.displayTitle)
                .font(.system(size: 13.5))
                .strikethrough(checked, color: .secondary)
                .foregroundStyle(checked ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if task.hasNotes {
                Image(systemName: "text.alignleft").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            if showDate, let day = task.dueDay {
                Text(DayLabel.short(day, today: store.today))
                    .font(.system(size: 12))
                    .foregroundStyle(day < store.today ? Color.red : Theme.subtle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering || editing ? 0.045 : 0))
        )
    }

    // MARK: Janela principal (cartão)

    private var cardBody: some View {
        let tags = store.tags(for: task)
        let hasMeta = (showDate && task.dueDay != nil) || task.hasNotes || !tags.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                CheckCircle(color: store.color(forList: task.listID), checked: checked, action: toggle)
                Text(task.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .strikethrough(checked, color: .secondary)
                    .foregroundStyle(checked ? .secondary : .primary)
                    .lineLimit(1)
                if showList { ListChip(listID: task.listID) }
                Spacer(minLength: 0)
            }
            if hasMeta {
                HStack(spacing: 14) {
                    if showDate, let day = task.dueDay {
                        DueLabel(day: day, today: store.today)
                    }
                    if task.hasNotes {
                        HStack(spacing: 4) {
                            Image(systemName: "text.alignleft")
                            Text((task.notes ?? "").components(separatedBy: .newlines).first ?? "")
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 260, alignment: .leading)
                    }
                    ForEach(tags) { TagChip(name: $0.name, color: Color(hex: $0.colorHex)) }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.subtle)
                .padding(.leading, 29)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Theme.stroke.opacity(hovering ? 1 : 0.5),
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.07 : 0.025), radius: hovering ? 8 : 2, y: hovering ? 3 : 1)
        .padding(.leading, CGFloat(depth) * 26)
        .animation(.easeOut(duration: 0.15), value: hovering)
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
