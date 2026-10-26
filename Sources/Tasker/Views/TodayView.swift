import SwiftUI

/// Layout de página das telas da janela principal.
struct PageScaffold<Header: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    header
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 28, weight: .bold))
                        if let subtitle {
                            Text(subtitle).font(.system(size: 13.5)).foregroundStyle(Theme.subtle)
                        }
                    }
                }
                .padding(.bottom, 4)
                CalendarIssueBanner()
                ErrorBanner()
                content
            }
            .padding(.horizontal, 36)
            .padding(.top, 26)
            .padding(.bottom, 120)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

extension PageScaffold where Header == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.header = EmptyView()
        self.content = content()
    }
}

func taskCountText(_ count: Int) -> String {
    count == 0 ? "Nada pendente" : "\(count) tarefa\(count == 1 ? "" : "s") para concluir"
}

struct TodayView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        let overdue = store.overdueTasks
        let today = store.todayTasks
        let done = store.completedToday
        PageScaffold(title: "Hoje",
                     subtitle: "\(DayLabel.long(store.today).capitalized) · \(taskCountText(overdue.count + today.count))") {
            EventsCard(events: store.events(on: store.today))

            if !overdue.isEmpty {
                TaskSection("Em atraso", count: overdue.count, tint: .red,
                            accessory: AnyView(Button("Mover para hoje") { store.postponeOverdue() }
                                .buttonStyle(.pressable)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.accentColor))) {
                    ForEach(overdue) { TaskRow(task: $0) }
                }
            }

            TaskSection("Hoje", count: today.count) {
                if today.isEmpty {
                    EmptyState(symbol: "sun.max", title: "Nada pendente para hoje", subtitle: "Aproveite o dia")
                } else {
                    ForEach(today) { TaskRow(task: $0, showDate: false) }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: today.map(\.id))

            if !done.isEmpty {
                TaskSection("Concluídas hoje", count: done.count, startCollapsed: true) {
                    ForEach(done) { TaskRow(task: $0, showDate: false) }
                }
            }
        }
    }
}

/// Tarefas e eventos de um único dia (usado em "Amanhã").
struct DayView: View {
    @Environment(TaskStore.self) private var store
    let title: String
    let day: Date

    var body: some View {
        let tasks = store.tasks(on: day)
        PageScaffold(title: title, subtitle: "\(DayLabel.long(day).capitalized) · \(taskCountText(tasks.count))") {
            EventsCard(events: store.events(on: day))
            TaskSection(title, count: tasks.count) {
                if tasks.isEmpty {
                    EmptyState(symbol: "sunrise", title: "Nenhuma tarefa para \(title.lowercased())")
                } else {
                    ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                }
            }
        }
    }
}
