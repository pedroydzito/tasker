import SwiftUI

/// Calendário: mês à esquerda (cartões por dia) e agenda do dia escolhido à direita.
struct CalendarView: View {
    @Environment(TaskStore.self) private var store
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var monthEvents: [CalendarEvent]?
    @State private var direcao: CGFloat = 1
    @AppStorage("larguraAgendaCalendario") private var larguraAgenda: Double = 340

    private let cal = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            // Rolável: o mês nunca passa da altura da janela (antes empurrava a barra lateral).
            ScrollView {
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
            }
            .scrollIndicators(.automatic)
            .indicadorDeRolagem()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divisoria(largura: $larguraAgenda, minimo: 280, maximo: 520, sentido: -1)

            DayAgenda(day: selected, events: events(on: selected))
                .frame(width: larguraAgenda)
                .background(DS.superficie)
        }
        .task(id: month) {
            // Meses já sincronizados abrem na hora; só os de fora buscam na rede.
            let days = gridDays
            guard let first = days.first, let last = days.last else { return }
            let end = cal.adding(days: 1, to: last)
            if let range = store.eventRange, range.contains(first), range.contains(last) {
                monthEvents = nil
                return
            }
            monthEvents = await store.loadEvents(from: first, to: end)
        }
    }

    private func events(on day: Date) -> [CalendarEvent] {
        monthEvents.map { $0.filter { $0.overlaps(dayStart: day) } } ?? store.events(on: day)
    }

    private var header: some View {
        CabecalhoTela(rotulo: "Calendário", titulo: month.formatted(.dateTime.month(.wide).year()).primeiraMaiuscula)
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
                                tasks: store.tasks(on: day) + store.completedTasks(on: day)) {
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

    private enum Item: Identifiable {
        case evento(CalendarEvent)
        case tarefa(TaskItem)

        var id: String {
            switch self {
            case .evento(let e): "e\(e.id)"
            case .tarefa(let t): "t\(t.id)"
            }
        }
    }

    var body: some View {
        let itens = events.map(Item.evento) + tasks.map(Item.tarefa)
        // No máximo 2 itens; com mais, 2 + "+N" — a célula nunca cresce.
        let visiveis = itens.count <= 2 ? itens : Array(itens.prefix(2))
        let extra = itens.count - visiveis.count
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .txt(.sm, isToday ? .bold : .medium)
                    .foregroundStyle(isToday ? DS.acentoSolidoTexto : (inMonth ? DS.texto : DS.texto3))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(isToday ? DS.acentoSolido : .clear))
                    .padding(.bottom, 1)

                ForEach(visiveis) { item in
                    switch item {
                    case .evento(let event):
                        linha(event.title, cor: Color(hex: event.colorHex), evento: true,
                              passado: event.end < .now, riscado: false)
                    case .tarefa(let task):
                        linha(task.displayTitle, cor: store.color(forList: task.listID), evento: false,
                              passado: task.isCompleted, riscado: task.isCompleted)
                    }
                }
                if extra > 0 {
                    Text("+\(extra)").txt(.xs, .semibold).foregroundStyle(DS.texto3).padding(.leading, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 84, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                .fill(inMonth ? DS.superficie : DS.superficie.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                .strokeBorder(isSelected ? DS.acento : DS.borda, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressionavel(raio: DS.raioM, escala: 0.98))
    }

    private func linha(_ text: String, cor: Color, evento: Bool, passado: Bool, riscado: Bool) -> some View {
        HStack(spacing: 4) {
            if evento {
                Capsule().fill(cor).frame(width: 2.5, height: 10)
            } else {
                Circle().strokeBorder(cor, lineWidth: 1.3).frame(width: 7, height: 7)
            }
            Text(text).lineLimit(1).strikethrough(riscado, color: DS.texto3)
        }
        .txt(.xs)
        .foregroundStyle(inMonth ? DS.texto2 : DS.texto3)
        .opacity(passado ? 0.45 : 1)
    }
}

private struct DayAgenda: View {
    @Environment(TaskStore.self) private var store
    let day: Date
    let events: [CalendarEvent]

    var body: some View {
        let tasks = store.tasks(on: day) + store.completedTasks(on: day)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.e5) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(DayLabel.long(day)).rotulo()
                    Text(DayLabel.short(day, today: store.today)).display(.titulo).foregroundStyle(DS.texto)
                }
                QuickAddField(defaultDue: day, style: .inline)
                EventsCard(events: events, compacto: true)
                if tasks.isEmpty && events.isEmpty {
                    EstadoVazio(icone: "calendar", titulo: "Dia livre")
                } else if !tasks.isEmpty {
                    CartaoDeLinhas(recuoDoFio: 44) {
                        ForEach(tasks) { TaskRow(task: $0, style: .compact, showDate: false) }
                    }
                }
            }
            .padding(DS.e6)
            .padding(.top, 32)
        }
        .scrollIndicators(.never)
        .indicadorDeRolagem(fundo: DS.superficie)
    }
}
