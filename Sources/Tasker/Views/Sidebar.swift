import SwiftUI

struct Sidebar: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav

    @State private var newTag = ""
    @State private var addingTag = false

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selection) {
            account
                .listRowSeparator(.hidden)
                .selectionDisabled()

            Section {
                row("Hoje", "sun.max", .today, store.badgeCount)
                row("Amanhã", "sunrise", .tomorrow, store.tasks(on: Calendar.current.adding(days: 1, to: store.today)).count)
                row("Próximas", "calendar.day.timeline.left", .upcoming)
                row("Calendário", "calendar", .calendar)
                row("Todas", "tray.full", .all, store.activeCount)
                row("Concluídas", "checkmark.circle", .completed, store.completedTasks.count)
            }

            Section("Listas") {
                ForEach(store.lists) { list in
                    Label {
                        HStack {
                            Text(list.title).lineLimit(1)
                            Spacer()
                            count(store.tasks(inList: list.id).count)
                        }
                    } icon: {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(store.color(forList: list.id))
                    }
                    .tag(SidebarItem.list(list.id))
                }
            }

            Section {
                ForEach(store.tags) { tag in
                    Label {
                        HStack {
                            Text(tag.name).lineLimit(1)
                            Spacer()
                            count(store.tasks(withTag: tag.id).count)
                        }
                    } icon: {
                        Image(systemName: "tag.fill").foregroundStyle(Color(hex: tag.colorHex))
                    }
                    .tag(SidebarItem.tag(tag.id))
                    .contextMenu {
                        Button("Excluir etiqueta", role: .destructive) {
                            if nav.selection == .tag(tag.id) { nav.selection = .today }
                            store.deleteTag(tag)
                        }
                    }
                }
                if store.tags.isEmpty {
                    Text("Use #etiqueta ao criar uma tarefa. Etiquetas ficam só no Tasker.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
            } header: {
                HStack {
                    Text("Etiquetas")
                    Spacer()
                    Button { addingTag = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .help("Nova etiqueta")
                        .popover(isPresented: $addingTag) {
                            HStack {
                                TextField("Nome", text: $newTag)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .onSubmit(createTag)
                                Button("Criar", action: createTag)
                            }
                            .padding(10)
                        }
                }
            }

            Section {
                row("Ajustes", "gearshape", .settings)
            }
        }
        .listStyle(.sidebar)
    }

    private var account: some View {
        HStack(spacing: 10) {
            Avatar(profile: auth.profile, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(auth.profile?.name ?? "Conta Google").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(auth.profile?.email ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    private func row(_ title: String, _ symbol: String, _ item: SidebarItem, _ value: Int? = nil) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if let value, value > 0 { count(value) }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
        }
        .tag(item)
    }

    private func count(_ value: Int) -> some View {
        Text("\(value)").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
    }

    private func createTag() {
        let name = newTag.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.createTag(name: name)
        newTag = ""
        addingTag = false
    }
}
