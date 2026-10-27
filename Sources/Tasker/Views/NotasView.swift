import SwiftUI

/// Notas: à esquerda a nota de hoje e as demais; à direita o editor (salva sozinho).
struct NotasView: View {
    @Environment(Caderno.self) private var caderno
    @Environment(TaskStore.self) private var store
    @Environment(Navigation.self) private var nav
    @AppStorage("larguraListaNotas") private var larguraLista: Double = 280

    var body: some View {
        HStack(spacing: 0) {
            lista
                .frame(width: larguraLista)
            Divisoria(largura: $larguraLista, minimo: 220, maximo: 420, sentido: 1)
            Group {
                if let alvo = nav.notaAberta, existe(alvo) {
                    EditorDeNota(alvo: alvo)
                        .id(alvo)
                } else {
                    EstadoVazio(icone: "note.text", titulo: "Escolha ou crie uma nota",
                                descricao: "A nota do dia é um diário de planejamento: o que você quer da semana, como foi hoje. Escreva [ ] no começo da linha para virar tarefa.")
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.superficie)
        }
        .onAppear {
            if nav.notaAberta == nil { nav.notaAberta = .dia(store.today) }
        }
        .onChange(of: nav.notaAberta) { anterior, _ in
            // Nota solta criada e deixada em branco não fica acumulando.
            if case .nota(let id) = anterior { caderno.descartarSeVazia(id) }
        }
    }

    private func existe(_ alvo: AlvoNota) -> Bool {
        switch alvo {
        case .dia: true
        case .nota(let id): caderno.nota(id) != nil
        }
    }

    private var lista: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CabecalhoTela(rotulo: "\(caderno.notas.count) \(caderno.notas.count == 1 ? "nota" : "notas")", titulo: "Notas", tamanho: .display2)
                Spacer()
                BotaoIcone(simbolo: "calendar.badge.checkmark", rotulo: "Revisão da semana (nota pronta com o que foi feito e o que ficou)") {
                    let id = caderno.revisaoDaSemana()
                    withAnimation(DS.curva) { nav.notaAberta = .nota(id) }
                }
                .accessibilityIdentifier("revisaoSemana")
                BotaoIcone(simbolo: "square.and.pencil", rotulo: "Nova nota") {
                    let id = caderno.novaNota()
                    withAnimation(DS.curva) { nav.notaAberta = .nota(id) }
                }
                .accessibilityIdentifier("novaNota")
            }
            .padding(.horizontal, DS.e5)
            .padding(.top, 44)
            .padding(.bottom, DS.e4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let hoje = store.today
                    let temHoje = caderno.notaDoDia(hoje) != nil
                    if !temHoje {
                        LinhaNota(titulo: "Hoje", detalhe: "Escrever a nota do dia", icone: "sun.max",
                                  selecionada: nav.notaAberta == .dia(hoje)) {
                            nav.notaAberta = .dia(hoje)
                        }
                    }
                    ForEach(caderno.notasOrdenadas) { nota in
                        let alvo: AlvoNota = nota.dia.map { .dia($0) } ?? .nota(nota.id)
                        LinhaNota(titulo: nota.dia == hoje ? "Hoje" : nota.tituloExibido,
                                  detalhe: resumo(nota),
                                  icone: nota.dia == nil ? "note.text" : "calendar",
                                  selecionada: nav.notaAberta == alvo) {
                            nav.notaAberta = alvo
                        }
                        .contextMenu {
                            Button("Excluir nota", role: .destructive) { excluir(nota) }
                        }
                    }
                }
                .padding(.horizontal, DS.e3)
                .padding(.bottom, DS.e5)
                .animation(DS.curva, value: caderno.notas.map(\.id))
            }
            .scrollIndicators(.never)
            .indicadorDeRolagem()
        }
        .background(DS.fundo)
    }

    private func resumo(_ nota: Anotacao) -> String {
        let corpo = nota.texto.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0 != nota.tituloExibido } ?? ""
        let quando = nota.dia.map { DayLabel.short($0, today: store.today) }
            ?? nota.editada.formatted(.relative(presentation: .named))
        return corpo.isEmpty ? quando : "\(quando) · \(corpo)"
    }

    private func excluir(_ nota: Anotacao) {
        excluirNotaComSeguranca(nota.id, caderno: caderno, nav: nav)
    }
}

private struct LinhaNota: View {
    let titulo: String
    let detalhe: String
    let icone: String
    let selecionada: Bool
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(alignment: .top, spacing: DS.e3) {
                Image(systemName: icone)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selecionada ? DS.acento : DS.texto3)
                    .frame(width: 18)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).txt(.sm, .semibold).foregroundStyle(DS.texto).lineLimit(1)
                    Text(detalhe).txt(.xs).foregroundStyle(DS.texto3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if selecionada {
                    RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(DS.superficie2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressionavel(raio: DS.raioM, escala: 0.99))
        .help("Abrir “\(titulo)”")
    }
}

/// Editor: título + texto, salvos enquanto se digita. Linhas "[ ] algo" podem virar tarefa.
struct EditorDeNota: View {
    @Environment(Caderno.self) private var caderno
    @Environment(TaskStore.self) private var store
    @Environment(Navigation.self) private var nav
    @Environment(Folhas.self) private var folhas
    let alvo: AlvoNota

    @State private var titulo = ""
    @State private var texto = ""
    @State private var carregado = false

    private var dia: Date? {
        if case .dia(let d) = alvo { return d }
        return nil
    }

