import SwiftUI

/// Menu da barra (base KiteTasks, com o design system): mesmo fundo do app, altura fixa
/// (abre sempre do mesmo tamanho), abas internas e botão para abrir em tela grande.
struct MenuBarPopover: View {
    enum Tab: Hashable { case today, calendar, lists }

    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav
    @Environment(\.openWindow) private var openWindow

    @State private var tab: Tab = .today
    @State private var openListID: String?
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var folhas = Folhas()
    @Namespace private var trilho

    static let size = CGSize(width: 340, height: 540)

    var body: some View {
        VStack(spacing: 0) {
            if auth.isSignedIn {
                header
                UpdateBanner().padding(.horizontal, DS.e4).padding(.bottom, DS.e2)
                content
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                signedOut.frame(maxHeight: .infinity)
            }
            navegacao
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(DS.fundo)
        .clipShape(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
        .hospedaFolhas(folhas)
        .tint(DS.acento)
        .background(PopoverWindowConfigurator(
            appearance: store.prefs.appearance.resolved,
            cornerRadius: DS.raioCartao,
            onOpen: { Task { await store.sync() } }
        ))
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack(alignment: .center, spacing: DS.e2) {
            if tab == .lists, let id = openListID {
                BotaoIcone(simbolo: "chevron.left", rotulo: "Voltar às listas") {
                    withAnimation(DS.curva) { openListID = nil }
                }
                .padding(.leading, -6)
                ListIconView(listID: id, size: 26)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(store.color(forList: id), lineWidth: 1.5).padding(-3))
                    .padding(.horizontal, 3)
                Text(store.displayName(id)).display(.titulo).foregroundStyle(DS.texto).lineLimit(1)
            } else {
                Text(titulo).display(.titulo).foregroundStyle(DS.texto)
            }
            Spacer()
            BotaoIcone(simbolo: "arrow.up.left.and.arrow.down.right", rotulo: "Abrir em tela grande") {
                openApp(destination)
            }
            accountMenu
        }
        .padding(.horizontal, DS.e4)
        .padding(.top, DS.e4)
        .padding(.bottom, DS.e3)
    }

    private var titulo: String {
        switch tab {
        case .today: "Hoje"
        case .calendar: "Calendário"
        case .lists: "Listas"
        }
    }

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
            Button("Ajustes") { openApp(.settings) }
            Divider()
            Button("Encerrar o Tasker") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: Avatar.menuImage(auth.avatar, side: 28))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Conteúdo

    @ViewBuilder private var content: some View {
        ZStack(alignment: .top) {
            switch tab {
            case .today: todayTab.transition(.opacity)
            case .calendar: PopoverCalendarView(day: $day).transition(.opacity)
            case .lists:
                if let id = openListID {
                    listTab(id).transition(.asymmetric(insertion: .offset(x: 56).combined(with: .opacity), removal: .opacity))
                } else {
                    listsIndex.transition(.asymmetric(insertion: .offset(x: -14).combined(with: .opacity), removal: .opacity))
                }
            }
        }
        .animation(DS.curva, value: tab)
        .animation(DS.curva, value: openListID)
    }

