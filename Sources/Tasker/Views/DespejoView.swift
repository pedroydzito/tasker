import SwiftUI

/// Campo do despejo: Enter guarda e o campo continua pronto para o próximo.
/// Texto colado com várias linhas vira um item por linha.
struct CampoDespejo: View {
    enum Estilo { case compacto, inline, large }

    @Environment(Caderno.self) private var caderno
    var style: Estilo = .inline
    var onEscape: (() -> Void)?

    @State private var texto = ""
    @State private var confirmacao: String?
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.e3) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: style == .large ? 15 : 13, weight: .semibold))
                    .foregroundStyle(foco ? DS.acento : DS.texto3)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                TextField(placeholder, text: $texto, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .txt(style == .large ? .lg : .md)
                    .foregroundStyle(DS.texto)
                    .focused($foco)
                    .onSubmit(guardar)
                    .onExitCommand {
                        if texto.isEmpty, let onEscape { onEscape() } else { texto = "" }
                    }
                    .accessibilityIdentifier("campoDespejo")
            }
            .padding(.leading, DS.e4)
            .padding(.trailing, DS.e3)
            .padding(.vertical, style == .large ? 15 : 11)
            .background {
                if style != .large {
                    RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(DS.superficie2)
                }
            }

            Group {
                if let confirmacao {
                    Label(confirmacao, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DS.sucesso)
                } else if style != .compacto {
                    Text("Enter guarda e já deixa pronto para o próximo. Sem data, sem lista — organize depois.")
                        .foregroundStyle(DS.texto3)
                }
            }
            .txt(.xs)
            .padding(.horizontal, DS.e3)
            .transition(.opacity)
        }
        .animation(DS.curvaRapida, value: confirmacao)
        .onAppear {
            if style == .large { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { foco = true } }
        }
    }

    private var placeholder: String {
        switch style {
        case .large: "O que está ocupando a sua cabeça?"
        case .compacto: "Despejar algo…"
        case .inline: "Escreva o que vier — uma coisa por vez, ou cole uma lista"
        }
    }

    private func guardar() {
        let total = caderno.capturar(texto)
        guard total > 0 else { return }
        texto = ""
        foco = true
        let mensagem = total == 1 ? "Guardado no despejo" : "\(total) itens guardados no despejo"
        confirmacao = mensagem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if confirmacao == mensagem { confirmacao = nil }
        }
    }
}

/// Tela do despejo: captura no topo, itens embaixo e a triagem um a um.
struct DespejoView: View {
    @Environment(Caderno.self) private var caderno
    /// Abre direto na triagem (usado nas capturas de tela).
    var abrirTriagem = false
    @State private var triando: String??

