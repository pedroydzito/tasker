import SwiftUI

/// Calendário: mês à esquerda (cartões por dia) e agenda do dia escolhido à direita.
struct CalendarView: View {
    @Environment(TaskStore.self) private var store
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var monthEvents: [CalendarEvent]?
    @State private var direcao: CGFloat = 1

    private let cal = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DS.e4) {
                header
                weekdayHeader
                grid
                    .id(month)
                    .transition(.asymmetric(insertion: .offset(x: 28 * direcao).combined(with: .opacity), removal: .opacity))
            }
            .animation(DS.curva, value: month)
            .padding(.horizontal, DS.e8)
            .padding(.top, 56)
            .padding(.bottom, DS.e6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(DS.borda).frame(width: 1)

            DayAgenda(day: selected, events: events(on: selected))
                .frame(width: 340)
                .background(DS.superficie)
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
        CabecalhoTela(rotulo: "calendário", titulo: month.formatted(.dateTime.month(.wide).year()).lowercased())
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: DS.e1) {
                    Button("Hoje") {
                        direcao = month > Date() ? -1 : 1
                        month = cal.dateInterval(of: .month, for: .now)?.start ?? .now
                        selected = store.today
                    }
                    .buttonStyle(.superficie)
                    BotaoIcone(simbolo: "chevron.left", rotulo: "Voltar um mês") { shift(-1) }
                    BotaoIcone(simbolo: "chevron.right", rotulo: "Avançar um mês") { shift(1) }
                }
            }
    }

    private func shift(_ value: Int) {
        direcao = CGFloat(value)
        month = cal.date(byAdding: .month, value: value, to: month) ?? month
        monthEvents = nil
    }

    private var weekdayHeader: some View {
        let symbols = cal.shortStandaloneWeekdaySymbols
        let i = cal.firstWeekday - 1
        let ordered = Array(symbols[i...] + symbols[..<i])
        return HStack(spacing: 6) {
            ForEach(ordered, id: \.self) { symbol in
                Text(symbol.replacingOccurrences(of: ".", with: "")).rotulo().frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, DS.e2)
            }
        }
    }

    private var gridDays: [Date] {
        let weekday = cal.component(.weekday, from: month)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let start = cal.adding(days: -leading, to: month)
        return (0..<42).map { cal.adding(days: $0, to: start) }
    }

    private var grid: some View {
        let days = gridDays
        return VStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 6) {
                    ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                        DayCell(day: day,
                                inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                                isToday: day == store.today,
                                isSelected: day == selected,
                                events: events(on: day),
                                tasks: store.tasks(on: day)) {
                            withAnimation(DS.curvaRapida) { selected = day }
                        }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .txt(.sm, isToday ? .bold : .medium)
                    .foregroundStyle(isToday ? DS.acentoSolidoTexto : (inMonth ? DS.texto : DS.texto3))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isToday ? DS.acentoSolido : .clear))
                    .padding(.bottom, 1)

                ForEach(events.prefix(2)) { event in
                    linha(event.title, cor: Color(hex: event.colorHex), evento: true)
                }
                ForEach(tasks.prefix(max(0, 3 - min(events.count, 2)))) { task in
                    linha(task.displayTitle, cor: store.color(forList: task.listID), evento: false)
                }
                let shown = min(events.count, 2) + min(tasks.count, max(0, 3 - min(events.count, 2)))
                let extra = events.count + tasks.count - shown
                if extra > 0 {
                    Text("+\(extra)").txt(.xs, .medium).foregroundStyle(DS.texto3).padding(.leading, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                .fill(inMonth ? DS.superficie : DS.superficie.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                .strokeBorder(isSelected ? DS.acento : DS.borda, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressionavel(raio: DS.raioM, escala: 0.98))
    }

    private func linha(_ text: String, cor: Color, evento: Bool) -> some View {
        HStack(spacing: 4) {
            if evento {
                Capsule().fill(cor).frame(width: 2.5, height: 10)
            } else {
                Circle().strokeBorder(cor, lineWidth: 1.3).frame(width: 7, height: 7)
            }
            Text(text).lineLimit(1)
        }
        .txt(.xs)
        .foregroundStyle(inMonth ? DS.texto2 : DS.texto3)
    }
}

private struct DayAgenda: View {
    @Environment(TaskStore.self) private var store
    let day: Date
    let events: [CalendarEvent]

    var body: some View {
        let tasks = store.tasks(on: day)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.e5) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(DayLabel.long(day)).rotulo()
                    Text(DayLabel.short(day, today: store.today).lowercased()).display(.titulo).foregroundStyle(DS.texto)
                }
                QuickAddField(defaultDue: day, style: .inline)
                EventsCard(events: events, compacto: true)
                if tasks.isEmpty && events.isEmpty {
                    EstadoVazio(icone: "calendar", titulo: "dia livre")
                } else if !tasks.isEmpty {
                    SecaoTarefas("tarefas", contagem: tasks.count) {
                        ForEach(tasks) { TaskRow(task: $0, style: .compact, showDate: false) }
                    }
                }
            }
            .padding(DS.e6)
            .padding(.top, 32)
        }
        .scrollIndicators(.never)
    }
}
