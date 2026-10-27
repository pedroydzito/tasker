import SwiftUI
import UniformTypeIdentifiers

/// Campo do despejo: Enter guarda e o campo continua pronto para o próximo.
/// Texto colado com várias linhas vira um item por linha.
struct CampoDespejo: View {
    enum Estilo { case compacto, inline, large }

    @Environment(Caderno.self) private var caderno
    var style: Estilo = .inline
    var onEscape: (() -> Void)?

    @State private var texto = ""
    @State private var confirmacao: String?
    @State private var foto: URL?
    @State private var arrastando = false
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
                if let foto {
                    // Foto escolhida: o texto vira o "por que salvei".
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: NSImage(contentsOf: foto) ?? NSImage())
                            .resizable().scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: DS.raioP, style: .continuous))
                        Button { withAnimation(DS.curvaRapida) { self.foto = nil } } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(DS.texto2)
                                .background(Circle().fill(DS.superficie))
                        }
                        .buttonStyle(SoAfunda(escala: 0.85))
                        .offset(x: 5, y: -5)
                        .help("Tirar a foto")
                    }
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                } else {
                    Button(action: escolherFoto) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 13, weight: .medium)).foregroundStyle(DS.texto3)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SoAfunda(escala: 0.88))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    .help("Guardar uma foto (ou arraste uma imagem para cá)")
                }
            }
            .padding(.leading, DS.e4)
            .padding(.trailing, DS.e3)
            .padding(.vertical, style == .large ? 15 : 11)
            .background {
                if style != .large {
                    RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(DS.superficie2)
                }
            }
            .overlay {
                if arrastando {
                    RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                        .strokeBorder(DS.acento, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: { NSImage(contentsOf: $0) != nil }) else { return false }
                withAnimation(DS.curvaRapida) { foto = url }
                foco = true
                return true
            } isTargeted: { arrastando = $0 }

            Group {
                if let confirmacao {
                    Label(confirmacao, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DS.sucesso)
                } else if foto != nil {
                    Text("Escreva por que salvou esta foto (opcional) e aperte Enter.")
                        .foregroundStyle(DS.texto3)
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
        if foto != nil { return "Por que salvou esta foto?" }
        switch style {
        case .large: return "O que está ocupando a sua cabeça?"
        case .compacto: return "Despejar algo…"
        case .inline: return "Escreva o que vier — uma coisa por vez, ou cole uma lista"
        }
    }

    private func escolherFoto() {
        let painel = NSOpenPanel()
        painel.allowedContentTypes = [.image]
        painel.message = "Escolha uma foto para guardar no despejo"
        if painel.runModal() == .OK, let url = painel.url {
            withAnimation(DS.curvaRapida) { foto = url }
            foco = true
        }
    }

    private func guardar() {
        let total = caderno.capturar(texto, foto: foto)
        guard total > 0 else { return }
        foto = nil
        texto = ""
        foco = true
        let mensagem = total == 1 ? "Guardado no despejo" : "\(total) itens guardados no despejo"
        confirmacao = mensagem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if confirmacao == mensagem { confirmacao = nil }
        }
    }
}

/// Miniatura da foto de um item (clique abre no Pré-Visualização).
struct MiniaturaFoto: View {
    let nome: String
    var lado: CGFloat = 40

    var body: some View {
        let url = Caderno.urlDaFoto(nome)
        Button { NSWorkspace.shared.open(url) } label: {
            Image(nsImage: NSImage(contentsOf: url) ?? NSImage())
                .resizable().scaledToFill()
                .frame(width: lado, height: lado)
                .clipShape(RoundedRectangle(cornerRadius: DS.raioP, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.raioP, style: .continuous).strokeBorder(DS.borda))
        }
        .buttonStyle(SoAfunda(escala: 0.94))
        .help("Abrir a foto")
    }
}

/// Despejo: a caixa de entrada e as pilhas Depois e Não.
struct DespejoView: View {
    enum Pilha: Hashable { case caixa, depois, nao }

    @Environment(Caderno.self) private var caderno
    /// Já começa organizando (usado nas capturas de tela).
    var abrirTriagem = false

    @State private var pilha: Pilha

    init(abrirTriagem: Bool = false, pilhaInicial: Pilha = .caixa) {
        self.abrirTriagem = abrirTriagem
        _pilha = State(initialValue: pilhaInicial)
    }
    /// Card aberto (com as escolhas à mostra).
    @State private var aberto: String?
    /// Organizando de 3 em 3: quantos já foram nesta rodada.
    @State private var emSequencia = false
    @State private var nestaRodada = 0
    @State private var pausaDaRodada = false
    private static let tamanhoDaRodada = 3

