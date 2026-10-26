import SwiftUI

/// Conteúdo do popover da barra de menu (visual do KiteTasks, mais enxuto).
struct MenuBarPopover: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            if auth.isSignedIn {
                content
            } else {
                signedOut
            }
            Divider()
            bottomBar
        }
        .frame(width: 380)
        .task { await store.sync() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hoje").font(.system(size: 24, weight: .bold))
                if store.isSyncing {
                    ProgressView().controlSize(.small).padding(.leading, 4)
                }
                Spacer()
                accountMenu
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            UpdateBanner()
                .padding(.horizontal, 14)

            QuickAddField(defaultDue: store.today)
                .padding(.horizontal, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    EventsCard(events: store.events(on: store.today))
                        .padding(.bottom, 4)

                    ErrorBanner()

                    let overdue = store.overdueTasks
                    if !overdue.isEmpty {
                        HStack {
                            SectionHeader(title: "Em atraso", count: overdue.count, tint: .red)
                            Button("Adiar") { store.postponeOverdue() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 10)
                                .help("Mover todas as tarefas atrasadas para hoje")
                        }
                        .padding(.trailing, 10)
                        ForEach(overdue) { TaskRow(task: $0, style: .compact) }
                    }

                    let today = store.todayTasks
                    SectionHeader(title: "Hoje", count: today.count)
                    if today.isEmpty {
                        EmptyState(symbol: "checkmark.circle", title: "Tudo feito por hoje")
                    } else {
                        ForEach(today) { TaskRow(task: $0, style: .compact, showDate: false) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
                .animation(.easeInOut(duration: 0.2), value: store.todayTasks.map(\.id))
            }
            .frame(minHeight: 140, maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signedOut: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Conecte sua conta Google").font(.headline)
            Text("Para ver suas tarefas e eventos de hoje.").font(.callout).foregroundStyle(.secondary)
            Button("Configurar…") { open(.today) }.buttonStyle(.borderedProminent)
        }
        .padding(30)
    }

    private var accountMenu: some View {
        Menu {
            if let email = auth.profile?.email { Text(email) }
            Button("Abrir Tasker") { open(.today) }
            Button("Sincronizar agora") { Task { await store.sync(force: true) } }
            Divider()
            Button("Ajustes…") { open(.settings) }
            Button("Encerrar Tasker") { NSApp.terminate(nil) }
        } label: {
            Avatar(profile: auth.profile, size: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var bottomBar: some View {
        HStack {
            barButton("sun.max", "Hoje", .today)
            barButton("calendar", "Calendário", .calendar)
            barButton("list.bullet", "Todas", .all)
            barButton("gearshape", "Ajustes", .settings)
        }
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private func barButton(_ symbol: String, _ help: String, _ item: SidebarItem) -> some View {
        Button { open(item) } label: {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(item == .today ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func open(_ item: SidebarItem) {
        nav.selection = item
        openWindow(id: WindowID.main)
        NSApp.activate()
    }
}
