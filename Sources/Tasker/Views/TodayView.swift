import SwiftUI

/// Layout de página usado pelas telas da janela principal.
struct PageScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 30, weight: .bold))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 6)
                ErrorBanner()
                content
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct TodayView: View {
    @Environment(TaskStore.self) private var store
    @State private var showCompleted = false

    var body: some View {
        PageScaffold(title: "Hoje", subtitle: DayLabel.long(store.today)) {
            EventsCard(events: store.events(on: store.today))

            QuickAddField(defaultDue: store.today, style: .inline)

            VStack(alignment: .leading, spacing: 1) {
                let overdue = store.overdueTasks
                if !overdue.isEmpty {
                    HStack {
                        SectionHeader(title: "Em atraso", count: overdue.count, tint: .red)
                        Button("Mover para hoje") { store.postponeOverdue() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 10)
                    }
                    ForEach(overdue) { TaskRow(task: $0) }
                }

                let today = store.todayTasks
                SectionHeader(title: "Hoje", count: today.count)
                if today.isEmpty {
                    EmptyState(symbol: "sun.max", title: "Nada pendente para hoje", subtitle: "Aproveite o dia ☀️")
                } else {
                    ForEach(today) { TaskRow(task: $0, showDate: false) }
                }

                let done = store.completedToday
                if !done.isEmpty {
                    Button {
                        withAnimation(.snappy) { showCompleted.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showCompleted ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                            SectionHeader(title: "Concluídas hoje", count: done.count)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    if showCompleted {
                        ForEach(done) { TaskRow(task: $0, showDate: false) }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.todayTasks.map(\.id))
        }
    }
}

/// Tarefas e eventos de um único dia (usado em "Amanhã").
struct DayView: View {
    @Environment(TaskStore.self) private var store
    let title: String
    let day: Date

    var body: some View {
        PageScaffold(title: title, subtitle: DayLabel.long(day)) {
            EventsCard(events: store.events(on: day))
            QuickAddField(defaultDue: day, style: .inline)
            let tasks = store.tasks(on: day)
            VStack(alignment: .leading, spacing: 1) {
                if tasks.isEmpty {
                    EmptyState(symbol: "sunrise", title: "Nenhuma tarefa para \(title.lowercased())")
                } else {
                    ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                }
            }
        }
    }
}
