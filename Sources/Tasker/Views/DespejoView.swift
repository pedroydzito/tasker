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
                Image(systemName: "brain.head.profile")
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

/// Tela do despejo: captura no topo e os itens embaixo. Cada item se organiza no próprio card;
/// "Organizar um a um" destaca um card por vez, do mais antigo ao mais novo.
struct DespejoView: View {
    @Environment(Caderno.self) private var caderno
    /// Já começa organizando um a um (usado nas capturas de tela).
    var abrirTriagem = false

    /// Card aberto (com as escolhas à mostra).
    @State private var aberto: String?
    /// Organizando um a um: ao resolver um card, abre o próximo.
    @State private var emSequencia = false
    @State private var pulados: Set<String> = []

    var body: some View {
        PageScaffold(rotulo: "Tire da cabeça. Organize depois.", title: "Despejo") {
            VStack(alignment: .leading, spacing: DS.e5) {
                CampoDespejo(style: .inline)
                    .padding(DS.e2)
                    .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))

                if caderno.despejo.isEmpty {
                    EstadoVazio(icone: "brain.head.profile", titulo: "Cabeça leve",
                                descricao: "Escreva aqui tudo o que estiver ocupando espaço. Depois, com calma, decida o que vira tarefa, nota ou sai da lista.")
                        .padding(.top, DS.e6)
                } else {
                    barra
                    VStack(spacing: DS.e2) {
                        // Mais antigos primeiro: é a ordem em que se organiza.
                        ForEach(caderno.despejo) { item in
                            CartaoDespejo(item: item, aberto: aberto == item.id, emSequencia: emSequencia,
                                          abrir: { withAnimation(DS.curva) { aberto = aberto == item.id ? nil : item.id } },
                                          resolvido: { proximo(depois: item.id) },
                                          pular: { pulados.insert(item.id); proximo(depois: item.id) })
                                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)),
                                                        removal: .opacity.combined(with: .scale(scale: 0.97))))
                        }
                    }
                }
            }
        }
        .animation(DS.curva, value: caderno.despejo.map(\.id))
        .onAppear { if abrirTriagem { comecar() } }
    }

    private var barra: some View {
        HStack {
            Text(caderno.despejo.count == 1 ? "1 item para organizar" : "\(caderno.despejo.count) itens para organizar")
                .txt(.sm, .medium)
                .foregroundStyle(DS.texto3)
            Spacer()
            if emSequencia {
                Button("Parar de organizar") { parar() }
                    .buttonStyle(Botao(variante: .superficie, tamanho: .m))
                    .help("Sai do modo um a um; os itens ficam como estão")
            } else {
                Button(action: comecar) {
                    Label("Organizar um a um", systemImage: "rectangle.stack")
                }
                .buttonStyle(Botao(variante: .primario, tamanho: .m))
                .help("Abre um item por vez, do mais antigo ao mais novo")
                .accessibilityIdentifier("organizar")
            }
        }
    }

    private func comecar() {
        pulados = []
        emSequencia = true
        withAnimation(DS.curva) { aberto = caderno.despejo.first?.id }
    }

    private func parar() {
        withAnimation(DS.curva) {
            emSequencia = false
            aberto = nil
        }
    }

    /// Depois de resolver (ou pular) um card: abre o próximo da fila, se estiver organizando um a um.
    private func proximo(depois id: String) {
        guard emSequencia else {
            withAnimation(DS.curva) { if aberto == id { aberto = nil } }
            return
        }
        let fila = caderno.despejo.filter { $0.id != id && !pulados.contains($0.id) }
        withAnimation(DS.curva) {
            aberto = fila.first?.id
            if fila.isEmpty { emSequencia = false }
        }
    }
}

/// Card do despejo. Clique no texto para editar; no hover aparecem as ações (por cima do fim
/// do texto, sem mudar a largura dele). Aberto, mostra as escolhas e as opções de tarefa.
struct CartaoDespejo: View {
    @Environment(Caderno.self) private var caderno
    @Environment(TaskStore.self) private var store
    let item: ItemDespejo
    let aberto: Bool
    let emSequencia: Bool
    let abrir: () -> Void
    let resolvido: () -> Void
    let pular: () -> Void

