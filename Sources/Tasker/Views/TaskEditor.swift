import SwiftUI

/// Rascunho de uma edição: nada vai para o Google até clicar em "Salvar".
struct RascunhoDeTarefa: Equatable {
    var title: String
    var notes: String
    var due: Date?
    var listID: String
    var tagIDs: [String]
    var horario: String?

    @MainActor
    init(_ task: TaskItem, store: TaskStore) {
        title = task.title
        notes = task.notasVisiveis
        due = task.dueDay
        listID = task.listID
        tagIDs = store.tags(for: task).map(\.id)
        horario = task.horario
    }

    @MainActor
    func aplicar(em task: TaskItem, store: TaskStore) {
        // O horário vai junto, como última linha das notas (o Google Tasks não guarda hora).
        store.save(task, title: title, notes: HorarioNasNotas.juntar(notes, due == nil ? nil : horario), due: due)
        if Set(tagIDs) != Set(store.tags(for: task).map(\.id)) { store.setTags(tagIDs, on: task) }
        if listID != task.listID { store.moveTask(store.tasks[task.id] ?? task, toList: listID) }
    }
}

/// Painel de detalhes da tarefa (janela principal). Só salva ao clicar em "Salvar".
struct TaskInspector: View {
    @Environment(TaskStore.self) private var store
    @Environment(Navigation.self) private var nav
    @Environment(Folhas.self) private var folhas
    let task: TaskItem
    let onClose: () -> Void

    @State private var rascunho: RascunhoDeTarefa?
    @State private var original: RascunhoDeTarefa?

    private var alterado: Bool { rascunho != nil && rascunho != original }

    var body: some View {
        let current = store.tasks[task.id] ?? task
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.e1) {
                Spacer()
                if let link = task.webViewLink.flatMap(URL.init(string:)) {
                    BotaoIcone(simbolo: "arrow.up.right", rotulo: "Abrir no Google") { NSWorkspace.shared.open(link) }
                }
                BotaoIcone(simbolo: "trash", rotulo: "Excluir tarefa") {
                    folhas.confirmar("Excluir tarefa", mensagem: "“\(current.displayTitle)” será excluída. Dá para desfazer logo depois.") {
                        store.delete(current)
                        onClose()
                    }
                }
                BotaoIcone(simbolo: "xmark", rotulo: "Fechar painel", acao: onClose)
            }
            .padding(.horizontal, DS.e5)
            .padding(.top, DS.e4)
            .padding(.bottom, DS.e3)

            if let binding = Binding($rascunho) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.e6) {
                        VStack(alignment: .leading, spacing: DS.e3) {
                            if let mae = current.parent.flatMap({ store.tasks[$0] }) {
                                Button { withAnimation(DS.curva) { nav.selectedTaskID = mae.id } } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.turn.left.up").font(.system(size: 10, weight: .semibold))
                                        Text("Subtarefa de \(mae.displayTitle)").txt(.xs, .medium).lineLimit(1)
                                    }
                                    .foregroundStyle(DS.texto3)
                                }
                                .buttonStyle(SoAfunda())
                                .help("Abrir a tarefa-mãe")
                            }
                            HStack(alignment: .firstTextBaseline, spacing: DS.e3) {
                                // Concluir: o mesmo círculo da lista de tarefas.
                                CheckCircle(color: store.color(forList: current.listID), checked: current.isCompleted, size: 22) {
                                    store.setCompleted(current, !current.isCompleted)
                                }
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                                TextField("Título", text: binding.title, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .display(.titulo)
                                    .strikethrough(current.isCompleted, color: DS.texto3)
                                    .foregroundStyle(current.isCompleted ? DS.texto3 : DS.texto)
                            }
                            PropriedadesDaTarefa(rascunho: binding)
                        }

                        VStack(alignment: .leading, spacing: DS.e2) {
                            Text("Descrição").rotulo()
                            TextEditor(text: binding.notes)
                                .txt(.md)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 90)
                                .overlay(alignment: .topLeading) {
                                    if binding.wrappedValue.notes.isEmpty {
                                        Text("Adicione detalhes, links ou anotações…")
                                            .txt(.md)
                                            .foregroundStyle(DS.texto3)
                                            .padding(.leading, 5)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .padding(DS.e3)
                                .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
                        }

                        // O Google Tasks só tem um nível de subtarefas.
                        if current.parent == nil {
                            Subtarefas(mae: current)
                        }
                    }
                    .padding(.horizontal, DS.e6)
                    .padding(.vertical, DS.e3)
                }
                .scrollIndicators(.never)
                .indicadorDeRolagem(fundo: DS.superficie)
            }

            if alterado {
                HStack(spacing: DS.e2) {
                    Text("Alterações não salvas").txt(.xs).foregroundStyle(DS.texto3)
                    Spacer()
                    Button("Descartar") { rascunho = original }.buttonStyle(.superficie)
                    Button("Salvar", action: salvar).buttonStyle(.primario).keyboardShortcut("s", modifiers: .command)
                }
                .padding(.horizontal, DS.e5)
                .padding(.vertical, DS.e3)
                .overlay(alignment: .top) { Rectangle().fill(DS.borda).frame(height: 1) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.curva, value: alterado)
        .background(DS.superficie)
        .onAppear {
            let inicial = RascunhoDeTarefa(task, store: store)
            rascunho = inicial
            original = inicial
        }
    }

    private func salvar() {
        guard let rascunho, let current = store.tasks[task.id] else { return }
        rascunho.aplicar(em: current, store: store)
        original = rascunho
    }
}