    var body: some View {
        PageScaffold(rotulo: "Tire da cabeça. Organize depois.", title: "Despejo") {
            VStack(alignment: .leading, spacing: DS.e5) {
                CampoDespejo(style: .inline)
                    .padding(DS.e2)
                    .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))

                Segmentado(selecao: $pilha, opcoes: [
                    (.caixa, "Caixa · \(caderno.despejo.count)"),
                    (.depois, "Depois · \(caderno.depois.count)"),
                    (.nao, "Não · \(caderno.naoCarregar.count)"),
                ])

                switch pilha {
                case .caixa: caixa
                case .depois: PilhaDespejo(estado: .depois)
                case .nao: PilhaDespejo(estado: .nao)
                }
            }
        }
        .animation(DS.curva, value: caderno.itens.map(\.id))
        .animation(DS.curva, value: caderno.itens.map(\.estado))
        .animation(DS.curva, value: pilha)
        .onAppear { if abrirTriagem { comecar() } }
        .onChange(of: pilha) { _, _ in parar() }
    }

    @ViewBuilder private var caixa: some View {
        if caderno.despejo.isEmpty {
            EstadoVazio(icone: "brain.head.profile", titulo: "Cabeça leve",
                        descricao: "Escreva aqui tudo o que estiver ocupando espaço. Depois, com calma, decida: Agora, Depois ou Não.")
                .padding(.top, DS.e6)
        } else {
            barra
            if pausaDaRodada {
                pausa.transition(.opacity.combined(with: .offset(y: -6)))
            }
            VStack(spacing: DS.e2) {
                // Mais antigos primeiro: é a ordem em que se organiza.
                ForEach(caderno.despejo) { item in
                    CartaoDespejo(item: item, aberto: aberto == item.id,
                                  abrir: { withAnimation(DS.curva) { aberto = aberto == item.id ? nil : item.id } },
                                  resolvido: { proximo(depois: item.id) })
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)),
                                                removal: .opacity.combined(with: .scale(scale: 0.97))))
                }
            }
        }
    }

    private var barra: some View {
        HStack {
            Text(caderno.despejo.count == 1 ? "1 coisa para organizar" : "\(caderno.despejo.count) coisas para organizar")
                .txt(.sm, .medium)
                .foregroundStyle(DS.texto3)
            Spacer()
            if emSequencia {
                Button("Parar") { parar() }
                    .buttonStyle(Botao(variante: .superficie, tamanho: .m))
                    .help("Sai do modo de organizar; os itens ficam como estão")
            } else {
                Button(action: comecar) {
                    Label(caderno.despejo.count > Self.tamanhoDaRodada ? "Organizar 3" : "Organizar", systemImage: "rectangle.stack")
                }
                .buttonStyle(Botao(variante: .primario, tamanho: .m))
                .help("Abre um item por vez, do mais antigo, de 3 em 3 — sem precisar esvaziar tudo")
                .accessibilityIdentifier("organizar")
            }
        }
    }

    /// Depois de 3: um respiro, sem cobrar o resto.
    private var pausa: some View {
        HStack(spacing: DS.e3) {
            Image(systemName: "checkmark.seal").font(.system(size: 18, weight: .medium)).foregroundStyle(DS.sucesso)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pronto, 3 organizadas.").txt(.sm, .semibold).foregroundStyle(DS.texto)
                Text("Pode parar aqui. O resto espera.").txt(.xs).foregroundStyle(DS.texto3)
            }
            Spacer()
            Button("Por hoje chega") { parar() }.buttonStyle(Botao(variante: .fantasma))
                .help("Para de organizar")
            Button("Mais 3") { comecar() }.buttonStyle(Botao(variante: .primario))
                .help("Organizar mais 3")
        }
        .padding(DS.e4)
        .background(DS.sucessoTenue, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
    }

    private func comecar() {
        withAnimation(DS.curva) {
            pausaDaRodada = false
            nestaRodada = 0
            emSequencia = true
            aberto = caderno.despejo.first?.id
        }
    }

    private func parar() {
        withAnimation(DS.curva) {
            emSequencia = false
            pausaDaRodada = false
            aberto = nil
        }
    }

    /// Depois de resolver um card: abre o próximo, até completar a rodada de 3.
    private func proximo(depois id: String) {
        guard emSequencia else {
            withAnimation(DS.curva) { if aberto == id { aberto = nil } }
            return
        }
        nestaRodada += 1
        let fila = caderno.despejo.filter { $0.id != id }
        withAnimation(DS.curva) {
            if fila.isEmpty {
                emSequencia = false
                aberto = nil
            } else if nestaRodada >= Self.tamanhoDaRodada {
                emSequencia = false
                aberto = nil
                pausaDaRodada = true
            } else {
                aberto = fila.first?.id
            }
        }
    }
}