    @State private var sobre = false
    @State private var editando = false
    @State private var rascunho = ""
    @State private var virandoTarefa = false
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            linha
            if aberto {
                Group {
                    if virandoTarefa {
                        OpcoesDeTarefaDespejo(texto: item.texto) { titulo, listID, due, horario, tags in
                            caderno.virarTarefa(item.id, titulo: titulo, listID: listID, due: due, horario: horario, tagIDs: tags)
                            resolvido()
                        } cancelar: {
                            withAnimation(DS.curva) { virandoTarefa = false }
                        }
                    } else {
                        escolhas
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(.horizontal, DS.e4)
        .padding(.vertical, aberto ? DS.e4 : 11)
        .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous)
            .strokeBorder(aberto ? DS.acento.opacity(0.6) : DS.borda, lineWidth: aberto ? 1.5 : 1))
        .onHover { sobre = $0 && !RolagemSuave.shared.rolando }
        .animation(DS.curvaRapida, value: sobre)
        .animation(DS.curva, value: aberto)
        .animation(DS.curva, value: virandoTarefa)
        .onChange(of: aberto) { _, agora in if !agora { virandoTarefa = false } }
    }

    private var linha: some View {
        HStack(spacing: DS.e3) {
            Circle().fill(aberto ? DS.acento : DS.texto3.opacity(0.5)).frame(width: 6, height: 6)
            if editando {
                TextField("", text: $rascunho, axis: .vertical)
                    .textFieldStyle(.plain)
                    .txt(.md)
                    .focused($foco)
                    .onSubmit(salvarEdicao)
                    .onExitCommand { editando = false }
                    .onChange(of: foco) { _, focado in if !focado { salvarEdicao() } }
            } else {
                Text(item.texto)
                    .txt(aberto ? .lg : .md, aberto ? .semibold : .regular)
                    .foregroundStyle(DS.texto)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        rascunho = item.texto
                        editando = true
                        DispatchQueue.main.async { foco = true }
                    }
                    .pointerStyle(.link)
                    .help("Clique para editar o texto")
            }
        }
        // Ações por cima do fim da linha: o texto mantém a largura.
        .overlay(alignment: .trailing) {
            if sobre && !editando && !aberto {
                HStack(spacing: 2) {
                    acaoRapida("checklist", "Virar tarefa") {
                        virandoTarefa = true
                        abrir()
                    }
                    acaoRapida("note.text", "Virar nota") {
                        caderno.virarNota(item.id)
                        resolvido()
                    }
                    acaoRapida("xmark", "Soltar (tirar da lista; dá para desfazer)") {
                        caderno.soltar(item.id)
                        resolvido()
                    }
                }
                .padding(.leading, DS.e6)
                .background(
                    LinearGradient(stops: [.init(color: DS.superficie.opacity(0), location: 0),
                                           .init(color: DS.superficie, location: 0.35)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .transition(.opacity)
            }
        }
    }

    private func acaoRapida(_ simbolo: String, _ rotulo: String, _ acao: @escaping () -> Void) -> some View {
        BotaoIcone(simbolo: simbolo, rotulo: rotulo, tamanho: 28, tamanhoIcone: 13) {
            withAnimation(DS.curva) { acao() }
        }
    }

    /// As quatro saídas, com hover e clique animados (estilo Botão do design system).
    private var escolhas: some View {
        HStack(spacing: DS.e2) {
            escolha("Virar tarefa", "checklist", "1", ajuda: "Escolher lista e data e criar a tarefa") {
                withAnimation(DS.curva) { virandoTarefa = true }
            }
            escolha("Virar nota", "note.text", "2", ajuda: "Vai para Notas, com este texto como título") {
                caderno.virarNota(item.id)
                resolvido()
            }
            if emSequencia {
                escolha("Pular", "forward", "3", ajuda: "Deixa para depois; continua no despejo", acao: pular)
            } else {
                escolha("Fechar", "chevron.up", "3", ajuda: "Fecha o card sem mudar nada", acao: abrir)
            }
            escolha("Soltar", "xmark.circle", "4", ajuda: "Tira da lista (dá para desfazer)") {
                caderno.soltar(item.id)
                resolvido()
            }
        }
    }

    private func escolha(_ titulo: String, _ simbolo: String, _ tecla: KeyEquivalent, ajuda: String,
                         acao: @escaping () -> Void) -> some View {
        Button {
            withAnimation(DS.curva) { acao() }
        } label: {
            Label(titulo, systemImage: simbolo).frame(maxWidth: .infinity)
        }
        .buttonStyle(Botao(variante: .superficie, tamanho: .m, largo: true))
        .keyboardShortcut(tecla, modifiers: .command)
        .help("\(ajuda) (⌘\(String(tecla.character)))")
    }

    private func salvarEdicao() {
        guard editando else { return }
        editando = false
        caderno.editar(item.id, texto: rascunho)
    }
}

/// Lista, data e horário para o item virar tarefa. Lê "amanhã", "~lista" e "#etiqueta" do texto.
struct OpcoesDeTarefaDespejo: View {
    @Environment(TaskStore.self) private var store
    let texto: String
    let criar: (_ titulo: String, _ listID: String?, _ due: Date?, _ horario: String?, _ tags: [String]) -> Void
    let cancelar: () -> Void

    @State private var titulo = ""
    @State private var listID: String?
    @State private var due: Date?
    @State private var horario: String?
    @State private var listasAbertas = false
    @State private var dataAberta = false
    @State private var tags: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            TextField("Título da tarefa", text: $titulo).campo()
                .help("Título da tarefa (sem as datas e etiquetas escritas no texto)")
            HStack(spacing: DS.e2) {
                if let id = listID ?? store.defaultList?.id {
                    Button {
                        withAnimation(DS.curva) { listasAbertas.toggle(); dataAberta = false }
                    } label: {
                        ListChip(listID: id, comSeta: true, aberta: listasAbertas)
                    }
                    .buttonStyle(SoAfunda(escala: 0.95))
                    .help("Trocar a lista")
                }
                Button {
                    withAnimation(DS.curva) { dataAberta.toggle(); listasAbertas = false }
                } label: {
                    Chip((due.map { DayLabel.short($0, today: store.today) } ?? "Sem data") + (horario.map { " · \($0)" } ?? "")) {
                        Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(SoAfunda(escala: 0.95))
                .help("Escolher data e horário")
                ForEach([("Hoje", 0), ("Amanhã", 1)], id: \.1) { rotulo, dias in
                    let dia = Calendar.current.adding(days: dias, to: store.today)
                    Button(rotulo) { due = dia }
                        .buttonStyle(Botao(variante: due == dia ? .primario : .superficie))
                        .help("Data: \(rotulo.lowercased())")
                }
                Button("Sem data") { due = nil; horario = nil }
                    .buttonStyle(Botao(variante: due == nil ? .primario : .superficie))
                    .help("Tarefa sem data")
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
                Button("Cancelar", action: cancelar)
                    .buttonStyle(.superficie)
                    .help("Volta às escolhas")
                Spacer()
                Button {
                    criar(titulo.trimmingCharacters(in: .whitespacesAndNewlines), listID, due, due == nil ? nil : horario, tags)
                } label: {
                    Label("Criar tarefa", systemImage: "checkmark")
                }
                .buttonStyle(Botao(variante: .primario, tamanho: .m))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Criar a tarefa (⌘↩)")
            }
        }
        .animation(DS.curva, value: listasAbertas)
        .animation(DS.curva, value: dataAberta)
        .onAppear {
            let lido = QuickAddParser.parse(texto, lists: store.lists, today: store.today)
            let limpo = lido.title.trimmingCharacters(in: .whitespaces)
            titulo = limpo.isEmpty ? texto : limpo
            listID = lido.listID
            due = lido.due ?? nil
            tags = store.resolveTags(named: lido.tagNames)
        }
    }
}

/// Linha compacta do despejo (aba do menu): editar no clique; no hover, organizar ou soltar.
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
                    .help("Clique para editar o texto")
            }
        }
        .overlay(alignment: .trailing) {
            if sobre && !editando {
                HStack(spacing: 2) {
                    BotaoIcone(simbolo: "arrow.up.forward.app", rotulo: "Organizar na janela", tamanho: 26, tamanhoIcone: 13, acao: organizar)
                    BotaoIcone(simbolo: "xmark", rotulo: "Soltar (tirar da lista; dá para desfazer)", tamanho: 26, tamanhoIcone: 12) {
                        withAnimation(DS.curva) { caderno.soltar(item.id) }
                    }
                }
                .padding(.leading, DS.e5)
                .background(
                    LinearGradient(stops: [.init(color: DS.superficie.opacity(0), location: 0),
                                           .init(color: DS.superficie, location: 0.35)],
                                   startPoint: .leading, endPoint: .trailing)
                )
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
