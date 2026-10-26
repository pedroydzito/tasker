import SwiftUI

/// Campo de nova tarefa: entende datas, ~lista e #etiqueta.
struct QuickAddField: View {
    enum Style { case compact, inline, large, floating }

    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas: Folhas?
    /// Data padrão quando nada é digitado (nil = sem data).
    var defaultDue: Date?
    var fixedListID: String?
    var fixedTagID: String?
    var style: Style = .compact
    var onAdded: (() -> Void)?

    @State private var text = ""
    @State private var chosenListID: String?
    @FocusState private var focused: Bool

    private var parsed: QuickAddParser.Result {
        QuickAddParser.parse(text, lists: store.lists, today: store.today)
    }

    private var listID: String? { parsed.listID ?? fixedListID ?? chosenListID ?? store.defaultList?.id }
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
                if fixedListID == nil { listMenu }
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
                chips.padding(.horizontal, DS.e4).padding(.bottom, style == .floating ? 6 : 0)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(DS.curva, value: text.isEmpty)
        .onAppear { if style == .large { focused = true } }
    }

    private var placeholder: String {
        let name = store.displayName(listID ?? "")
        let list = name.isEmpty ? "Minhas tarefas" : name
        switch style {
        case .large: return "Nova tarefa — ex.: ligar pro cliente amanhã ~\(list.lowercased()) #urgente"
        case .floating: return "Adicionar tarefa em \(list)  ·  ⌥Espaço de qualquer lugar"
        default: return "Adicionar tarefa em \(list)"
        }
    }

    /// Escolha da lista: o ícone da lista atual; abre a grade de listas (com ícones, na ordem do app).
    @ViewBuilder private var listMenu: some View {
        if let folhas {
            Button {
                let atual = listID
                folhas.abrir("Escolher lista", largura: 320) {
                    EscolhaDeLista(atual: atual) { chosenListID = $0 }
                }
            } label: {
                botaoDaLista
            }
            .buttonStyle(Pressionavel(raio: 999, escala: 0.94))
            .help("Escolher lista")
        } else {
            Menu {
                ForEach(store.lists) { list in
                    Button(store.displayName(list.id)) { chosenListID = list.id }
                }
            } label: {
                botaoDaLista
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var botaoDaLista: some View {
        HStack(spacing: 4) {
            if let listID { ListIconView(listID: listID, size: 20, redondo: true) }
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(DS.texto3)
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .contentShape(Capsule())
    }

    private var chips: some View {
        HStack(spacing: DS.e2) {
            if let listID { ListChip(listID: listID) }
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
        onAdded?()
    }
}
