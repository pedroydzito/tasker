import SwiftUI

/// Popover de edição rápida (usado no popover da barra de menu).
struct TaskEditor: View {
    @Environment(TaskStore.self) private var store
    let task: TaskItem
    let onClose: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var due: Date?

    init(task: TaskItem, onClose: @escaping () -> Void) {
        self.task = task
        self.onClose = onClose
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes ?? "")
        _due = State(initialValue: task.dueDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ListIconView(listID: task.listID, size: 14)
                Text(store.displayName(task.listID)).font(.system(size: 12)).foregroundStyle(Theme.subtle)
            }
            TextField("Título", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .onSubmit(save)
            TextField("Notas", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(3...10)
            HStack {
                DueChip(due: $due)
                TagPicker(task: task)
                Spacer()
            }
            HStack {
                Button(role: .destructive) {
                    store.delete(task)
                    onClose()
                } label: { Image(systemName: "trash").iconButtonLabel() }
                    .buttonStyle(.pressable)
                    .help("Excluir tarefa")
                Spacer()
                Button("Cancelar", action: onClose).keyboardShortcut(.cancelAction).buttonStyle(.soft)
                Button("Salvar", action: save).keyboardShortcut(.defaultAction).buttonStyle(.primary)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func save() {
        store.save(store.tasks[task.id] ?? task, title: title, notes: notes, due: due)
        onClose()
    }
}

/// Painel de detalhes à direita da janela principal (inspirado na referência do Dribbble).
/// Tudo salva sozinho no Google Tasks.
struct TaskInspector: View {
    @Environment(TaskStore.self) private var store
    let task: TaskItem
    let onClose: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var due: Date?

    init(task: TaskItem, onClose: @escaping () -> Void) {
        self.task = task
        self.onClose = onClose
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes ?? "")
        _due = State(initialValue: task.dueDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Rectangle().fill(Theme.stroke).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 6) {
                        ListIconView(listID: task.listID, size: 16)
                        Text(store.displayName(task.listID)).font(.system(size: 12.5)).foregroundStyle(Theme.subtle)
                    }

                    TextField("Título", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 24, weight: .semibold))

                    HStack(spacing: 8) {
                        ListChip(listID: task.listID)
                        DueChip(due: $due)
                        TagPicker(task: task)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Descrição").font(.system(size: 13, weight: .semibold))
                        TextEditor(text: $notes)
                            .font(.system(size: 13.5))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                            .padding(10)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Label("Salvo automaticamente no Google Tasks", systemImage: "checkmark.icloud")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(22)
            }
        }
        .background(Theme.surface)
        .task(id: "\(title)\u{0}\(notes)\u{0}\(due?.timeIntervalSince1970 ?? 0)") {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            persist()
        }
        .onDisappear(perform: persist)
    }

    private var toolbar: some View {
        let current = store.tasks[task.id] ?? task
        return HStack(spacing: 4) {
            Button {
                store.setCompleted(current, !current.isCompleted)
            } label: {
                Label(current.isCompleted ? "Reabrir" : "Concluir",
                      systemImage: current.isCompleted ? "arrow.uturn.backward" : "checkmark")
            }
            .buttonStyle(.soft)
            Spacer()
            if let link = task.webViewLink.flatMap(URL.init(string:)) {
                Button { NSWorkspace.shared.open(link) } label: { Image(systemName: "arrow.up.right.square").iconButtonLabel() }
                    .buttonStyle(.pressable)
                    .help("Abrir no Google")
            }
            Button {
                store.delete(current)
                onClose()
            } label: { Image(systemName: "trash").iconButtonLabel() }
                .buttonStyle(.pressable)
                .help("Excluir")
            Button(action: onClose) { Image(systemName: "xmark").iconButtonLabel() }
                .buttonStyle(.pressable)
                .keyboardShortcut(.cancelAction)
                .help("Fechar")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func persist() {
        guard let current = store.tasks[task.id] else { return }
        store.save(current, title: title, notes: notes, due: due)
    }
}

/// Chip de data com calendário em popover.
struct DueChip: View {
    @Environment(TaskStore.self) private var store
    @Binding var due: Date?
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                Text(due.map { DayLabel.short($0, today: store.today) } ?? "Sem data")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(due.map { $0 < store.today ? Color.red : Color.primary } ?? Theme.subtle)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(Theme.stroke))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $picking) {
            VStack(spacing: 10) {
                HStack {
                    quick("Hoje", 0)
                    quick("Amanhã", 1)
                    quick("+1 semana", 7)
                    Button("Sem data") { due = nil; picking = false }.buttonStyle(.soft)
                }
                DatePicker("", selection: Binding(
                    get: { due ?? store.today },
                    set: { due = Calendar.current.startOfDay(for: $0) }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            }
            .padding(12)
        }
    }

    private func quick(_ label: String, _ days: Int) -> some View {
        Button(label) {
            due = Calendar.current.adding(days: days, to: store.today)
            picking = false
        }
        .buttonStyle(.soft)
    }
}

/// Etiquetas locais da tarefa + menu para adicionar/criar.
struct TagPicker: View {
    @Environment(TaskStore.self) private var store
    let task: TaskItem
    @State private var addingTag = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(store.tags(for: task)) { TagChip(name: $0.name, color: Color(hex: $0.colorHex)) }
            Menu {
                ForEach(store.tags) { tag in
                    let has = store.tags(for: task).contains(tag)
                    Button { store.toggleTag(tag, on: task) } label: {
                        if has { Label(tag.name, systemImage: "checkmark") } else { Text(tag.name) }
                    }
                }
                if !store.tags.isEmpty { Divider() }
                Button("Nova etiqueta…") { addingTag = true }
            } label: {
                Image(systemName: "tag").font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Etiquetas (só no Tasker)")
            .popover(isPresented: $addingTag) {
                TagCreator { tag in
                    store.toggleTag(tag, on: task)
                    addingTag = false
                }
            }
        }
    }

}
