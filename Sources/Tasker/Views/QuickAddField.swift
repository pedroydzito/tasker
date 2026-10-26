import SwiftUI

/// Campo "Adicionar tarefa a <lista>" com seletor de lista e reconhecimento de datas.
struct QuickAddField: View {
    enum Style { case compact, inline, large }

    @Environment(TaskStore.self) private var store
    /// Data padrão quando nada é digitado (nil = sem data).
    var defaultDue: Date?
    var fixedListID: String?
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: style == .large ? 17 : 13, weight: .medium))
                    .foregroundStyle(style == .inline ? Color.accentColor : .secondary)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: style == .large ? 18 : 14))
                    .focused($focused)
                    .onSubmit(submit)
                if fixedListID == nil {
                    listMenu
                }
            }
            .padding(.horizontal, style == .inline ? 10 : 12)
            .padding(.vertical, style == .large ? 12 : 9)
            .background {
                if style != .inline {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05))
                }
            }

            if !text.isEmpty {
                chips.padding(.horizontal, 12).transition(.opacity)
            }
        }
        .onAppear { if style == .large { focused = true } }
    }

    private var placeholder: String {
        let name = store.list(listID ?? "")?.title ?? "Minhas tarefas"
        return style == .large ? "Nova tarefa — ex.: Ligar pro cliente amanhã ~\(QuickAddParser.normalizedListName(name).lowercased()) #urgente"
                               : "Adicionar tarefa a \"\(name)\""
    }

    private var listMenu: some View {
        Menu {
            ForEach(store.lists) { list in
                Button {
                    chosenListID = list.id
                } label: {
                    if list.id == listID { Label(list.title, systemImage: "checkmark") } else { Text(list.title) }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Escolher lista")
    }

    private var chips: some View {
        HStack(spacing: 6) {
            if let list = store.list(listID ?? "") {
                ListBadge(title: list.title, color: store.color(forList: list.id))
            }
            if let due {
                DueBadge(day: due, today: store.today, filled: true)
            } else {
                Text("Sem data").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(parsed.tagNames, id: \.self) { name in
                TagChip(name: name, color: store.tags.first { $0.name.lowercased() == name.lowercased() }
                    .map { Color(hex: $0.colorHex) } ?? .secondary)
            }
            Spacer()
            Text("↩︎ para adicionar").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    private func submit() {
        let result = parsed
        guard !result.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.addTask(title: result.title, listID: listID, due: due, tagIDs: store.resolveTags(named: result.tagNames))
        text = ""
        onAdded?()
    }
}