/// Lista (dropdown no lugar), data e etiquetas — tudo no rascunho.
struct PropriedadesDaTarefa: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    @Binding var rascunho: RascunhoDeTarefa
    @State private var listasAbertas = false
    @State private var dataAberta = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e2) {
            HStack(spacing: DS.e2) {
                Button {
                    withAnimation(DS.curva) { listasAbertas.toggle(); dataAberta = false }
                } label: {
                    HStack(spacing: 3) {
                        ListChip(listID: rascunho.listID, comSeta: true, aberta: listasAbertas)
                    }
                }
                .buttonStyle(SoAfunda(escala: 0.95))
                .help("Trocar a lista")

                Button {
                    withAnimation(DS.curva) { dataAberta.toggle(); listasAbertas = false }
                } label: {
                    Chip(rascunho.due.map { DayLabel.comAtraso($0, today: store.today) + (rascunho.horario.map { " · \($0)" } ?? "") } ?? "Sem data",
                         cor: rascunho.due.map { $0 < store.today ? DS.perigoTexto : DS.texto2 }) {
                        Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(SoAfunda(escala: 0.94))

                ForEach(store.tags.filter { rascunho.tagIDs.contains($0.id) }) { tag in
                    Button { rascunho.tagIDs.removeAll { $0 == tag.id } } label: {
                        Chip("#\(tag.name)", cor: Color(hex: tag.colorHex))
                    }
                    .buttonStyle(SoAfunda(escala: 0.94))
                    .help("Tirar a etiqueta")
                }

                Menu {
                    ForEach(store.tags) { tag in
                        let has = rascunho.tagIDs.contains(tag.id)
                        Button {
                            if has { rascunho.tagIDs.removeAll { $0 == tag.id } } else { rascunho.tagIDs.append(tag.id) }
                        } label: {
                            if has { Label(tag.name, systemImage: "checkmark") } else { Text(tag.name) }
                        }
                    }
                    if !store.tags.isEmpty { Divider() }
                    Button("Nova etiqueta…") {
                        folhas.abrir("Nova etiqueta") { CriadorDeEtiqueta() }
                    }
                } label: {
                    Image(systemName: "number").font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .animacaoDeClique()
                .help("Etiquetas (só no Tasker)")
            }

            if listasAbertas {
                DropdownDeListas(atual: rascunho.listID) { id in
                    rascunho.listID = id
                    withAnimation(DS.curva) { listasAbertas = false }
                }
                .frame(maxWidth: 300)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
            if dataAberta {
                SeletorDeDataEmbutido(due: $rascunho.due, horario: $rascunho.horario) {
                    withAnimation(DS.curva) { dataAberta = false }
                }
                    .frame(maxWidth: 320)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
    }
}

/// Seletor de data no lugar (sem abrir outra tela): atalhos + calendário do mês.
struct SeletorDeDataEmbutido: View {
    @Environment(TaskStore.self) private var store
    @Binding var due: Date?
    @Binding var horario: String?
    let fechar: () -> Void
    @State private var mes = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var textoHora = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            HStack(spacing: DS.e1) {
                atalho("Hoje", 0)
                atalho("Amanhã", 1)
                Button("Sem data") { due = nil; fechar() }.buttonStyle(Botao(variante: .fantasma))
            }
            CalendarioMes(mes: $mes, selecionado: due, hoje: store.today,
                          ocupado: { !store.tasks(on: $0).isEmpty }) { dia in
                due = dia
            }
            // Horário opcional (fica no Tasker; o Google Tasks só guarda a data).
            HStack(spacing: DS.e2) {
                Image(systemName: "clock").font(.system(size: 12, weight: .medium)).foregroundStyle(DS.texto3)
                TextField("Sem horário", text: $textoHora)
                    .textFieldStyle(.plain)
                    .txt(.sm, .medium)
                    .monospacedDigit()
                    .frame(width: 84)
                    .padding(.horizontal, DS.e2)
                    .frame(height: 30)
                    .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioP, style: .continuous))
                    .onSubmit(aplicarHora)
                    .onChange(of: textoHora) { _, _ in aplicarHora() }
                ForEach(["09:00", "12:00", "18:00"], id: \.self) { h in
                    Button(h) { textoHora = h }.buttonStyle(Botao(variante: horario == h ? .primario : .superficie))
                }
                if horario != nil {
                    BotaoIcone(simbolo: "xmark", rotulo: "Tirar o horário", tamanho: 24, tamanhoIcone: 10) {
                        textoHora = ""
                        horario = nil
                    }
                }
            }
            .disabled(due == nil)
            .opacity(due == nil ? 0.5 : 1)
            HStack {
                Spacer()
                Button("Pronto", action: fechar).buttonStyle(.superficie)
            }
        }
        .padding(DS.e3)
        .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).strokeBorder(DS.borda))
        .sombra()
        .onAppear {
            if let due { mes = Calendar.current.dateInterval(of: .month, for: due)?.start ?? mes }
            textoHora = horario ?? ""
        }
    }

    /// Aceita "9", "930", "9:30", "09h30".
    private func aplicarHora() {
        let digitos = textoHora.filter(\.isNumber)
        guard !digitos.isEmpty else { horario = nil; return }
        var h = 0, m = 0
        switch digitos.count {
        case 1, 2: h = Int(digitos) ?? 0
        case 3: h = Int(digitos.prefix(1)) ?? 0; m = Int(digitos.suffix(2)) ?? 0
        default: h = Int(digitos.prefix(2)) ?? 0; m = Int(digitos.dropFirst(2).prefix(2)) ?? 0
        }
        guard h < 24, m < 60 else { return }
        horario = String(format: "%02d:%02d", h, m)
    }

    private func atalho(_ rotulo: String, _ dias: Int) -> some View {
        let dia = Calendar.current.adding(days: dias, to: store.today)
        return Button(rotulo) { due = dia; fechar() }
            .buttonStyle(Botao(variante: due == dia ? .primario : .superficie))
    }
}