    private var todayTab: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            QuickAddField(defaultDue: store.today).padding(.horizontal, DS.e4)
            scroll {
                EventsCard(events: store.events(on: store.today), compacto: true)
                CalendarIssueBanner()
                ErrorBanner()

                let overdue = store.overdueTasks
                if !overdue.isEmpty {
                    SecaoTarefas("Em atraso", contagem: overdue.count, tom: DS.perigoTexto,
                                 acao: ("Adiar p/ hoje", { store.postponeOverdue() })) {
                        ForEach(overdue) { TaskRow(task: $0, style: .compact) }
                    }
                }

                let today = store.todayTasks
                SecaoTarefas("Hoje", contagem: today.count) {
                    if today.isEmpty {
                        EstadoVazio(icone: "checkmark.circle", titulo: "Tudo feito por hoje")
                    } else {
                        ForEach(today) { TaskRow(task: $0, style: .compact) }
                    }
                }
            }
        }
    }

    private var listsIndex: some View {
        scroll {
            VStack(spacing: 0) {
                ForEach(store.lists) { list in
                    Button {
                        withAnimation(DS.curva) { openListID = list.id }
                    } label: {
                        HStack(spacing: DS.e3) {
                            ListIconView(listID: list.id, size: 26)
                            Text(store.displayName(list.id)).txt(.sm, .medium).foregroundStyle(DS.texto)
                            Spacer()
                            let count = store.tasks(inList: list.id).count
                            if count > 0 { Text("\(count)").txt(.xs, .medium).foregroundStyle(DS.texto3) }
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.texto3)
                        }
                        .padding(.horizontal, DS.e3)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(Pressionavel(raio: DS.raioM))
                }
            }
            .padding(DS.e1)
            .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
        }
    }

    private func listTab(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            QuickAddField(fixedListID: id).padding(.horizontal, DS.e4)
            scroll {
                let items = store.tasks(inList: id)
                SecaoTarefas("Tarefas", contagem: items.count, tom: store.color(forList: id)) {
                    if items.isEmpty {
                        EstadoVazio(icone: "checklist", titulo: "Lista vazia")
                    } else {
                        ForEach(items) { TaskRow(task: $0, style: .compact) }
                    }
                }
            }
        }
    }

    private func scroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.e4) { content() }
                .padding(.horizontal, DS.e4)
                .padding(.bottom, DS.e4)
        }
        .scrollIndicators(.never)
    }

    private var signedOut: some View {
        VStack(spacing: DS.e3) {
            Simbolo(tamanho: 44)
            Text("Conecte sua conta").display(.xl).foregroundStyle(DS.texto)
            Text("Para ver as tarefas e os eventos de hoje.").txt(.sm).foregroundStyle(DS.texto3)
            Button("Configurar") { openApp(.today) }.buttonStyle(Botao(variante: .primario, tamanho: .m))
        }
        .padding(DS.e8)
    }

    // MARK: Navegação (pílula, rótulo só no ativo)

    private var navegacao: some View {
        HStack(spacing: DS.e1) {
            aba(.today, "sun.max", "Hoje")
            aba(.calendar, "calendar", "Calendário")
            aba(.lists, "list.bullet", "Listas")
            Rectangle().fill(DS.borda).frame(width: 1, height: 22).padding(.horizontal, 2)
            BotaoIcone(simbolo: "gearshape", rotulo: "Abrir ajustes", tamanho: 40, tamanhoIcone: 15) {
                openApp(.settings)
            }
        }
        .padding(6)
        .background(Capsule().fill(DS.superficie))
        .overlay(Capsule().strokeBorder(DS.borda))
        .sombraAlta()
        .padding(.vertical, DS.e3)
        .frame(maxWidth: .infinity)
        .animation(DS.curva, value: tab)
    }

    private func aba(_ valor: Tab, _ simbolo: String, _ rotulo: String) -> some View {
        let ativa = tab == valor
        return Button {
            if valor == .lists && tab == .lists { openListID = nil }
            tab = valor
        } label: {
            HStack(spacing: DS.e2) {
                Image(systemName: simbolo)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ativa ? DS.acento : DS.texto3)
                if ativa {
                    Text(rotulo).txt(.sm, .semibold).foregroundStyle(DS.texto)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .padding(.horizontal, ativa ? DS.e4 : DS.e3)
            .frame(height: 40)
            .background {
                if ativa {
                    Capsule().fill(DS.superficie2).matchedGeometryEffect(id: "trilho", in: trilho)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(SoAfunda(escala: 0.94))
        .help(rotulo)
    }

    private func openApp(_ item: SidebarItem) {
        nav.selection = item
        // Muda a política antes de abrir para a janela já surgir ativa, sem atraso.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openWindow(id: WindowID.main)
    }
}

/// Aba de calendário do menu: faixa da semana + agenda do dia escolhido.
struct PopoverCalendarView: View {
    @Environment(TaskStore.self) private var store
    @Binding var day: Date
    private let cal = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            weekStrip.padding(.horizontal, DS.e4)
            QuickAddField(defaultDue: day).padding(.horizontal, DS.e4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.e4) {
                    let events = store.events(on: day)
                    let tasks = store.tasks(on: day)
                    EventsCard(events: events, compacto: true)
                    if tasks.isEmpty && events.isEmpty {
                        EstadoVazio(icone: "calendar", titulo: "Dia livre")
                    } else if !tasks.isEmpty {
                        SecaoTarefas(DayLabel.short(day, today: store.today), contagem: tasks.count) {
                            ForEach(tasks) { TaskRow(task: $0, style: .compact, showDate: false) }
                        }
                    }
                }
                .padding(.horizontal, DS.e4)
                .padding(.bottom, DS.e4)
            }
            .scrollIndicators(.never)
        }
    }

    private var weekStart: Date {
        cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    }

    private var weekStrip: some View {
        HStack(spacing: 2) {
            BotaoIcone(simbolo: "chevron.left", rotulo: "Voltar uma semana", tamanho: 26, tamanhoIcone: 11) {
                withAnimation(DS.curva) { day = cal.adding(days: -7, to: day) }
            }
            ForEach(0..<7, id: \.self) { offset in
                let date = cal.adding(days: offset, to: weekStart)
                let selected = date == day
                let isToday = date == store.today
                let busy = !store.tasks(on: date).isEmpty || !store.events(on: date).isEmpty
                Button { withAnimation(DS.curvaRapida) { day = date } } label: {
                    VStack(spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.narrow)).uppercased())
                            .txt(.xs, .medium)
                            .foregroundStyle(selected ? DS.acentoSolidoTexto.opacity(0.85) : DS.texto3)
                        Text("\(cal.component(.day, from: date))")
                            .txt(.md, selected || isToday ? .bold : .medium)
                            .foregroundStyle(selected ? DS.acentoSolidoTexto : (isToday ? DS.acentoTexto : DS.texto))
                        Circle()
                            .fill(selected ? DS.acentoSolidoTexto : DS.acentoTexto)
                            .frame(width: 4, height: 4)
                            .opacity(busy ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                        .fill(selected ? DS.acentoSolido : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(Pressionavel(raio: DS.raioM, escala: 0.94))
            }
            BotaoIcone(simbolo: "chevron.right", rotulo: "Avançar uma semana", tamanho: 26, tamanhoIcone: 11) {
                withAnimation(DS.curva) { day = cal.adding(days: 7, to: day) }
            }
        }
    }
}
