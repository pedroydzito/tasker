import SwiftUI

/// Barra lateral própria: vidro, ícones coloridos, seleção em pílula e status de sincronização no rodapé.
struct Sidebar: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav

    @State private var addingTag = false
    @State private var editingListID: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    account.padding(.bottom, 14)

                    item(.today, "Hoje", "sun.max.fill", .orange, store.badgeCount)
                    item(.tomorrow, "Amanhã", "sunrise.fill", .indigo,
                         store.tasks(on: Calendar.current.adding(days: 1, to: store.today)).count)
                    item(.upcoming, "Próximas", "calendar.day.timeline.left", .red)
                    item(.calendar, "Calendário", "calendar", .blue)
                    item(.all, "Todas", "tray.full.fill", .teal, store.activeCount)
                    item(.completed, "Concluídas", "checkmark.circle.fill", .green)

                    header("Listas").padding(.top, 16)
                    ForEach(store.lists) { list in
                        SidebarRow(title: store.displayName(list.id),
                                   count: store.tasks(inList: list.id).count,
                                   selected: nav.selection == .list(list.id)) {
                            ListIconView(listID: list.id, size: 20)
                        } action: {
                            select(.list(list.id))
                        }
                        .contextMenu {
                            Button("Personalizar ícone e cor…") { editingListID = list.id }
                        }
                        .popover(isPresented: Binding(
                            get: { editingListID == list.id },
                            set: { if !$0 { editingListID = nil } }
                        ), arrowEdge: .trailing) {
                            ListAppearanceEditor(listID: list.id)
                        }
                    }

                    HStack {
                        header("Etiquetas")
                        Spacer()
                        Button { addingTag = true } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).iconButtonLabel(size: 22)
                        }
                        .buttonStyle(.pressable)
                        .help("Nova etiqueta")
                        .popover(isPresented: $addingTag, arrowEdge: .trailing) {
                            TagCreator { tag in
                                addingTag = false
                                select(.tag(tag.id))
                            }
                        }
                    }
                    .padding(.top, 16)

                    ForEach(store.tags) { tag in
                        SidebarRow(title: tag.name, count: store.tasks(withTag: tag.id).count,
                                   selected: nav.selection == .tag(tag.id)) {
                            Image(systemName: "number")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: tag.colorHex))
                        } action: {
                            select(.tag(tag.id))
                        }
                        .contextMenu {
                            Button("Excluir etiqueta", role: .destructive) {
                                if nav.selection == .tag(tag.id) { nav.selection = .today }
                                store.deleteTag(tag)
                            }
                        }
                    }
                    if store.tags.isEmpty {
                        Text("Digite #etiqueta ao criar uma tarefa.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.subtle)
                            .padding(.horizontal, 10)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 44) // espaço dos botões da janela
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            footer
        }
    }

    private var account: some View {
        Menu {
            if let email = auth.profile?.email { Text(email) }
            Button("Ajustes…") { select(.settings) }
            Divider()
            Button("Sair da conta") {
                auth.signOut()
                store.reset()
            }
        } label: {
            HStack(spacing: 10) {
                Avatar(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(auth.profile?.name ?? "Conta Google").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(auth.profile?.email ?? "").font(.system(size: 11)).foregroundStyle(Theme.subtle).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.pressable)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            SyncStatusButton()
            Spacer()
            Button { select(.settings) } label: {
                Image(systemName: "gearshape").iconButtonLabel()
                    .foregroundStyle(nav.selection == .settings ? Color.accentColor : .secondary)
            }
            .buttonStyle(.pressable)
            .help("Ajustes")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.subtle)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }

    private func item(_ selection: SidebarItem, _ title: String, _ symbol: String, _ tint: Color, _ count: Int? = nil) -> some View {
        SidebarRow(title: title, count: count, selected: nav.selection == selection) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
        } action: {
            select(selection)
        }
    }

    private func select(_ item: SidebarItem) {
        nav.selection = item
    }
}

struct SidebarRow<Icon: View>: View {
    let title: String
    var count: Int?
    let selected: Bool
    @ViewBuilder var icon: Icon
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon.frame(width: 20, height: 20)
                Text(title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.subtle)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.surface : (hovering ? Theme.hover : .clear))
                    .shadow(color: .black.opacity(selected ? 0.07 : 0), radius: 2, y: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: selected)
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// "Sincronizado há 2 min" — clique para sincronizar agora.
struct SyncStatusButton: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        Button {
            Task { await store.sync(force: true) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(store.isSyncing ? 360 : 0))
                    .animation(store.isSyncing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: store.isSyncing)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(label(now: context.date)).lineLimit(1)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(store.lastError == nil ? Theme.subtle : Color.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .buttonStyle(.pressable)
        .help(store.lastError ?? "Sincronizar agora")
    }

    private func label(now: Date) -> String {
        if store.isSyncing { return "Sincronizando…" }
        if store.lastError != nil { return "Erro ao sincronizar" }
        guard let last = store.lastSync else { return "Sincronizar" }
        let seconds = Int(now.timeIntervalSince(last))
        if seconds < 60 { return "Sincronizado agora" }
        if seconds < 3600 { return "Sincronizado há \(seconds / 60) min" }
        return "Sincronizado há \(seconds / 3600) h"
    }
}