/// Editor rápido (folha), usado no menu da barra. Só salva ao clicar em "Salvar".
struct EditorRapido: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    let task: TaskItem
    @State private var rascunho: RascunhoDeTarefa?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e4) {
            if let binding = Binding($rascunho) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Título").rotulo()
                    TextField("Título", text: binding.title).campo().onSubmit(save)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Descrição").rotulo()
                    TextField("Detalhes", text: binding.notes, axis: .vertical).lineLimit(2...6).campo()
                }
                PropriedadesDaTarefa(rascunho: binding)
            }
            RodapeFolha {
                Button("Excluir") {
                    let alvo = store.tasks[task.id] ?? task
                    folhas.confirmar("Excluir tarefa", mensagem: "“\(alvo.displayTitle)” será excluída. Dá para desfazer logo depois.") {
                        store.delete(alvo)
                    }
                }
                .buttonStyle(Botao(variante: .fantasma))
                Spacer()
                Button("Cancelar") { folhas.fechar() }.buttonStyle(.superficie)
                Button("Salvar", action: save).buttonStyle(.primario).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { rascunho = RascunhoDeTarefa(task, store: store) }
    }

    private func save() {
        guard let rascunho else { return }
        rascunho.aplicar(em: store.tasks[task.id] ?? task, store: store)
        withAnimation(DS.curvaSaida) { folhas.fechar() }
    }
}