    var body: some View {
        PageScaffold(rotulo: "Tire da cabeça. Organize depois.", title: "Despejo") {
            if let alvo = triando {
                Triagem(comecarPor: alvo) { withAnimation(DS.curva) { triando = nil } }
                    .transition(.opacity.combined(with: .offset(y: 8)))
            } else {
                VStack(alignment: .leading, spacing: DS.e5) {
                    CampoDespejo(style: .inline)
                        .padding(DS.e2)
                        .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))

                    if caderno.despejo.isEmpty {
                        EstadoVazio(icone: "tray", titulo: "Cabeça leve",
                                    descricao: "Escreva aqui tudo o que estiver ocupando espaço. Depois, com calma, decida o que vira tarefa, nota ou sai da lista.")
                            .padding(.top, DS.e6)
                    } else {
                        HStack {
                            Text(caderno.despejo.count == 1 ? "1 item para organizar" : "\(caderno.despejo.count) itens para organizar")
                                .txt(.sm, .medium)
                                .foregroundStyle(DS.texto3)
                            Spacer()
                            Button {
                                withAnimation(DS.curva) { triando = .some(nil) }
                            } label: {
                                Label("Organizar um a um", systemImage: "rectangle.stack")
                            }
                            .buttonStyle(Botao(variante: .primario, tamanho: .m))
                            .accessibilityIdentifier("organizar")
                        }
                        CartaoDeLinhas(recuoDoFio: DS.e4) {
                            // Mais recentes no topo (a triagem começa pelos mais antigos).
                            ForEach(caderno.despejo.reversed()) { item in
                                LinhaDespejo(item: item) {
                                    withAnimation(DS.curva) { triando = .some(item.id) }
                                }
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(DS.curva, value: caderno.despejo.map(\.id))
        .onAppear { if abrirTriagem { triando = .some(nil) } }
    }
}

/// Linha do despejo: clique para editar; no hover, organizar ou soltar.
struct LinhaDespejo: View {
    @Environment(Caderno.self) private var caderno
    let item: ItemDespejo
    var compacta = false
    let organizar: () -> Void

    @State private var sobre = false
    @State private var editando = false
    @State private var rascunho = ""
    @FocusState private var foco: Bool

    var body: some View {
        HStack(spacing: DS.e3) {
            Circle().fill(DS.texto3.opacity(0.5)).frame(width: 5, height: 5)
            if editando {
                TextField("", text: $rascunho, axis: .vertical)
                    .textFieldStyle(.plain)
                    .txt(compacta ? .sm : .md)
                    .focused($foco)
                    .onSubmit(salvar)
                    .onExitCommand { editando = false }
                    .onChange(of: foco) { _, focado in if !focado { salvar() } }
            } else {
                Text(item.texto)
                    .txt(compacta ? .sm : .md)
                    .foregroundStyle(DS.texto)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        rascunho = item.texto
                        editando = true
                        DispatchQueue.main.async { foco = true }
                    }
                    .pointerStyle(.link)
                    .help("Clique para editar")
            }
            if sobre && !editando {
                HStack(spacing: 2) {
                    BotaoIcone(simbolo: "arrow.right.circle", rotulo: "Organizar este", tamanho: 26, tamanhoIcone: 13, acao: organizar)
                    BotaoIcone(simbolo: "xmark", rotulo: "Soltar (tirar da lista)", tamanho: 26, tamanhoIcone: 12) {
                        withAnimation(DS.curva) { caderno.soltar(item.id) }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.e3)
        .padding(.vertical, compacta ? 6 : 9)
        .frame(minHeight: compacta ? 32 : 40)
        .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(sobre ? DS.veuHover : .clear))
        .onHover { sobre = $0 && !RolagemSuave.shared.rolando }
        .animation(DS.curvaRapida, value: sobre)
    }

    private func salvar() {
        guard editando else { return }
        editando = false
        caderno.editar(item.id, texto: rascunho)
    }
}

/// Triagem: um item por vez, com quatro saídas — tarefa, nota, pular ou soltar.
struct Triagem: View {
    @Environment(Caderno.self) private var caderno
    @Environment(TaskStore.self) private var store
    @Environment(Navigation.self) private var nav
    let comecarPor: String?
    let fechar: () -> Void

    @State private var atualID: String?
    @State private var pulados: Set<String> = []
    @State private var organizados = 0
    @State private var texto = ""
    @State private var virandoTarefa = false
    @State private var listID: String?
    @State private var due: Date?
    @State private var horario: String?
    @State private var listasAbertas = false
    @State private var dataAberta = false

    private var fila: [ItemDespejo] { caderno.despejo.filter { !pulados.contains($0.id) } }
    private var atual: ItemDespejo? { atualID.flatMap { id in caderno.despejo.first { $0.id == id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e5) {
            HStack {
                Button(action: fechar) {
                    Label("Voltar ao despejo", systemImage: "chevron.left")
                }
                .buttonStyle(Botao(variante: .fantasma))
                Spacer()
                if atual != nil {
                    Text("\(organizados + 1) de \(organizados + fila.count)")
                        .txt(.sm, .semibold).monospacedDigit().foregroundStyle(DS.texto3)
                }
            }

            if let item = atual {
                cartao(item)
                    .id(item.id)
                    .transition(.asymmetric(insertion: .offset(x: 24).combined(with: .opacity), removal: .opacity))
            } else {
                VStack(spacing: DS.e4) {
                    EstadoVazio(icone: "checkmark.seal", titulo: pulados.isEmpty ? "Tudo organizado" : "Fim da fila",
                                descricao: pulados.isEmpty
                                    ? "O despejo está vazio. Cabeça leve."
                                    : "Você pulou \(pulados.count) \(pulados.count == 1 ? "item" : "itens"). Eles continuam no despejo para outra hora.")
                    Button("Voltar ao despejo", action: fechar).buttonStyle(Botao(variante: .superficie, tamanho: .m))
                }
                .padding(.top, DS.e6)
            }
        }
        .animation(DS.curva, value: atualID)
        .onAppear { carregar(comecarPor ?? fila.first?.id) }
    }

    private func cartao(_ item: ItemDespejo) -> some View {
        VStack(alignment: .leading, spacing: DS.e5) {
            VStack(alignment: .leading, spacing: DS.e2) {
                Text("Despejado \(item.criado.formatted(.relative(presentation: .named)))").rotulo()
                TextField("", text: $texto, axis: .vertical)
                    .textFieldStyle(.plain)
                    .display(.titulo)
                    .foregroundStyle(DS.texto)
                    .lineLimit(1...6)
                    .accessibilityIdentifier("textoTriagem")
            }

            if virandoTarefa {
                opcoesDeTarefa
                    .transition(.opacity.combined(with: .offset(y: -6)))
            } else {
                Text("O que fazer com isto?").txt(.sm, .medium).foregroundStyle(DS.texto3)
                HStack(spacing: DS.e2) {
                    escolha("Virar tarefa", "checklist", "1") {
                        withAnimation(DS.curva) { virandoTarefa = true }
                    }
                    escolha("Virar nota", "note.text", "2") { virarNota(item) }
                    escolha("Pular", "forward", "3") { pular(item) }
                    escolha("Soltar", "xmark.circle", "4") { soltar(item) }
                }
            }
        }
        .padding(DS.e6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
        .animation(DS.curva, value: virandoTarefa)
        .animation(DS.curva, value: listasAbertas)
        .animation(DS.curva, value: dataAberta)
    }

    private func escolha(_ titulo: String, _ simbolo: String, _ tecla: KeyEquivalent, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            VStack(spacing: DS.e2) {
                Image(systemName: simbolo).font(.system(size: 18, weight: .medium))
                Text(titulo).txt(.sm, .semibold)
            }
            .foregroundStyle(DS.texto)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.e4)
            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressionavel(raio: DS.raioM, escala: 0.97))
        .keyboardShortcut(tecla, modifiers: .command)
        .help("\(titulo) (⌘\(String(tecla.character)))")
    }

    private var opcoesDeTarefa: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            HStack(spacing: DS.e2) {
                if let id = listID ?? store.defaultList?.id {
                    Button {
                        withAnimation(DS.curva) { listasAbertas.toggle(); dataAberta = false }
                    } label: {
                        ListChip(listID: id, comSeta: true, aberta: listasAbertas)
                    }
                    .buttonStyle(SoAfunda(escala: 0.95))
                }
                Button {
                    withAnimation(DS.curva) { dataAberta.toggle(); listasAbertas = false }
                } label: {
                    Chip((due.map { DayLabel.short($0, today: store.today) } ?? "Sem data") + (horario.map { " · \($0)" } ?? "")) {
                        Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(SoAfunda(escala: 0.95))
                ForEach([("Hoje", 0), ("Amanhã", 1)], id: \.1) { rotulo, dias in
                    let dia = Calendar.current.adding(days: dias, to: store.today)
                    Button(rotulo) { due = dia }
                        .buttonStyle(Botao(variante: due == dia ? .primario : .superficie))
                }
                Button("Sem data") { due = nil; horario = nil }
                    .buttonStyle(Botao(variante: due == nil ? .primario : .superficie))
            }
            if listasAbertas {
                DropdownDeListas(atual: listID ?? store.defaultList?.id) { id in
                    listID = id
                    withAnimation(DS.curva) { listasAbertas = false }
                }
                .frame(maxWidth: 300)
            }
            if dataAberta {
                SeletorDeDataEmbutido(due: $due, horario: $horario) {
                    withAnimation(DS.curva) { dataAberta = false }
                }
                .frame(maxWidth: 320)
            }
            HStack {
                Button("Cancelar") { withAnimation(DS.curva) { virandoTarefa = false } }
                    .buttonStyle(.superficie)
                Spacer()
                Button {
                    if let item = atual { virarTarefa(item) }
                } label: {
                    Label("Criar tarefa", systemImage: "checkmark")
                }
                .buttonStyle(Botao(variante: .primario, tamanho: .m))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("criarTarefaTriagem")
            }
        }
    }

    // MARK: Ações

    /// Prepara o item: lê "amanhã", "~lista" e "#etiqueta" do texto, como no campo de nova tarefa.
    private func carregar(_ id: String?) {
        atualID = id
        virandoTarefa = false
        listasAbertas = false
        dataAberta = false
        horario = nil
        guard let id, let item = caderno.despejo.first(where: { $0.id == id }) else { return }
        let lido = QuickAddParser.parse(item.texto, lists: store.lists, today: store.today)
        texto = item.texto
        listID = lido.listID
        due = lido.due ?? nil
    }

    private func proximo() {
        carregar(fila.first?.id)
    }

    private func virarTarefa(_ item: ItemDespejo) {
        let lido = QuickAddParser.parse(texto, lists: store.lists, today: store.today)
        let titulo = lido.title.trimmingCharacters(in: .whitespaces).isEmpty ? texto : lido.title
        caderno.virarTarefa(item.id, titulo: titulo, listID: listID ?? lido.listID, due: due,
                            horario: horario, tagIDs: store.resolveTags(named: lido.tagNames))
        organizados += 1
        proximo()
    }

    private func virarNota(_ item: ItemDespejo) {
        if texto != item.texto { caderno.editar(item.id, texto: texto) }
        caderno.virarNota(item.id)
        organizados += 1
        proximo()
    }

    private func pular(_ item: ItemDespejo) {
        if texto != item.texto { caderno.editar(item.id, texto: texto) }
        pulados.insert(item.id)
        proximo()
    }

    private func soltar(_ item: ItemDespejo) {
        caderno.soltar(item.id)
        organizados += 1
        proximo()
    }
}
