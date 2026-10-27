import SwiftUI

/// Campo de nova tarefa: entende datas, ~lista e #etiqueta.
/// Ao digitar, aparecem a lista, a data e as etiquetas; clicar na lista abre um dropdown ali mesmo.
struct QuickAddField: View {
    enum Style { case compact, inline, large, floating }

    @Environment(TaskStore.self) private var store
    /// Data padrão quando nada é digitado (nil = sem data).
    var defaultDue: Date?
    var fixedListID: String?
    var fixedTagID: String?
    var style: Style = .compact
    var onAdded: (() -> Void)?
    /// ESC sem nada aberto: fecha quem hospeda o campo (ex.: painel do ⌥Espaço).
    var onEscape: (() -> Void)?

    @State private var text = ""
    @State private var chosenListID: String?
    @State private var dropdownAberto = false
    @State private var dataAberta = false
    /// Data escolhida no seletor (vale mais que o padrão; o texto digitado vale mais que ela).
    @State private var dataEscolhida: Date??
    @State private var horario: String?
    @FocusState private var focused: Bool

    private var parsed: QuickAddParser.Result {
        QuickAddParser.parse(text, lists: store.lists, today: store.today)
    }

    private var listID: String? { parsed.listID ?? chosenListID ?? fixedListID ?? store.defaultList?.id }
    private var due: Date? {
        if let explicit = parsed.due { return explicit }
        if let dataEscolhida { return dataEscolhida }
        return defaultDue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e2) {
            HStack(spacing: DS.e3) {
                Image(systemName: "plus")
                    .font(.system(size: style == .large ? 16 : 13, weight: .semibold))
                    .foregroundStyle(focused ? DS.acento : DS.texto3)
                    .rotationEffect(.degrees(focused ? 90 : 0))
                    .animation(DS.curva, value: focused)
                // Vertical: uma lista colada mantém as linhas (vira uma tarefa por linha).
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .txt(style == .large ? .lg : .md)
                    .foregroundStyle(DS.texto)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand {
                        if dropdownAberto {
                            withAnimation(DS.curva) { dropdownAberto = false }
                        } else if let onEscape {
                            text = ""
                            onEscape()
                        } else {
                            text = ""
                        }
                    }
                if style == .floating || style == .large {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(text.isEmpty ? DS.texto3 : DS.acentoSolidoTexto)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(text.isEmpty ? DS.superficie2 : DS.acentoSolido))
                    }
                    .buttonStyle(SoAfunda(escala: 0.9))
                    .disabled(text.isEmpty)
                    .animation(DS.curvaRapida, value: text.isEmpty)
                    .help("Adicionar tarefa")
                }
            }
            .padding(.leading, DS.e4)
            .padding(.trailing, style == .floating || style == .large ? 6 : DS.e3)
            .frame(height: style == .large ? 52 : (style == .floating ? 44 : 40))
            .background {
                if style == .compact || style == .inline {
                    RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(DS.superficie2)
                }
            }

            if !text.isEmpty {
                chips.padding(.horizontal, DS.e3).padding(.bottom, style == .floating ? 4 : 0)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
            if dataAberta && !text.isEmpty {
                SeletorDeDataEmbutido(due: Binding(get: { due }, set: { dataEscolhida = .some($0) }),
                                      horario: $horario) {
                    withAnimation(DS.curva) { dataAberta = false }
                    focused = true
                }
                .frame(maxWidth: 320)
                .padding(.horizontal, DS.e1)
                .padding(.bottom, DS.e1)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
            if dropdownAberto && !text.isEmpty {
                DropdownDeListas(atual: listID) { id in
                    chosenListID = id
                    withAnimation(DS.curva) { dropdownAberto = false }
                    focused = true
                }
                .padding(.horizontal, DS.e1)
                .padding(.bottom, DS.e1)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(DS.curva, value: text.isEmpty)
        .animation(DS.curva, value: dropdownAberto)
        .animation(DS.curva, value: dataAberta)
        .onChange(of: text) { _, novo in
            if novo.isEmpty {
                dropdownAberto = false
                dataAberta = false
            }
        }
        .onAppear {
            if style == .large {
                // Abre já pronto para digitar.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
            }
        }
    }

    private var placeholder: String {
        switch style {
        case .large: return "Nova tarefa — ex.: ligar pro cliente amanhã #urgente"
        case .floating: return "Adicionar tarefa  ·  ⌥Espaço de qualquer lugar"
        default: return "Adicionar tarefa"
        }
    }

    private var chips: some View {
        HStack(spacing: DS.e2) {
            if let listID {
                Button {
                    withAnimation(DS.curva) { dropdownAberto.toggle(); dataAberta = false }
                } label: {
                    HStack(spacing: 3) {
                        ListChip(listID: listID, comSeta: true, aberta: dropdownAberto)
                    }
                }
                .buttonStyle(SoAfunda(escala: 0.95))
                .help("Trocar a lista")
            }
            Button {
                withAnimation(DS.curva) { dataAberta.toggle(); dropdownAberto = false }
            } label: {
                Chip((due.map { DayLabel.short($0, today: store.today) } ?? "Sem data") + (horario.map { " · \($0)" } ?? "")) {
                    Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(SoAfunda(escala: 0.95))
            .help("Trocar a data")
            if varias.count > 1 {
                Chip("\(varias.count) tarefas", cor: DS.acento) {
                    Image(systemName: "list.bullet").font(.system(size: 10, weight: .semibold))
                }
                .help("Uma tarefa por linha. Data e lista escritas na linha valem só para ela.")
            }
            ForEach(varias.count > 1 ? [] : parsed.tagNames, id: \.self) { name in
                Chip("#\(name)", cor: store.tags.first { $0.name.lowercased() == name.lowercased() }
                    .map { Color(hex: $0.colorHex) } ?? DS.texto2)
            }
            Spacer()
            Text("↩︎ Adicionar").txt(.xs).foregroundStyle(DS.texto3)
        }
    }

    /// Linhas do texto (mais de uma = lista colada).
    private var varias: [String] { QuickAddParser.linhas(text) }

    private func submit() {
        let linhas = varias
        if linhas.count > 1 {
            // Cada linha vira uma tarefa; o que estiver escrito na linha (data, ~lista, #etiqueta)
            // vale para ela, o resto vem dos chips.
            for linha in linhas {
                let r = QuickAddParser.parse(linha, lists: store.lists, today: store.today)
                let titulo = r.title.trimmingCharacters(in: .whitespaces)
                guard !titulo.isEmpty else { continue }
                var tagIDs = store.resolveTags(named: r.tagNames)
                if let fixedTagID, !tagIDs.contains(fixedTagID) { tagIDs.append(fixedTagID) }
                let dataDaLinha: Date?? = r.due
                let quando: Date? = dataDaLinha ?? dataEscolhida ?? defaultDue
                store.addTask(title: titulo, listID: r.listID ?? chosenListID ?? fixedListID ?? store.defaultList?.id,
                              due: quando, tagIDs: tagIDs,
                              horario: dataDaLinha == nil && quando != nil ? horario : nil)
            }
            limpar()
            return
        }
        let result = parsed
        guard !result.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var tagIDs = store.resolveTags(named: result.tagNames)
        if let fixedTagID, !tagIDs.contains(fixedTagID) { tagIDs.append(fixedTagID) }
        store.addTask(title: result.title, listID: listID, due: due, tagIDs: tagIDs, horario: due == nil ? nil : horario)
        limpar()
    }

    private func limpar() {
        text = ""
        chosenListID = nil
        dropdownAberto = false
        dataAberta = false
        dataEscolhida = nil
        horario = nil
        onAdded?()
    }
}

/// Dropdown de listas (no lugar, sem abrir outra tela): ícones, mesma ordem do app e "Nova lista".
struct DropdownDeListas: View {
    @Environment(TaskStore.self) private var store
    let atual: String?
    let escolher: (String) -> Void
    @State private var criando = false
    @State private var nome = ""
    @FocusState private var focoNome: Bool

    var body: some View {
        VStack(spacing: 1) {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(store.lists) { list in
                        let ativa = list.id == atual
                        Button { escolher(list.id) } label: {
                            HStack(spacing: DS.e2) {
                                ListIconView(listID: list.id, size: 22)
                                Text(store.displayName(list.id)).txt(.sm, ativa ? .semibold : .medium).foregroundStyle(DS.texto)
                                Spacer()
                                if ativa {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.acento)
                                }
                            }
                            .padding(.horizontal, DS.e2)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(Pressionavel(raio: DS.raioP, escala: 0.99))
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 200)
            .indicadorDeRolagem(fundo: DS.superficie)
            .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(DS.borda).frame(height: 1).padding(.vertical, 3)

            if criando {
                HStack(spacing: DS.e2) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.acento)
                        .frame(width: 22)
                    TextField("Nome da nova lista", text: $nome)
                        .textFieldStyle(.plain)
                        .txt(.sm)
                        .focused($focoNome)
                        .onSubmit(criar)
                        .onExitCommand { criando = false }
                    Button("Criar", action: criar).buttonStyle(Botao(variante: .primario))
                        .disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, DS.e2)
                .padding(.vertical, 3)
            } else {
                Button {
                    criando = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focoNome = true }
                } label: {
                    HStack(spacing: DS.e2) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.acento)
                            .frame(width: 22)
                        Text("Nova lista").txt(.sm, .medium).foregroundStyle(DS.acento)
                        Spacer()
                    }
                    .padding(.horizontal, DS.e2)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Pressionavel(raio: DS.raioP, escala: 0.99))
            }
        }
        .padding(DS.e1)
        .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).strokeBorder(DS.borda))
        .sombra()
    }

    private func criar() {
        let limpo = nome.trimmingCharacters(in: .whitespaces)
        guard !limpo.isEmpty else { return }
        Task {
            if let id = await store.createList(title: limpo, symbol: nil, colorHex: nil) {
                escolher(id)
            }
            nome = ""
            criando = false
        }
    }
}