/// Subtarefas no detalhe: concluir, abrir e adicionar na hora (sincronizam com o Google Tasks).
struct Subtarefas: View {
    @Environment(TaskStore.self) private var store
    @Environment(Navigation.self) private var nav
    let mae: TaskItem
    @State private var nova = ""
    @FocusState private var foco: Bool

    var body: some View {
        let filhas = store.subtarefas(de: mae.id)
        let feitas = filhas.filter(\.isCompleted).count
        VStack(alignment: .leading, spacing: DS.e2) {
            HStack {
                Text("Subtarefas").rotulo()
                if !filhas.isEmpty {
                    Text("\(feitas)/\(filhas.count)").txt(.xs, .semibold).foregroundStyle(DS.texto3)
                }
            }
            if !filhas.isEmpty {
                ProgressView(value: Double(feitas), total: Double(max(filhas.count, 1)))
                    .tint(store.color(forList: mae.listID))
                    .animation(DS.curva, value: feitas)
            }
            VStack(spacing: 1) {
                ForEach(filhas) { filha in
                    LinhaSubtarefa(tarefa: filha, cor: store.color(forList: mae.listID)) {
                        withAnimation(DS.curva) { nav.selectedTaskID = filha.id }
                    }
                }
                HStack(spacing: DS.e3) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(foco ? DS.acento : DS.texto3)
                        .frame(width: 18)
                    TextField("Adicionar subtarefa", text: $nova)
                        .textFieldStyle(.plain)
                        .txt(.sm)
                        .focused($foco)
                        .onSubmit(adicionar)
                }
                .padding(.horizontal, DS.e3)
                .padding(.vertical, 9)
            }
            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
        }
        .animation(DS.curva, value: filhas.map(\.id))
    }

    private func adicionar() {
        store.addSubtask(title: nova, parent: mae)
        nova = ""
        foco = true
    }
}

private struct LinhaSubtarefa: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    let tarefa: TaskItem
    let cor: Color
    let abrir: () -> Void
    @State private var sobre = false

    var body: some View {
        HStack(spacing: DS.e3) {
            CheckCircle(color: cor, checked: tarefa.isCompleted, size: 18) {
                store.setCompleted(tarefa, !tarefa.isCompleted)
            }
            Button(action: abrir) {
                HStack {
                    Text(tarefa.displayTitle)
                        .txt(.sm)
                        .strikethrough(tarefa.isCompleted, color: DS.texto3)
                        .foregroundStyle(tarefa.isCompleted ? DS.texto3 : DS.texto)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SoAfunda(escala: 0.99))
            .disabled(tarefa.isLocal)
            if sobre && !tarefa.isLocal {
                BotaoIcone(simbolo: "trash", rotulo: "Excluir subtarefa") {
                    folhas.confirmar("Excluir subtarefa", mensagem: "“\(tarefa.displayTitle)” será excluída. Dá para desfazer logo depois.") {
                        store.delete(tarefa)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.e3)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(sobre ? DS.veuHover : .clear))
        .onHover { sobre = $0 && !RolagemSuave.shared.rolando }
        .animation(DS.curvaRapida, value: sobre)
    }
}
