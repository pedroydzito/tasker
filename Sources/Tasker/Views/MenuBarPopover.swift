import SwiftUI

/// Popover da barra de menu — base no KiteTasks: título, campo de adicionar, eventos e tarefas de hoje.
struct MenuBarPopover: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav
    @Environment(\.openWindow) private var openWindow
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            if auth.isSignedIn {
                content
            } else {
                signedOut
            }
            bottomBar
        }
        .frame(width: 370)
        .background(Theme.surface)
        // Entrada com mola a cada abertura do menu.
        .scaleEffect(shown ? 1 : 0.96, anchor: .top)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : -8)
        .background(PopoverWindowConfigurator(
            appearance: store.prefs.appearance.resolved,
            onOpen: {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { shown = true }
                Task { await store.sync() }
            },
            onClose: { shown = false }
        ))
        .onAppear {
            if !shown { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { shown = true } }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Hoje").font(.system(size: 22, weight: .bold))
                if store.isSyncing {
                    ProgressView().controlSize(.mini).padding(.leading, 2)
                }
                Spacer()
                accountMenu
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            UpdateBanner().padding(.horizontal, 12)

            QuickAddField(defaultDue: store.today)
                .padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    EventsCard(events: store.events(on: store.today))
                        .padding(.bottom, 2)
                    CalendarIssueBanner()
                    ErrorBanner()

                    let overdue = store.overdueTasks
                    if !overdue.isEmpty {
                        HStack {
                            SectionHeader(title: "Em atraso", count: overdue.count, tint: .red)
                            Button("Adiar p/ hoje") { store.postponeOverdue() }
                                .buttonStyle(.pressable)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 10)
                        }
                        .padding(.trailing, 10)
                        ForEach(overdue) { TaskRow(task: $0, style: .compact) }
                    }

                    let today = store.todayTasks
                    SectionHeader(title: "Hoje", count: today.count)
                    if today.isEmpty {
                        EmptyState(symbol: "checkmark.circle", title: "Tudo feito por hoje")
                    } else {
                        ForEach(today) { TaskRow(task: $0, style: .compact) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
                .animation(.easeInOut(duration: 0.2), value: store.todayTasks.map(\.id))
            }
            .frame(minHeight: 120, maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signedOut: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Conecte sua conta Google").font(.headline)
            Text("Para ver suas tarefas e eventos de hoje.").font(.callout).foregroundStyle(.secondary)
            Button("Configurar…") { open(.today) }.buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
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
            Image(nsImage: Avatar.menuImage(auth.avatar, side: 26))
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
        .background(Theme.group.opacity(0.6))
        .overlay(alignment: .top) { Divider() }
    }

    private func barButton(_ symbol: String, _ help: String, _ item: SidebarItem) -> some View {
        Button { open(item) } label: {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(item == .today ? Color.accentColor : .secondary)
                .frame(width: 44, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .frame(maxWidth: .infinity)
        .help(help)
    }

    private func open(_ item: SidebarItem) {
        nav.selection = item
        // Muda a política antes de abrir para a janela já surgir ativa, sem atraso.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openWindow(id: WindowID.main)
    }
}
