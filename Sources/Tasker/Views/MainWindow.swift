import SwiftUI

struct MainWindow: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav

    var body: some View {
        Group {
            if auth.isSignedIn {
                layout
            } else {
                OnboardingView().background(Theme.canvas)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 880, minHeight: 560)
        // Com a janela aberta o app aparece no Dock e no ⌘Tab; fechada, volta a viver só na barra de menu.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.appearance = store.prefs.appearance.nsAppearance
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .onChange(of: store.prefs.appearance) { _, value in NSApp.appearance = value.nsAppearance }
    }

    private var layout: some View {
        let selectedTask = nav.selectedTaskID.flatMap { store.tasks[$0] }
        return HStack(spacing: 0) {
            Sidebar()
                .frame(width: 250)
                .background(GlassBackground(material: .sidebar))

            Rectangle().fill(Theme.stroke).frame(width: 1)

            ZStack(alignment: .bottom) {
                ZStack {
                    detail
                        .id(nav.selection)
                        .transition(.opacity)
                }
                .animation(.easeOut(duration: 0.14), value: nav.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                floatingBar
            }
            .background(Theme.canvas)

            if let task = selectedTask {
                Rectangle().fill(Theme.stroke).frame(width: 1)
                TaskInspector(task: task) { nav.selectedTaskID = nil }
                    .id(task.id)
                    .frame(width: 400)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selectedTask?.id)
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

    /// Barra flutuante de nova tarefa.
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
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
                .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
                .frame(maxWidth: 620)
                .padding(.horizontal, 30)
                .padding(.bottom, 18)
        }
    }
}