    private var nota: Anotacao? {
        switch alvo {
        case .dia(let d): caderno.notaDoDia(d)
        case .nota(let id): caderno.nota(id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.e1) {
                if let nota {
                    Text("Editada \(nota.editada.formatted(.relative(presentation: .named)))")
                        .txt(.xs).foregroundStyle(DS.texto3)
                }
                Spacer()
                if let nota {
                    BotaoIcone(simbolo: "trash", rotulo: "Excluir nota") {
                        folhas.confirmar("Excluir nota", mensagem: "“\(nota.tituloExibido)” será excluída. Dá para desfazer logo depois.") {
                            excluirNotaComSeguranca(nota.id, caderno: caderno, nav: nav)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.e6)
            .padding(.top, DS.e4)
            .frame(height: 52)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.e4) {
                    if let dia {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(DayLabel.long(dia)).rotulo()
                            Text(DayLabel.short(dia, today: store.today)).display(.titulo).foregroundStyle(DS.texto)
                        }
                    } else {
                        TextField("Título", text: $titulo, axis: .vertical)
                            .textFieldStyle(.plain)
                            .display(.titulo)
                            .foregroundStyle(DS.texto)
                            .onChange(of: titulo) { _, novo in
                                if carregado, case .nota(let id) = alvo { caderno.atualizar(id, titulo: novo) }
                            }
                            .accessibilityIdentifier("tituloNota")
                    }

                    if let foto = nota?.foto {
                        MiniaturaFoto(nome: foto, lado: 160)
                    }

                    TextEditor(text: $texto)
                        .txt(.md)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .frame(minHeight: 320)
                        .overlay(alignment: .topLeading) {
                            if texto.isEmpty {
                                Text(dia == nil
                                     ? "Escreva livremente. [ ] no começo da linha vira tarefa."
                                     : "Como está o dia? O que você quer fazer? [ ] no começo da linha vira tarefa.")
                                    .txt(.md)
                                    .foregroundStyle(DS.texto3)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                        // O TextEditor tem 5 pt de margem interna: puxa para alinhar com o título.
                        .padding(.leading, -5)
                        .onChange(of: texto) { _, novo in salvar(texto: novo) }
                        .accessibilityIdentifier("textoNota")

                    let pendentes = Caderno.pendentes(em: texto)
                    if !pendentes.isEmpty, let nota {
                        TarefasDaNota(nota: nota, pendentes: pendentes)
                    }
                }
                .padding(.horizontal, DS.e6)
                .padding(.bottom, DS.e8)
            }
            .scrollIndicators(.never)
            .indicadorDeRolagem(fundo: DS.superficie)
        }
        .onAppear(perform: carregar)
        // A nota pode mudar por fora (ex.: "[ ]" virou "→" ao criar a tarefa).
        .onChange(of: nota?.texto) { _, novo in
            if let novo, novo != texto { texto = novo }
        }
    }

    private func carregar() {
        titulo = nota?.titulo ?? ""
        texto = nota?.texto ?? ""
        DispatchQueue.main.async { carregado = true }
    }

    private func salvar(texto novo: String) {
        guard carregado else { return }
        switch alvo {
        case .dia(let d): caderno.escreverNoDia(d, texto: novo)
        case .nota(let id): caderno.atualizar(id, texto: novo)
        }
    }
}

/// Linhas "[ ] algo" da nota: um clique cria a tarefa (na lista padrão; a data é a do dia da nota).
private struct TarefasDaNota: View {
    @Environment(Caderno.self) private var caderno
    @Environment(TaskStore.self) private var store
    let nota: Anotacao
    let pendentes: [Caderno.Pendente]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e2) {
            HStack {
                Text("Viram tarefa").rotulo()
                Spacer()
                if pendentes.count > 1 {
                    Button("Criar todas") {
                        // De baixo para cima: os números das linhas não mudam, mas mantém a ordem estável.
                        for p in pendentes.reversed() { criar(p) }
                    }
                    .buttonStyle(Botao(variante: .fantasma))
                }
            }
            VStack(spacing: 1) {
                ForEach(pendentes, id: \.self) { p in
                    HStack(spacing: DS.e3) {
                        Image(systemName: "circle").font(.system(size: 13)).foregroundStyle(DS.texto3)
                        Text(p.titulo).txt(.sm).foregroundStyle(DS.texto).lineLimit(2)
                        Spacer()
                        Button("Criar tarefa") { criar(p) }
                            .buttonStyle(Botao(variante: .superficie))
                    }
                    .padding(.horizontal, DS.e3)
                    .padding(.vertical, 6)
                }
            }
            .padding(DS.e1)
            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
            if let lista = store.defaultList {
                Text("Vão para “\(store.displayName(lista.id))”\(nota.dia.map { ", com a data \(DayLabel.short($0, today: store.today).lowercased())" } ?? "").")
                    .txt(.xs).foregroundStyle(DS.texto3)
            }
        }
    }

    private func criar(_ p: Caderno.Pendente) {
        withAnimation(DS.curva) {
            caderno.criarTarefa(daLinha: p.linha, naNota: nota.id, listID: nil, due: nota.dia)
        }
    }
}

/// Exclui uma nota sem derrubar o editor: primeiro encerra a edição do texto (o editor de texto
/// do AppKit não pode sumir com o cursor dentro), fecha a nota na tela e só no ciclo seguinte
/// tira a nota do caderno — depois que a folha de confirmação terminou de fechar.
@MainActor
func excluirNotaComSeguranca(_ id: String, caderno: Caderno, nav: Navigation) {
    for janela in NSApp.windows where janela.firstResponder is NSTextView {
        janela.makeFirstResponder(nil)
    }
    if let nota = caderno.nota(id) {
        let alvo: AlvoNota = nota.dia.map { .dia($0) } ?? .nota(id)
        if nav.notaAberta == alvo { nav.notaAberta = nil }
    }
    DispatchQueue.main.async {
        withAnimation(DS.curva) { caderno.excluirNota(id) }
    }
}
