import SwiftUI

struct MainWindow: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav

    var body: some View {
        Group {
            if auth.isSignedIn {
                split
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        // Com a janela aberta o app aparece no Dock e no ⌘Tab; fechada, volta a viver só na barra de menu.
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    private var split: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HotkeyTip()
            }
            .inspector(isPresented: Binding(
                get: { nav.selectedTaskID != nil && store.tasks[nav.selectedTaskID ?? ""] != nil },
                set: { if !$0 { nav.selectedTaskID = nil } }
            )) {
                if let id = nav.selectedTaskID, let task = store.tasks[id] {
                    TaskEditor(task: task, isInspector: true) { nav.selectedTaskID = nil }
                        .id(task.id)
                        .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.sync(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(store.isSyncing ? 360 : 0))
                        .animation(store.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                   value: store.isSyncing)
                }
                .help("Sincronizar agora")
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch nav.selection ?? .today {
        case .today: TodayView()
        case .tomorrow: DayView(title: "Amanhã", day: Calendar.current.adding(days: 1, to: store.today))
        case .upcoming: UpcomingView()
        case .calendar: CalendarView()
        case .completed: CompletedView()
        case .all: AllTasksView()
        case .list(let id): ListDetailView(listID: id)
        case .tag(let id): TagDetailView(tagID: id)
        case .settings: SettingsView()
        }
    }
}

/// Dica do atalho global, como no rodapé do KiteTasks.
struct HotkeyTip: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        if !store.prefs.hotkeyTipDismissed {
            HStack(spacing: 8) {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                Text("Pressione **⌥Espaço** para adicionar uma tarefa de qualquer lugar — mesmo fora do Tasker")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { store.prefs.hotkeyTipDismissed = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.03))
            .overlay(alignment: .top) { Divider() }
        }
    }
}
