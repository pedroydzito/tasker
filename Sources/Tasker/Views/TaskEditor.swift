import SwiftUI

/// Popover de edição: título, notas, data e exclusão.
struct TaskEditor: View {
    @Environment(TaskStore.self) private var store
    let task: TaskItem
    /// Exibido no painel lateral da janela principal (em vez de popover).
    var isInspector = false
    let onClose: () -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDue = false
    @State private var due = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Título", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .onSubmit(save)

            TextField("Notas", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(3...10)

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "calendar").foregroundStyle(.secondary)
                if hasDue {
                    DatePicker("", selection: $due, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .fixedSize()
                } else {
                    Text("Sem data").foregroundStyle(.secondary)
                }
                Spacer()
                quickDate("Hoje", 0)
                quickDate("Amanhã", 1)
                Button { hasDue = false } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
                    .help("Remover data")
                    .disabled(!hasDue)
            }
            .font(.system(size: 12.5))

            HStack(spacing: 6) {
                if let list = store.list(task.listID) {
                    ListBadge(title: list.title, color: store.color(forList: list.id))
                }
                ForEach(store.tags(for: task)) { tag in
                    TagChip(name: tag.name, color: Color(hex: tag.colorHex))
                }
                tagMenu
                Spacer()
            }

            HStack {
                Button(role: .destructive) {
                    store.delete(task)
                    onClose()
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Excluir tarefa")
                if let link = task.webViewLink.flatMap(URL.init(string:)) {
                    Button { NSWorkspace.shared.open(link) } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(.borderless)
                        .help("Abrir no Google")
                }
                Spacer()
                Button(isInspector ? "Fechar" : "Cancelar", action: onClose).keyboardShortcut(.cancelAction)
                Button("Salvar", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: isInspector ? nil : 340)
        .frame(maxHeight: isInspector ? .infinity : nil, alignment: .top)
        .onAppear {
            title = task.title
            notes = task.notes ?? ""
            hasDue = task.dueDay != nil
            due = task.dueDay ?? store.today
        }
    }

    @State private var newTagName = ""
    @State private var addingTag = false

    private var tagMenu: some View {
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
            HStack {
                TextField("Nome da etiqueta", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit(createTag)
                Button("Criar", action: createTag)
            }
            .padding(10)
        }
    }

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let tag = store.createTag(name: name)
        store.toggleTag(tag, on: task)
        newTagName = ""
        addingTag = false
    }

    private func quickDate(_ label: String, _ offset: Int) -> some View {
        Button(label) {
            due = Calendar.current.adding(days: offset, to: store.today)
            hasDue = true
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func save() {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if newTitle != task.title || notes != (task.notes ?? "") {
            store.update(task, title: newTitle.isEmpty ? task.title : newTitle, notes: notes)
        }
        let newDue = hasDue ? Calendar.current.startOfDay(for: due) : nil
        if newDue != task.dueDay {
            // Espera o PATCH anterior não sobrescrever a data.
            let current = store.tasks[task.id] ?? task
            store.setDue(current, newDue)
        }
        onClose()
    }
}
