import SwiftUI

/// Menu da barra (base KiteTasks, com o design system): mesmo fundo do app, altura fixa
/// (abre sempre do mesmo tamanho), abas internas e botão para abrir em tela grande.
struct MenuBarPopover: View {
    enum Tab: Hashable { case today, calendar, despejo }

    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav
    @Environment(\.openWindow) private var openWindow

    @State private var tab: Tab = .today
    @State private var day = Calendar.current.adding(days: 1, to: Calendar.current.startOfDay(for: .now))

    private var amanha: Date { Calendar.current.adding(days: 1, to: store.today) }
    @State private var folhas = Folhas()
    @Namespace private var trilho
    /// Altura do conteúdo rolável (guardada para o menu já abrir no tamanho certo).
    @AppStorage("menu.alturaConteudo") private var alturaConteudo: Double = 220

    static let largura: CGFloat = 340
    static let altura: CGFloat = 460
    /// Altura máxima da área rolável (o menu inteiro fica em ~540 no máximo).
    private static let alturaMaxima: CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            if store.hasAccount {
                header
                UpdateBanner().padding(.horizontal, DS.e4).padding(.bottom, DS.e2)
                content.frame(maxHeight: .infinity, alignment: .top)
            } else {
                signedOut.frame(maxHeight: .infinity)
            }
            navegacao
        }
        // Tamanho fixo: o menu nunca muda de altura; o conteúdo rola.
        .frame(width: Self.largura, height: Self.altura)
        .background(DS.fundo)
        .overlay(alignment: .bottom) { ToastDesfazer().padding(.bottom, 70) }
        .environment(\.noMenuDaBarra, true)
        .hospedaFolhas(folhas)
        .tint(DS.acento)
        // Ao fechar uma folha, devolve o foco à janela do menu (o hover das linhas volta na hora).
        .onChange(of: folhas.atual == nil) { _, fechou in
            if fechou {
                // A janela do menu é a que tem este tamanho fixo.
                let janela = NSApp.windows.first {
                    $0.isVisible && abs($0.frame.width - Self.largura) < 2 && abs($0.frame.height - Self.altura) < 2
                }
                janela?.makeFirstResponder(nil)
                janela?.makeKey()
            }
        }
        .background(PopoverWindowConfigurator(
            tema: store.prefs.appearance,
            onOpen: {
                // O calendário do menu sempre abre no dia seguinte (com o "hoje" atualizado).
                store.refreshToday()
                day = amanha
                Task { await store.sync() }
            }
        ))
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack(alignment: .center, spacing: DS.e2) {
            Text(titulo).display(.titulo).foregroundStyle(DS.texto)
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
        case .despejo: "Despejo"
        }
    }

    private var destination: SidebarItem {
        switch tab {
        case .today: .today
        case .calendar: .calendar
        case .despejo: .despejo
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
        .animacaoDeClique(circulo: true)
    }

    // MARK: Conteúdo

    @ViewBuilder private var content: some View {
        ZStack(alignment: .top) {
            switch tab {
            case .today: todayTab.transition(.opacity)
            case .calendar: PopoverCalendarView(day: $day).transition(.opacity)
            case .despejo: DespejoDoMenu { openApp(.despejo) }.transition(.opacity)
            }
        }
        .animation(DS.curva, value: tab)
    }

    private var todayTab: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            QuickAddField(defaultDue: store.today).padding(.horizontal, DS.e4)
            scroll {
                if store.prefs.showEventsInMenu {
                    EventsCard(events: store.events(on: store.today), compacto: true)
                }
                CalendarIssueBanner()
                ErrorBanner()

                // Sem energia: sem a seção de atrasadas.
                let overdue = store.prefs.showOverdueInMenu && !store.prefs.energiaBaixa ? store.overdueTasks : []
                let today = store.todayTasks
                if !overdue.isEmpty {
                    SecaoTarefas("Em atraso", contagem: overdue.count, tom: DS.perigoTexto,
                                 acao: ("Adiar p/ hoje", { store.postponeOverdue() })) {
                        ForEach(overdue) { TaskRow(task: $0, style: .compact) }
                    }
                }
                let feitas = store.completedToday
                if today.isEmpty && overdue.isEmpty && !feitas.isEmpty {
                    SecaoTarefas("Concluídas", contagem: feitas.count, recolhida: true) {
                        ForEach(feitas) { TaskRow(task: $0, style: .compact) }
                    }
                }
                if today.isEmpty {
                    if overdue.isEmpty { EstadoVazio(icone: "checkmark.circle", titulo: "Tudo feito por hoje") }
                } else if overdue.isEmpty {
                    CartaoDeLinhas(recuoDoFio: 44) { ForEach(today) { TaskRow(task: $0, style: .compact) } }
                } else {
                    SecaoTarefas("Hoje", contagem: today.count) {
                        ForEach(today) { TaskRow(task: $0, style: .compact) }
                    }
                }

                if !(today.isEmpty && overdue.isEmpty) && !feitas.isEmpty {
                    SecaoTarefas("Concluídas", contagem: feitas.count, recolhida: true) {
                        ForEach(feitas) { TaskRow(task: $0, style: .compact) }
                    }
                }
            }
        }
    }

    /// Área rolável que cresce com o conteúdo, até a altura máxima.
    private func scroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.e4) { content() }
                .padding(.horizontal, DS.e4)
                .padding(.bottom, DS.e2)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: AlturaDoConteudo.self, value: geo.size.height)
                })
        }
        .scrollIndicators(.never)
        .indicadorDeRolagem()
        .frame(maxHeight: .infinity)
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
            aba(.despejo, "brain.head.profile", "Despejo")
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
            // Entrar no Calendário (vindo de outra aba ou de novo) volta para amanhã.
            if valor == .calendar { day = amanha }
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
        .buttonStyle(Pressionavel(raio: 999, escala: 0.94))
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
                VStack(alignment: .leading, spacing: DS.e4) {
                    let events = store.events(on: day)
                    let tasks = store.tasks(on: day)
                    EventsCard(events: events, compacto: true)
                    if tasks.isEmpty && events.isEmpty {
                        EstadoVazio(icone: "calendar", titulo: "Dia livre")
                    } else if !tasks.isEmpty {
                        CartaoDeLinhas(recuoDoFio: 44) {
                            ForEach(tasks) { TaskRow(task: $0, style: .compact, showDate: false) }
                        }
                    }
                }
                .padding(.horizontal, DS.e4)
                .padding(.bottom, DS.e4)
            }
            .scrollIndicators(.never)
            .indicadorDeRolagem()
            .frame(maxHeight: .infinity)
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
                            .foregroundStyle(selected ? DS.acentoSolidoTexto : (isToday ? DS.acento : DS.texto))
                        Circle()
                            .fill(selected ? DS.acentoSolidoTexto : DS.acento)
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

