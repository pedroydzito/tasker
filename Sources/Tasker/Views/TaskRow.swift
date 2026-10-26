import SwiftUI

/// Linha de tarefa (padrão "linha de lista" do design system):
/// [círculo] título / metadado (data · nota · #etiquetas)  ……  [chip da lista]
struct TaskRow: View {
    enum Style { case compact, full }

    @Environment(TaskStore.self) private var store
    @Environment(Navigation.self) private var nav
    @Environment(Folhas.self) private var folhas
    let task: TaskItem
    var style: Style = .full
    var showDate = true
    var showList = true
    var depth = 0

    @State private var checking = false
    @State private var hovering = false
    @State private var pressed = false

    private var checked: Bool { task.isCompleted || checking }
    private var isSelected: Bool { style == .full && nav.selectedTaskID == task.id }

    var body: some View {
        HStack(spacing: DS.e3) {
            CheckCircle(color: store.color(forList: task.listID), checked: checked, size: 18, action: toggle)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayTitle)
                    .txt(style == .compact ? .sm : .md, .medium)
                    .strikethrough(checked, color: DS.texto3)
                    .foregroundStyle(checked ? DS.texto3 : DS.texto)
                    .lineLimit(1)
                if style == .full { metadata }
            }

            Spacer(minLength: DS.e2)

            if style == .compact {
                if task.hasNotes {
                    Image(systemName: "text.alignleft").font(.system(size: 10.5)).foregroundStyle(DS.texto3)
                }
                if showDate, let day = task.dueDay {
                    Text(DayLabel.short(day, today: store.today))
                        .txt(.xs, .medium)
                        .foregroundStyle(day < store.today ? DS.perigoTexto : DS.texto3)
                }
            } else if showList {
                ListChip(listID: task.listID)
            }
        }
        .padding(.leading, 12 + CGFloat(depth) * 26)
        .padding(.trailing, 12)
        .padding(.vertical, style == .compact ? 8 : 9)
        .background(
            RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                .fill(isSelected ? DS.superficie2 : (pressed ? DS.veuAtivo : (hovering ? DS.veuHover : .clear)))
        )
        .scaleEffect(pressed ? 0.995 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(DS.curvaRapida, value: hovering)
        .animation(DS.curvaRapida, value: isSelected)
        .onTapGesture(perform: open)
        .pointerStyle(.link)
        // Arraste até uma lista da barra lateral para mudar a tarefa de lista.
        .draggable("tarefa:\(task.id)") {
            HStack(spacing: DS.e2) {
                Circle().strokeBorder(store.color(forList: task.listID), lineWidth: 1.75).frame(width: 14, height: 14)
                Text(task.displayTitle).txt(.sm, .medium).lineLimit(1)
            }
            .padding(.horizontal, DS.e3)
            .padding(.vertical, DS.e2)
            .background(DS.superficie, in: Capsule())
        }
        .contextMenu { contextMenu }
        .opacity(task.isLocal ? 0.55 : 1)
    }

    /// Metadado numa linha, separado por "·": data, primeira linha da nota, etiquetas.
    @ViewBuilder private var metadata: some View {
        let tags = store.tags(for: task)
        let note = (task.notes ?? "").components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        let hasDate = showDate && task.dueDay != nil
        if hasDate || !note.isEmpty || !tags.isEmpty {
            HStack(spacing: 6) {
                if showDate, let day = task.dueDay { DueLabel(day: day, today: store.today) }
                if !note.isEmpty {
                    if hasDate { Text("·") }
                    Text(note).lineLimit(1).frame(maxWidth: 280, alignment: .leading)
                }
                ForEach(tags) { tag in
                    if hasDate || !note.isEmpty || tag.id != tags.first?.id { Text("·") }
                    TagChip(tag: tag)
                }
            }
            .txt(.xs)
            .foregroundStyle(DS.texto3)
        }
    }

    private func open() {
        if style == .full {
            withAnimation(DS.curva) { nav.selectedTaskID = task.id }
        } else {
            let current = task
            folhas.abrir("Editar tarefa") { EditorRapido(task: current) }
        }
    }

    private func toggle() {
        if task.isCompleted {
            store.setCompleted(task, false)
            return
        }
        withAnimation(DS.curvaRapida) { checking = true }
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(DS.curva) { store.setCompleted(task, true) }
            checking = false
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Button(task.isCompleted ? "Reabrir" : "Concluir") { store.setCompleted(task, !task.isCompleted) }
        Divider()
        Button("Para hoje") { store.setDue(task, store.today) }
        Button("Para amanhã") { store.setDue(task, Calendar.current.adding(days: 1, to: store.today)) }
        Button("Para a próxima semana") { store.setDue(task, Calendar.current.adding(days: 7, to: store.today)) }
        Button("Tirar a data") { store.setDue(task, nil) }
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
        Button("Excluir…", role: .destructive) {
            let alvo = task
            folhas.confirmar("Excluir tarefa", mensagem: "“\(alvo.displayTitle)” será excluída. Dá para desfazer logo depois.") {
                store.delete(alvo)
            }
        }
    }
}
