import SwiftUI

/// Busca única (⌘K): tarefas, notas, despejo e eventos. Setas escolhem, Enter abre.
struct BuscaView: View {
    @Environment(Caderno.self) private var caderno
    @Environment(TaskStore.self) private var store
    @Environment(Navigation.self) private var nav
    @Environment(Folhas.self) private var folhas
    var consultaInicial = ""

    @State private var consulta = ""
    @State private var resultados: [ResultadoBusca] = []
    @State private var escolhido = 0
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            HStack(spacing: DS.e3) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.texto3)
                TextField("Buscar em tarefas, notas, despejo e agenda", text: $consulta)
                    .textFieldStyle(.plain)
                    .txt(.lg)
                    .focused($foco)
                    .onSubmit(abrirEscolhido)
                    .onKeyPress(.downArrow) { mover(1); return .handled }
                    .onKeyPress(.upArrow) { mover(-1); return .handled }
                    .accessibilityIdentifier("campoBusca")
            }
            .padding(.horizontal, DS.e4)
            .frame(height: 48)
            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))

            if consulta.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Dica: várias palavras procuram todas ao mesmo tempo; acentos e maiúsculas não importam.")
                    .txt(.xs).foregroundStyle(DS.texto3).padding(.horizontal, DS.e2)
            } else if resultados.isEmpty {
                Text("Nada encontrado para “\(consulta)”.").txt(.sm).foregroundStyle(DS.texto3).padding(DS.e3)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(resultados.enumerated()), id: \.element.id) { i, r in
                                LinhaResultado(resultado: r, escolhido: i == escolhido) { abrir(r) }
                                    .id(r.id)
                                    .onHover { if $0 { escolhido = i } }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(maxHeight: 360)
                    .indicadorDeRolagem(fundo: DS.superficie)
                    .onChange(of: escolhido) { _, i in
                        guard resultados.indices.contains(i) else { return }
                        withAnimation(DS.curvaRapida) { proxy.scrollTo(resultados[i].id) }
                    }
                }
            }
        }
        .onAppear {
            if !consultaInicial.isEmpty { consulta = consultaInicial }
            DispatchQueue.main.async { foco = true }
        }
        .onChange(of: consulta) { _, q in
            resultados = caderno.buscar(q)
            escolhido = 0
        }
    }

    private func mover(_ passo: Int) {
        guard !resultados.isEmpty else { return }
        escolhido = (escolhido + passo + resultados.count) % resultados.count
    }

    private func abrirEscolhido() {
        guard resultados.indices.contains(escolhido) else { return }
        abrir(resultados[escolhido])
    }

    private func abrir(_ r: ResultadoBusca) {
        folhas.fechar()
        withAnimation(DS.curva) {
            switch r.tipo {
            case .tarefa:
                if let task = store.tasks[r.alvo] {
                    // Mostra a tarefa numa tela onde ela aparece e abre o detalhe.
                    nav.selection = task.isCompleted ? .completed : .list(task.listID)
                    nav.selectedTaskID = task.id
                }
            case .nota:
                nav.selection = .notas
                if let nota = caderno.nota(r.alvo) {
                    nav.notaAberta = nota.dia.map { .dia($0) } ?? .nota(nota.id)
                }
            case .despejo:
                nav.selection = .despejo
            case .evento:
                if let link = store.events.first(where: { $0.id == r.alvo })?.htmlLink.flatMap(URL.init(string:)) {
                    NSWorkspace.shared.open(link)
                } else {
                    nav.selection = .calendar
                }
            }
        }
    }
}

private struct LinhaResultado: View {
    @Environment(TaskStore.self) private var store
    let resultado: ResultadoBusca
    let escolhido: Bool
    let acao: () -> Void

    private var icone: String {
        switch resultado.tipo {
        case .tarefa: resultado.concluida ? "checkmark.circle" : "circle"
        case .nota: "note.text"
        case .despejo: "brain.head.profile"
        case .evento: "calendar"
        }
    }

    private var tipo: String {
        switch resultado.tipo {
        case .tarefa: "Tarefa"
        case .nota: "Nota"
        case .despejo: "Despejo"
        case .evento: "Evento"
        }
    }

    var body: some View {
        Button(action: acao) {
            HStack(alignment: .top, spacing: DS.e3) {
                Image(systemName: icone).font(.system(size: 13, weight: .medium)).foregroundStyle(DS.texto3)
                    .frame(width: 18).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(resultado.titulo).txt(.sm, .semibold).foregroundStyle(DS.texto).lineLimit(1)
                        .strikethrough(resultado.concluida, color: DS.texto3)
                    if let trecho = resultado.trecho, !trecho.isEmpty {
                        Text(trecho).txt(.xs).foregroundStyle(DS.texto3).lineLimit(1)
                    }
                }
                Spacer(minLength: DS.e2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tipo).txt(.xs, .semibold).foregroundStyle(DS.texto3)
                    if let data = resultado.data, resultado.tipo != .despejo {
                        Text(DayLabel.short(Calendar.current.startOfDay(for: data), today: store.today))
                            .txt(.xs).foregroundStyle(DS.texto3)
                    }
                }
            }
            .padding(.horizontal, DS.e3)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(escolhido ? DS.superficie2 : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(SoAfunda(escala: 0.99))
    }
}
