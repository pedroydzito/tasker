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

    /// Subtarefas (só no primeiro nível: o Google Tasks não tem netas).
    private var filhas: [TaskItem] { depth == 0 ? store.subtarefas(de: task.id) : [] }
    private var aberta: Bool { nav.subtarefasAbertas.contains(task.id) && !filhas.isEmpty }

    var body: some View {
        let filhas = self.filhas
        let aberta = self.aberta
        VStack(spacing: 0) {
            linha
            if aberta {
                ForEach(filhas) { filha in
                    TaskRow(task: filha, style: style, showDate: showDate, showList: false, depth: depth + 1)
                }
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(DS.curva, value: aberta)
    }

    private var linha: some View {
        Group {
            if style == .compact {
                linhaCompacta
            } else {
                // Cartão largo: data à direita, numa linha só. Estreito: data embaixo do nome.
                ViewThatFits(in: .horizontal) {
                    linhaLarga
                    linhaEmpilhada
                }
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
        .onHover { hovering = $0 && !RolagemSuave.shared.rolando }
        .animation(DS.curvaRapida, value: hovering)
        .animation(DS.curvaRapida, value: isSelected)
        .onTapGesture(perform: open)
        .pointerStyle(.link)
        .help("Abrir “\(task.displayTitle)”")
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

    /// "▸ 1/3": abre as subtarefas embaixo, sem entrar na tarefa.
    @ViewBuilder private var seta: some View {
        let filhas = self.filhas
        if !filhas.isEmpty {
            SetaSubtarefas(aberta: aberta, feitas: filhas.filter(\.isCompleted).count, total: filhas.count) {
                withAnimation(DS.curva) {
                    if aberta { nav.subtarefasAbertas.remove(task.id) } else { nav.subtarefasAbertas.insert(task.id) }
                }
            }
        }
    }

    private var circulo: some View {
        CheckCircle(color: store.color(forList: task.listID), checked: checked, size: 18, action: toggle)
    }

    private var titulo: some View {
        Text(task.displayTitle)
            .txt(style == .compact ? .sm : .md, .medium)
            .strikethrough(checked, color: DS.texto3)
            .foregroundStyle(checked ? DS.texto3 : DS.texto)
            .lineLimit(1)
    }

    /// Menu da barra: no dia de hoje mostra o horário (se tiver) no lugar de "Hoje".
    private var linhaCompacta: some View {
        HStack(spacing: DS.e3) {
            circulo
            titulo
            seta
            Spacer(minLength: DS.e2)
            if task.hasNotes {
                Image(systemName: "text.alignleft").font(.system(size: 10.5)).foregroundStyle(DS.texto3)
            }
            if showDate || store.horario(of: task) != nil, let texto = textoDaData(compacto: true) {
                Text(texto)
                    .txt(.xs, .medium)
                    .monospacedDigit()
                    .foregroundStyle((task.dueDay ?? .distantFuture) < store.today ? DS.perigoTexto : DS.texto3)
            }
        }
    }

    private var linhaLarga: some View {
        HStack(spacing: DS.e3) {
            circulo
            titulo.fixedSize()
            seta
            metadadosSemData.fixedSize()
            Spacer(minLength: 120)
            dataComHora
            if showList { ListChip(listID: task.listID) }
        }
    }

    private var linhaEmpilhada: some View {
        HStack(spacing: DS.e3) {
            circulo
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.e1) { titulo; seta }
                HStack(spacing: 6) {
                    dataComHora
                    metadadosSemData
                }
                .txt(.xs)
            }
            Spacer(minLength: DS.e2)
            if showList { ListChip(listID: task.listID) }
        }
    }

    /// Data (e horário) como metadado; atrasada em vermelho.
    @ViewBuilder private var dataComHora: some View {
        if let texto = textoDaData(compacto: false), showDate || store.horario(of: task) != nil {
            let atrasada = (task.dueDay ?? .distantFuture) < store.today
            HStack(spacing: DS.e1) {
                Image(systemName: atrasada ? "exclamationmark.circle" : (store.horario(of: task) != nil ? "clock" : "calendar"))
                    .font(.system(size: 10, weight: .semibold))
                Text(texto).monospacedDigit()
            }
            .txt(.xs, .medium)
            .foregroundStyle(atrasada ? DS.perigoTexto : DS.texto3)
        }
    }

    private func textoDaData(compacto: Bool) -> String? {
        let hora = store.horario(of: task)
        guard let day = task.dueDay else { return nil }
        let rotulo = DayLabel.short(day, today: store.today)
        if let hora {
            if !showDate || (compacto && day == store.today) { return hora }
            return "\(rotulo) · \(hora)"
        }
        return showDate ? rotulo : nil
    }

    /// Nota e etiquetas (sem a data).
    @ViewBuilder private var metadadosSemData: some View {
        let tags = store.tags(for: task)
        let note = task.notasVisiveis.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        if !note.isEmpty || !tags.isEmpty {
            HStack(spacing: 6) {
                if !note.isEmpty {
                    Image(systemName: "text.alignleft").font(.system(size: 9.5))
                    Text(note).lineLimit(1).frame(maxWidth: 220, alignment: .leading)
                }
                ForEach(tags) { TagChip(tag: $0) }
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

/// Seta à esquerda da tarefa-mãe: abre/fecha as subtarefas embaixo dela.
struct SetaSubtarefas: View {
    let aberta: Bool
    let feitas: Int
    let total: Int
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(aberta ? 90 : 0))
                Text("\(feitas)/\(total)").txt(.xs, .semibold).monospacedDigit()
            }
            .foregroundStyle(aberta ? DS.texto2 : DS.texto3)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Capsule().fill(DS.superficie2))
            .contentShape(Capsule())
        }
        .buttonStyle(SoAfunda(escala: 0.9))
        .help(aberta ? "Esconder subtarefas (\(feitas)/\(total))" : "Mostrar subtarefas (\(feitas)/\(total))")
    }
}
