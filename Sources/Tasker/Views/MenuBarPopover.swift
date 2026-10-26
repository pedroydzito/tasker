import SwiftUI

/// Popover da barra de menu: vidro do macOS, abre instantâneo, com abas internas
/// (Hoje, Calendário, Listas) e um botão para abrir o app em tela grande.
struct MenuBarPopover: View {
    enum Tab { case today, calendar, lists }

    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav
    @Environment(\.openWindow) private var openWindow

    @State private var tab: Tab = .today
    @State private var openListID: String?
    @State private var day = Calendar.current.startOfDay(for: .now)

    var body: some View {
        VStack(spacing: 0) {
            if auth.isSignedIn {
                header
                UpdateBanner().padding(.horizontal, 12).padding(.bottom, 6)
                content
            } else {
                signedOut
            }
            tabBar
        }
        .frame(width: 370)
        .background(GlassBackground(material: .popover, cornerRadius: 16))
        .background(PopoverWindowConfigurator(
            appearance: store.prefs.appearance.resolved,
            onOpen: { Task { await store.sync() } }
        ))
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack(spacing: 6) {
            if tab == .lists, let id = openListID {
                Button { openListID = nil } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).iconButtonLabel(size: 26)
                }
                .buttonStyle(.pressable)
                ListIconView(listID: id, size: 22)
                Text(store.displayName(id)).font(.system(size: 19, weight: .bold)).lineLimit(1)
            } else {
                Text(title).font(.system(size: 22, weight: .bold))
            }
            if store.isSyncing {
                ProgressView().controlSize(.mini).padding(.leading, 2)
            }
            Spacer()
            Button { openApp(destination) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").iconButtonLabel()
            }
            .buttonStyle(.pressable)
            .help("Abrir no app em tela grande")
            accountMenu
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var title: String {
        switch tab {
        case .today: "Hoje"
        case .calendar: "Calendário"
        case .lists: "Listas"
        }
    }

    /// Para onde o botão de tela grande leva, conforme a aba atual.
    private var destination: SidebarItem {
        switch tab {
        case .today: .today
        case .calendar: .calendar
        case .lists: openListID.map { .list($0) } ?? .all
        }
    }

    private var accountMenu: some View {
        Menu {
            if let email = auth.profile?.email { Text(email) }
            Button("Sincronizar agora") { Task { await store.sync(force: true) } }
            Button("Ajustes…") { openApp(.settings) }
            Divider()
            Button("Encerrar Tasker") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: Avatar.menuImage(auth.avatar, side: 26))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Conteúdo por aba

    @ViewBuilder private var content: some View {
        switch tab {
        case .today: todayTab
        case .calendar: PopoverCalendarView(day: $day)
        case .lists:
            if let id = openListID { listTab(id) } else { listsIndex }
        }
    }

    private var todayTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickAddField(defaultDue: store.today).padding(.horizontal, 12)
            scroll {
                EventsCard(events: store.events(on: store.today)).padding(.bottom, 2)
                CalendarIssueBanner()
                ErrorBanner()

                let overdue = store.overdueTasks
                if !overdue.isEmpty {
                    HStack {
                        SectionHeader(title: "Em atraso", count: overdue.count, tint: .red)
                        Button("Adiar p/ hoje") { store.postponeOverdue() }
                            .buttonStyle(.pressable)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 10)
                    }
                    .padding(.trailing, 6)
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
        }
    }

    private var listsIndex: some View {
        scroll {
            ForEach(store.lists) { list in
                SidebarRow(title: store.displayName(list.id), count: store.tasks(inList: list.id).count, selected: false) {
                    ListIconView(listID: list.id, size: 22)
                } action: {
                    openListID = list.id
                }
            }
        }
    }

    private func listTab(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickAddField(fixedListID: id).padding(.horizontal, 12)
            scroll {
                let items = store.tasks(inList: id)
                if items.isEmpty {
                    EmptyState(symbol: "checklist", title: "Lista vazia")
                } else {
                    ForEach(items) { TaskRow(task: $0, style: .compact) }
                }
            }
        }
    }

    private func scroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) { content() }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
        .frame(minHeight: 120, maxHeight: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var signedOut: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Conecte sua conta Google").font(.headline)
            Text("Para ver suas tarefas e eventos de hoje.").font(.callout).foregroundStyle(.secondary)
            Button("Configurar…") { openApp(.today) }.buttonStyle(.primary)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }

    // MARK: Abas

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("sun.max", .today)
            tabButton("calendar", .calendar)
            tabButton("list.bullet", .lists)
            Button { openApp(.settings) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .frame(maxWidth: .infinity)
            .help("Ajustes")
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke.opacity(0.7)).frame(height: 1) }
    }

    private func tabButton(_ symbol: String, _ value: Tab) -> some View {
        let selected = tab == value
        return Button {
            if value == .lists && tab == .lists { openListID = nil }
            tab = value
        } label: {
            Image(systemName: selected && symbol == "sun.max" ? "sun.max.fill" : symbol)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 52, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .frame(maxWidth: .infinity)
    }

    private func openApp(_ item: SidebarItem) {
        nav.selection = item
        // Muda a política antes de abrir para a janela já surgir ativa, sem atraso.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openWindow(id: WindowID.main)
    }
}

/// Aba de calendário do popover: faixa da semana + agenda do dia escolhido.
struct PopoverCalendarView: View {
    @Environment(TaskStore.self) private var store
    @Binding var day: Date
    private let cal = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            weekStrip.padding(.horizontal, 12)
            QuickAddField(defaultDue: day).padding(.horizontal, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    let events = store.events(on: day)
                    let tasks = store.tasks(on: day)
                    EventsCard(events: events).padding(.bottom, 2)
                    SectionHeader(title: DayLabel.short(day, today: store.today), count: tasks.count)
                    if tasks.isEmpty && events.isEmpty {
                        EmptyState(symbol: "calendar", title: "Dia livre")
                    }
                    ForEach(tasks) { TaskRow(task: $0, style: .compact, showDate: false) }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
            .frame(minHeight: 120, maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var weekStart: Date {
        cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    }

    private var weekStrip: some View {
        HStack(spacing: 2) {
            Button { day = cal.adding(days: -7, to: day) } label: {
                Image(systemName: "chevron.left").iconButtonLabel(size: 24)
            }
            .buttonStyle(.pressable)

            ForEach(0..<7, id: \.self) { offset in
                let date = cal.adding(days: offset, to: weekStart)
                let selected = date == day
                let isToday = date == store.today
                let busy = !store.tasks(on: date).isEmpty || !store.events(on: date).isEmpty
                Button { day = date } label: {
                    VStack(spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.narrow)).uppercased())
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.subtle)
                        Text("\(cal.component(.day, from: date))")
                            .font(.system(size: 14, weight: selected || isToday ? .bold : .medium))
                            .foregroundStyle(selected ? Color.white : (isToday ? Color.accentColor : .primary))
                        Circle()
                            .fill(selected ? Color.white : Color.accentColor)
                            .frame(width: 4, height: 4)
                            .opacity(busy ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.accentColor : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }

            Button { day = cal.adding(days: 7, to: day) } label: {
                Image(systemName: "chevron.right").iconButtonLabel(size: 24)
            }
            .buttonStyle(.pressable)
        }
    }
}
