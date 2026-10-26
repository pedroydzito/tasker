import SwiftUI

struct MainWindow: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav
    @State private var folhas = Folhas()
    @AppStorage("larguraBarraLateral") private var larguraBarra: Double = 256
    @AppStorage("larguraDetalhes") private var larguraDetalhes: Double = 400
    @AppStorage("larguraBarraLateral") private var larguraBarra: Double = 256
    @AppStorage("larguraDetalhes") private var larguraDetalhes: Double = 400

    var body: some View {
        Group {
            if store.hasAccount {
                layout
            } else {
                OnboardingView()
            }
        }
        .background(DS.fundo)
        .ignoresSafeArea()
        .frame(minWidth: 900, minHeight: 580)
        .hospedaFolhas(folhas)
        .tint(DS.acento)
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
            Sidebar().frame(width: larguraBarra)
            Divisoria(largura: $larguraBarra, minimo: 210, maximo: 360, sentido: 1)

            ZStack(alignment: .bottom) {
                ZStack {
                    detail
                        .id(nav.selection)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
                }
                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18), value: nav.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                floatingBar
                ToastDesfazer().padding(.bottom, 84)
            }

            if let task = selectedTask {
                Divisoria(largura: $larguraDetalhes, minimo: 320, maximo: 600, sentido: -1)
                TaskInspector(task: task) { withAnimation(DS.curva) { nav.selectedTaskID = nil } }
                    .id(task.id)
                    .frame(width: larguraDetalhes)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(DS.curva, value: selectedTask?.id)
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

    /// Barra flutuante de nova tarefa: a ação principal é da tela (cria na lista/dia da tela atual).
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
                .padding(DS.e1)
                .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioG, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.raioG, style: .continuous).strokeBorder(DS.borda))
                .sombraAlta()
                .frame(maxWidth: 620)
                .padding(.horizontal, DS.e8)
                .padding(.bottom, DS.e5)
        }
    }
}

/// Divisória que redimensiona o painel vizinho arrastando (com limites).
/// `sentido` 1 = painel à esquerda, -1 = painel à direita.
struct Divisoria: View {
    @Binding var largura: Double
    let minimo: Double
    let maximo: Double
    let sentido: Double
    @State private var inicio: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || inicio != nil ? DS.acento.opacity(0.5) : DS.borda)
            .frame(width: hovering || inicio != nil ? 2 : 1)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { hovering = $0 }
                    .pointerStyle(.columnResize)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { g in
                            if inicio == nil { inicio = largura }
                            largura = min(maximo, max(minimo, (inicio ?? largura) + sentido * g.translation.width))
                        }
                        .onEnded { _ in inicio = nil })
            }
            .animation(DS.curvaRapida, value: hovering)
            .zIndex(2)
    }
}