private struct AlturaDoConteudo: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Aba do despejo no menu: captura rápida e os itens; organizar é na janela (precisa de espaço).
struct DespejoDoMenu: View {
    @Environment(Caderno.self) private var caderno
    let organizarNaJanela: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            CampoDespejo(style: .compacto).padding(.horizontal, DS.e4)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.e3) {
                    if caderno.despejo.isEmpty {
                        EstadoVazio(icone: "brain.head.profile", titulo: "Cabeça leve",
                                    descricao: "Despeje aqui o que estiver ocupando espaço. Organize depois.")
                            .padding(.top, DS.e4)
                    } else {
                        HStack {
                            Text("\(caderno.despejo.count) para organizar").txt(.xs, .semibold).foregroundStyle(DS.texto3)
                            Spacer()
                            Button("Organizar na janela", action: organizarNaJanela).buttonStyle(Botao(variante: .fantasma))
                        }
                        CartaoDeLinhas(recuoDoFio: DS.e4) {
                            ForEach(caderno.despejo.reversed()) { item in
                                LinhaDespejo(item: item, compacta: true, organizar: organizarNaJanela)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.e4)
                .padding(.bottom, DS.e4)
                .animation(DS.curva, value: caderno.despejo.map(\.id))
            }
            .scrollIndicators(.never)
            .indicadorDeRolagem()
            .frame(maxHeight: .infinity)
        }
    }
}
