import SwiftUI

/// Visão mensal com tarefas + eventos e a agenda do dia selecionado ao lado.
struct CalendarView: View {
    @Environment(TaskStore.self) private var store
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var monthEvents: [CalendarEvent]?

    private let cal = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                header
                weekdayHeader
                grid
            }
            .padding(.horizontal, 24)
            .padding(.top, 44)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)

            Divider()

            DayAgenda(day: selected, events: events(on: selected))
                .frame(width: 330)
                .background(Theme.surface)
        }
        .task(id: month) {
            let days = gridDays
            guard let first = days.first, let last = days.last else { return }
            monthEvents = await store.loadEvents(from: first, to: cal.adding(days: 1, to: last))
        }
    }

    private func events(on day: Date) -> [CalendarEvent] {
        (monthEvents ?? store.events).filter { $0.overlaps(dayStart: day) }
    }

    private var header: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year()).capitalized)
                .font(.system(size: 22, weight: .bold))
            Spacer()
            Button {
                month = cal.dateInterval(of: .month, for: .now)?.start ?? .now
                selected = store.today
            } label: {
                Text("Hoje").font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 4)
            }
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 26, height: 24) }
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 26, height: 24) }
        }
        .buttonStyle(.pressable)
    }

    private func shift(_ value: Int) {
        month = cal.date(byAdding: .month, value: value, to: month) ?? month
        monthEvents = nil
    }

    private var weekdayHeader: some View {
        let symbols = cal.shortWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return HStack(spacing: 0) {
            ForEach(ordered, id: \.self) { symbol in
                Text(symbol.uppercased().replacingOccurrences(of: ".", with: ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 6 semanas a partir do início da semana que contém o dia 1.
    private var gridDays: [Date] {
        let weekday = cal.component(.weekday, from: month)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let start = cal.adding(days: -leading, to: month)
        return (0..<42).map { cal.adding(days: $0, to: start) }
    }

    private var grid: some View {
        let days = gridDays
        return VStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 4) {
                    ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                        DayCell(day: day,
                                inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                                isToday: day == store.today,
                                isSelected: day == selected,
                                events: events(on: day),
                                tasks: store.tasks(on: day))
                            .onTapGesture { withAnimation(.snappy(duration: 0.18)) { selected = day } }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    @Environment(TaskStore.self) private var store
    let day: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let events: [CalendarEvent]
    let tasks: [TaskItem]
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? AnyShapeStyle(Color.white) : (inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)))
                .frame(width: 22, height: 22)
                .background(Circle().fill(isToday ? Color.accentColor : .clear))
                .padding(.bottom, 1)

            ForEach(events.prefix(2)) { event in
                line(event.title, color: Color(hex: event.colorHex), filled: true)
            }
            ForEach(tasks.prefix(max(0, 3 - min(events.count, 2)))) { task in
                line(task.displayTitle, color: store.color(forList: task.listID), filled: false)
            }
            let extra = events.count + tasks.count - min(events.count, 2) - min(tasks.count, max(0, 3 - min(events.count, 2)))
            if extra > 0 {
                Text("+\(extra)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(inMonth ? Theme.surface : Theme.surface.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : (hovering ? Theme.stroke : .clear),
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func line(_ text: String, color: Color, filled: Bool) -> some View {
        HStack(spacing: 4) {
            if filled {
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2.5, height: 10)
            } else {
                Circle().strokeBorder(color, lineWidth: 1.2).frame(width: 7, height: 7)
            }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 10.5))
        .opacity(inMonth ? 1 : 0.5)
    }
}

private struct DayAgenda: View {
    @Environment(TaskStore.self) private var store
    let day: Date
    let events: [CalendarEvent]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(DayLabel.short(day, today: store.today)).font(.system(size: 20, weight: .bold))
                Text(DayLabel.long(day)).font(.system(size: 13)).foregroundStyle(.secondary)
                EventsCard(events: events)
                QuickAddField(defaultDue: day, style: .inline)
                let tasks = store.tasks(on: day)
                if tasks.isEmpty && events.isEmpty {
                    EmptyState(symbol: "calendar", title: "Dia livre")
                }
                LazyVStack(spacing: 6) {
                    ForEach(tasks) { TaskRow(task: $0, showDate: false) }
                }
            }
            .padding(18)
            .padding(.top, 26)
        }
    }
}