/// Card da caixa. Clique no texto para editar; no hover, Agora · Depois · Não por cima do fim do
/// texto (sem mudar a largura). Aberto, mostra as escolhas grandes e "escolher lista e data".
struct CartaoDespejo: View {
    @Environment(Caderno.self) private var caderno
    @Environment(TaskStore.self) private var store
    let item: ItemDespejo
    let aberto: Bool
    let abrir: () -> Void
    let resolvido: () -> Void

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
                        OpcoesDeTarefaDespejo(texto: item.textoExibido) { titulo, listID, due, horario, tags in
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
            if let foto = item.foto {
                MiniaturaFoto(nome: foto, lado: aberto ? 56 : 36)
            } else {
                Circle().fill(aberto ? DS.acento : DS.texto3.opacity(0.5)).frame(width: 6, height: 6)
            }
            if editando {
                TextField("", text: $rascunho, axis: .vertical)
                    .textFieldStyle(.plain)
                    .txt(.md)
                    .focused($foco)
                    .onSubmit(salvarEdicao)
                    .onExitCommand { editando = false }
                    .onChange(of: foco) { _, focado in if !focado { salvarEdicao() } }
            } else {
                Text(item.textoExibido)
                    .txt(aberto ? .lg : .md, aberto ? .semibold : .regular)
                    .foregroundStyle(item.texto.isEmpty ? DS.texto3 : DS.texto)
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
                AcoesRapidasDespejo(id: item.id, tamanho: 28, depois: resolvido) {
                    virandoTarefa = false
                    abrir()
                }
                .transition(.opacity)
            }
        }
    }

    /// As saídas, com hover e clique animados (estilo Botão do design system).
    private var escolhas: some View {
        VStack(alignment: .leading, spacing: DS.e2) {
            HStack(spacing: DS.e2) {
                escolha("Agora", "bolt", "1", ajuda: "Vira tarefa para hoje") {
                    caderno.fazerAgora(item.id)
                    resolvido()
                }
                escolha("Depois", "clock", "2", ajuda: "Importante, mas não agora: fica guardado em Depois") {
                    caderno.mover(item.id, para: .depois)
                    resolvido()
                }
                escolha("Não", "hand.raised", "3", ajuda: "Decidi não carregar isso (fica guardado em Não)") {
                    caderno.mover(item.id, para: .nao)
                    resolvido()
                }
                escolha("Nota", "note.text", "4", ajuda: "Vira uma nota, com este texto como título") {
                    caderno.virarNota(item.id)
                    resolvido()
                }
            }
            HStack {
                Button("Escolher lista e data…") { withAnimation(DS.curva) { virandoTarefa = true } }
                    .buttonStyle(Botao(variante: .fantasma))
                    .help("Virar tarefa escolhendo a lista, a data e o horário")
                Spacer()
                Button("Fechar", action: abrir)
                    .buttonStyle(Botao(variante: .fantasma))
                    .keyboardShortcut(.cancelAction)
                    .help("Fecha o card sem mudar nada (Esc)")
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

/// Agora · Depois · Não (e "mais") em ícones, para o hover dos itens da caixa.
struct AcoesRapidasDespejo: View {
    @Environment(Caderno.self) private var caderno
    let id: String
    var tamanho: CGFloat = 26
    var depois: () -> Void = {}
    var mais: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            botao("bolt", "Agora: vira tarefa para hoje") { caderno.fazerAgora(id) }
            botao("clock", "Depois: importante, mas não agora") { caderno.mover(id, para: .depois) }
            botao("hand.raised", "Não: decidi não carregar isso") { caderno.mover(id, para: .nao) }
            if let mais {
                BotaoIcone(simbolo: "ellipsis", rotulo: "Mais opções (nota, lista e data)", tamanho: tamanho, tamanhoIcone: 13) {
                    withAnimation(DS.curva) { mais() }
                }
            }
        }
        .padding(.leading, DS.e6)
        .background(
            LinearGradient(stops: [.init(color: DS.superficie.opacity(0), location: 0),
                                   .init(color: DS.superficie, location: 0.3)],
                           startPoint: .leading, endPoint: .trailing)
        )
    }

    private func botao(_ simbolo: String, _ rotulo: String, _ acao: @escaping () -> Void) -> some View {
        BotaoIcone(simbolo: simbolo, rotulo: rotulo, tamanho: tamanho, tamanhoIcone: 13) {
            withAnimation(DS.curva) {
                acao()
                depois()
            }
        }
    }
}

/// Pilhas Depois e Não: o que foi guardado, sem cobrança. Dá para trazer de volta a qualquer hora.
struct PilhaDespejo: View {
    @Environment(Caderno.self) private var caderno
    let estado: ItemDespejo.Estado

    var body: some View {
        let itens = estado == .depois ? caderno.depois : caderno.naoCarregar
        VStack(alignment: .leading, spacing: DS.e4) {
            HStack(alignment: .top) {
                Text(estado == .depois
                     ? "Importante, mas não agora. Fica aqui guardado — sem prazo e sem cobrança."
                     : "O que você decidiu não carregar. Uma ideia não precisa ser feita só porque é boa.")
                    .txt(.sm).foregroundStyle(DS.texto3)
                Spacer()
                if estado == .nao && !itens.isEmpty {
                    Button("Apagar tudo") { withAnimation(DS.curva) { caderno.esvaziarNao() } }
                        .buttonStyle(Botao(variante: .fantasma))
                        .help("Apaga de vez os itens desta pilha (dá para desfazer logo depois)")
                }
            }
            if itens.isEmpty {
                EstadoVazio(icone: estado == .depois ? "clock" : "hand.raised",
                            titulo: estado == .depois ? "Nada guardado para depois" : "Nada por aqui",
                            descricao: estado == .depois
                                ? "No despejo, use “Depois” para o que é importante, mas não agora."
                                : "No despejo, use “Não” para o que você decidiu não carregar.")
                    .padding(.top, DS.e4)
            } else {
                CartaoDeLinhas(recuoDoFio: DS.e4) {
                    ForEach(itens) { LinhaPilha(item: $0) }
                }
            }
        }
    }
}

private struct LinhaPilha: View {
    @Environment(Caderno.self) private var caderno
    let item: ItemDespejo
    @State private var sobre = false

    var body: some View {
        HStack(spacing: DS.e3) {
            if let foto = item.foto { MiniaturaFoto(nome: foto, lado: 32) }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.textoExibido).txt(.md).foregroundStyle(item.texto.isEmpty ? DS.texto3 : DS.texto)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text((item.movido ?? item.criado).formatted(.relative(presentation: .named)).primeiraMaiuscula)
                    .txt(.xs).foregroundStyle(DS.texto3)
            }
        }
        .overlay(alignment: .trailing) {
            if sobre {
                HStack(spacing: 2) {
                    BotaoIcone(simbolo: "bolt", rotulo: "Agora: vira tarefa para hoje", tamanho: 28, tamanhoIcone: 13) {
                        withAnimation(DS.curva) { caderno.fazerAgora(item.id) }
                    }
                    BotaoIcone(simbolo: "tray.and.arrow.up", rotulo: "Voltar para a caixa", tamanho: 28, tamanhoIcone: 13) {
                        withAnimation(DS.curva) { caderno.mover(item.id, para: .caixa) }
                    }
                    if item.estado == .depois {
                        BotaoIcone(simbolo: "hand.raised", rotulo: "Não: decidi não carregar isso", tamanho: 28, tamanhoIcone: 13) {
                            withAnimation(DS.curva) { caderno.mover(item.id, para: .nao) }
                        }
                    } else {
                        BotaoIcone(simbolo: "clock", rotulo: "Mover para Depois", tamanho: 28, tamanhoIcone: 13) {
                            withAnimation(DS.curva) { caderno.mover(item.id, para: .depois) }
                        }
                    }
                    BotaoIcone(simbolo: "trash", rotulo: "Apagar (dá para desfazer)", tamanho: 28, tamanhoIcone: 13) {
                        withAnimation(DS.curva) { caderno.soltar(item.id) }
                    }
                }
                .padding(.leading, DS.e6)
                .background(
                    LinearGradient(stops: [.init(color: DS.superficie.opacity(0), location: 0),
                                           .init(color: DS.superficie, location: 0.3)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.e3)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(sobre ? DS.veuHover : .clear))
        .onHover { sobre = $0 && !RolagemSuave.shared.rolando }
        .animation(DS.curvaRapida, value: sobre)
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
                Button("Voltar", action: cancelar)
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

/// Linha compacta do despejo (aba do menu): editar no clique; no hover, Agora · Depois · Não.
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
            if let foto = item.foto {
                MiniaturaFoto(nome: foto, lado: 26)
            } else {
                Circle().fill(DS.texto3.opacity(0.5)).frame(width: 5, height: 5)
            }
            if editando {
                TextField("", text: $rascunho, axis: .vertical)
                    .textFieldStyle(.plain)
                    .txt(compacta ? .sm : .md)
                    .focused($foco)
                    .onSubmit(salvar)
                    .onExitCommand { editando = false }
                    .onChange(of: foco) { _, focado in if !focado { salvar() } }
            } else {
                Text(item.textoExibido)
                    .txt(compacta ? .sm : .md)
                    .foregroundStyle(item.texto.isEmpty ? DS.texto3 : DS.texto)
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
                AcoesRapidasDespejo(id: item.id, tamanho: 26, mais: organizar)
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
