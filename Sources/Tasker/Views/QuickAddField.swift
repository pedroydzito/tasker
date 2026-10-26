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

    @State private var text = ""
    @State private var chosenListID: String?
    @State private var dropdownAberto = false
    @FocusState private var focused: Bool

    private var parsed: QuickAddParser.Result {
        QuickAddParser.parse(text, lists: store.lists, today: store.today)
    }

    private var listID: String? { parsed.listID ?? chosenListID ?? fixedListID ?? store.defaultList?.id }
    private var due: Date? {
        if let explicit = parsed.due { return explicit }
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
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .txt(style == .large ? .lg : .md)
                    .foregroundStyle(DS.texto)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand {
                        if dropdownAberto { withAnimation(DS.curva) { dropdownAberto = false } } else { text = "" }
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
        .onChange(of: text) { _, novo in if novo.isEmpty { dropdownAberto = false } }
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
                    withAnimation(DS.curva) { dropdownAberto.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        ListChip(listID: listID)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DS.texto3)
                            .rotationEffect(.degrees(dropdownAberto ? 180 : 0))
                    }
                }
                .buttonStyle(SoAfunda(escala: 0.95))
                .help("Trocar a lista")
            }
            Chip(due.map { DayLabel.short($0, today: store.today) } ?? "Sem data") {
                Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
            }
            ForEach(parsed.tagNames, id: \.self) { name in
                Chip("#\(name)", cor: store.tags.first { $0.name.lowercased() == name.lowercased() }
                    .map { Color(hex: $0.colorHex) } ?? DS.texto2)
            }
            Spacer()
            Text("↩︎ Adicionar").txt(.xs).foregroundStyle(DS.texto3)
        }
    }

    private func submit() {
        let result = parsed
        guard !result.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var tagIDs = store.resolveTags(named: result.tagNames)
        if let fixedTagID, !tagIDs.contains(fixedTagID) { tagIDs.append(fixedTagID) }
        store.addTask(title: result.title, listID: listID, due: due, tagIDs: tagIDs)
        text = ""
        chosenListID = nil
        dropdownAberto = false
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
                        Text("Nova lista").txt(.sm, .medium).foregroundStyle(DS.acentoTexto)
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
