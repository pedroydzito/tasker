import SwiftUI

/// Campo de nova tarefa com seletor de lista e reconhecimento de datas, ~lista e #etiqueta.
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: fontSize - 1, weight: .medium))
                    .foregroundStyle(style == .inline || style == .floating ? Color.accentColor : .secondary)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: fontSize))
                    .focused($focused)
                    .onSubmit(submit)
                if fixedListID == nil { listMenu }
                if style == .floating {
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(text.isEmpty ? Theme.subtle.opacity(0.5) : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.isEmpty)
                }
            }
            .padding(.horizontal, style == .inline ? 10 : 14)
            .padding(.vertical, verticalPadding)
            .background {
                if style == .compact || style == .large {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field)
                }
            }

            if !text.isEmpty {
                chips.padding(.horizontal, 14).padding(.bottom, style == .floating ? 4 : 0).transition(.opacity)
            }
        }
        .onAppear { if style == .large { focused = true } }
    }

    private var fontSize: CGFloat {
        switch style {
        case .large: 18
        case .floating: 14.5
        default: 14
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .large: 12
        case .floating: 8
        default: 9
        }
    }

    private var placeholder: String {
        let name = store.displayName(listID ?? "")
        let list = name.isEmpty ? "Minhas tarefas" : name
        switch style {
        case .large: return "Nova tarefa — ex.: Ligar pro cliente amanhã ~\(list.lowercased()) #urgente"
        case .floating: return "Adicionar tarefa a \"\(list)\"…   ⌥Espaço de qualquer lugar"
        default: return "Adicionar tarefa a \"\(list)\""
        }
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
        HStack(spacing: 8) {
            if let listID { ListChip(listID: listID) }
            if let due {
                DueLabel(day: due, today: store.today)
            } else {
                Text("Sem data").foregroundStyle(Theme.subtle)
            }
            ForEach(parsed.tagNames, id: \.self) { name in
                TagChip(name: name, color: store.tags.first { $0.name.lowercased() == name.lowercased() }
                    .map { Color(hex: $0.colorHex) } ?? .secondary)
            }
            Spacer()
            Text("↩︎ para adicionar").foregroundStyle(.tertiary)
        }
        .font(.system(size: 11.5))
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
