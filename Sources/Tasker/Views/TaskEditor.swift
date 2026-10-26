import SwiftUI

/// Painel de detalhes da tarefa (janela principal). Salva sozinho.
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
        let current = store.tasks[task.id] ?? task
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.e1) {
                Button {
                    store.setCompleted(current, !current.isCompleted)
                } label: {
                    Label(current.isCompleted ? "Reabrir" : "Concluir",
                          systemImage: current.isCompleted ? "arrow.uturn.backward" : "checkmark")
                }
                .buttonStyle(Botao(variante: current.isCompleted ? .superficie : .primario))
                Spacer()
                if let link = task.webViewLink.flatMap(URL.init(string:)) {
                    BotaoIcone(simbolo: "arrow.up.right", rotulo: "Abrir no Google") { NSWorkspace.shared.open(link) }
                }
                BotaoIcone(simbolo: "trash", rotulo: "Excluir tarefa") {
                    store.delete(current)
                    onClose()
                }
                BotaoIcone(simbolo: "xmark", rotulo: "Fechar painel", acao: onClose)
            }
            .padding(.horizontal, DS.e5)
            .padding(.top, DS.e4)
            .padding(.bottom, DS.e3)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.e6) {
                    VStack(alignment: .leading, spacing: DS.e3) {
                        TextField("título", text: $title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .display(.titulo)
                            .foregroundStyle(DS.texto)
                        PropriedadesDaTarefa(task: current, due: $due)
                    }

                    VStack(alignment: .leading, spacing: DS.e2) {
                        Text("descrição").rotulo()
                        TextEditor(text: $notes)
                            .txt(.md)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .padding(DS.e3)
                            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
                    }

                    Label("salvo automaticamente no Google Tasks", systemImage: "checkmark.icloud")
                        .txt(.xs)
                        .foregroundStyle(DS.texto3)
                }
                .padding(.horizontal, DS.e6)
                .padding(.vertical, DS.e3)
            }
            .scrollIndicators(.never)
        }
        .background(DS.superficie)
        .task(id: "\(title)\u{0}\(notes)\u{0}\(due?.timeIntervalSince1970 ?? 0)") {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            persist()
        }
        .onDisappear(perform: persist)
    }

    private func persist() {
        guard let current = store.tasks[task.id] else { return }
        store.save(current, title: title, notes: notes, due: due)
    }
}

/// Linha de propriedades: chip da lista (com foto), data e etiquetas.
struct PropriedadesDaTarefa: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    let task: TaskItem
    @Binding var due: Date?

    var body: some View {
        HStack(spacing: DS.e2) {
            ListChip(listID: task.listID)

            Button {
                let inicial = due
                folhas.abrir("quando?") {
                    SeletorDeData(inicial: inicial) { due = $0 }
                }
            } label: {
                Chip(due.map { DayLabel.short($0, today: store.today).lowercased() } ?? "sem data",
                     cor: due.map { $0 < store.today ? DS.acentoTexto : DS.texto2 }) {
                    Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(SoAfunda(escala: 0.94))

            ForEach(store.tags(for: task)) { tag in
                Button { store.toggleTag(tag, on: task) } label: {
                    Chip("#\(tag.name)", cor: Color(hex: tag.colorHex))
                }
                .buttonStyle(SoAfunda(escala: 0.94))
                .help("Remover etiqueta")
            }

            Menu {
                ForEach(store.tags) { tag in
                    let has = store.tags(for: task).contains(tag)
                    Button { store.toggleTag(tag, on: task) } label: {
                        if has { Label(tag.name, systemImage: "checkmark") } else { Text(tag.name) }
                    }
                }
                if !store.tags.isEmpty { Divider() }
                Button("Nova etiqueta…") {
                    let current = task
                    folhas.abrir("nova etiqueta") {
                        CriadorDeEtiqueta { tag in store.toggleTag(tag, on: current) }
                    }
                }
            } label: {
                Image(systemName: "number").font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Etiquetas (só no Tasker)")
        }
    }
}

/// Editor rápido (folha), usado no menu da barra.
struct EditorRapido: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    let task: TaskItem

    @State private var title: String
    @State private var notes: String
    @State private var due: Date?

    init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes ?? "")
        _due = State(initialValue: task.dueDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e4) {
            VStack(alignment: .leading, spacing: 6) {
                Text("título").rotulo()
                TextField("título", text: $title).campo().onSubmit(save)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("descrição").rotulo()
                TextField("detalhes", text: $notes, axis: .vertical).lineLimit(2...6).campo()
            }
            PropriedadesDaTarefa(task: store.tasks[task.id] ?? task, due: $due)
            RodapeFolha {
                Button("Excluir") {
                    store.delete(task)
                    folhas.fechar()
                }
                .buttonStyle(Botao(variante: .fantasma))
                Spacer()
                Button("Cancelar") { folhas.fechar() }.buttonStyle(.superficie)
                Button("Salvar", action: save).buttonStyle(.primario).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func save() {
        store.save(store.tasks[task.id] ?? task, title: title, notes: notes, due: due)
        withAnimation(DS.curvaSaida) { folhas.fechar() }
    }
}
