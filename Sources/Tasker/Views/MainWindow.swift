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
        .frame(minWidth: 860, minHeight: 540)
        // Com a janela aberta o app aparece no Dock e no ⌘Tab; fechada, volta a viver só na barra de menu.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.appearance = store.prefs.appearance.nsAppearance
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .onChange(of: store.prefs.appearance) { _, value in NSApp.appearance = value.nsAppearance }
    }

    private var split: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            ZStack {
                detail
                    .id(nav.selection)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: nav.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
                .overlay(alignment: .bottom) { floatingBar }
                .inspector(isPresented: Binding(
                    get: { nav.selectedTaskID != nil && store.tasks[nav.selectedTaskID ?? ""] != nil },
                    set: { if !$0 { nav.selectedTaskID = nil } }
                )) {
                    if let id = nav.selectedTaskID, let task = store.tasks[id] {
                        TaskInspector(task: task) { nav.selectedTaskID = nil }
                            .id(task.id)
                            .inspectorColumnWidth(min: 320, ideal: 400, max: 520)
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

    /// Barra flutuante de nova tarefa (como o "Speak or Type task" da referência).
    @ViewBuilder private var floatingBar: some View {
        let selection = nav.selection ?? .today
        if selection != .settings && selection != .calendar && selection != .completed {
            let tomorrow = Calendar.current.adding(days: 1, to: store.today)
            let context: (due: Date?, list: String?, tag: String?) = switch selection {
            case .today: (store.today, nil, nil)
            case .tomorrow, .upcoming: (tomorrow, nil, nil)
            case .list(let id): (nil, id, nil)
            case .tag(let id): (nil, nil, id)
            default: (nil, nil, nil)
            }
            QuickAddField(defaultDue: context.due, fixedListID: context.list, fixedTagID: context.tag, style: .floating)
                .id("\(selection)")
                .padding(4)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .frame(maxWidth: 640)
                .padding(.horizontal, 30)
                .padding(.bottom, 18)
        }
    }
}
