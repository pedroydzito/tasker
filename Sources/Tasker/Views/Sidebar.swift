import SwiftUI

/// Coluna de navegação (design system §9.5): mesmo fundo do app, marca + pessoa no topo,
/// trilho que desliza sob o item ativo, seções recolhíveis e listas reordenáveis.
struct Sidebar: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Navigation.self) private var nav
    @Environment(Folhas.self) private var folhas

    @AppStorage("sidebar.listsCollapsed") private var listsCollapsed = false
    @AppStorage("sidebar.tagsCollapsed") private var tagsCollapsed = false
    @Namespace private var trilho
    @State private var alvoDeTarefa: String?

    var body: some View {
        VStack(spacing: 0) {
            marca
                .padding(.horizontal, DS.e3)
                .padding(.top, 40) // botões da janela
                .padding(.bottom, DS.e5)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.e1) {
                    item(.today, "Hoje", "sun.max", store.badgeCount)
                    item(.tomorrow, "Amanhã", "sunrise", store.tasks(on: Calendar.current.adding(days: 1, to: store.today)).count)
                    item(.upcoming, "Próximas", "calendar.day.timeline.left")
                    item(.calendar, "Calendário", "calendar")
                    item(.all, "Todas", "tray.full", store.activeCount)
                    item(.completed, "Concluídas", "checkmark.circle")

                    cabecalhoSecao("Listas", recolhida: $listsCollapsed) {
                        BotaoIcone(simbolo: "plus", rotulo: "Nova lista", tamanho: 22, tamanhoIcone: 10) {
                            folhas.abrir("Nova lista", largura: 420) { NovaLista() }
                        }
                    }
                    if !listsCollapsed {
                        // "Minhas tarefas" fica fixa no topo; as outras se reordenam arrastando.
                        let fixa = store.pinnedListID.flatMap { store.list($0) }
                        if let fixa { linhaLista(fixa).frame(height: 36) }
                        ListaReordenavel(ids: store.lists.map(\.id).filter { $0 != fixa?.id },
                                         mover: { id, alvo in store.moveList(id, toIndex: alvo + (fixa == nil ? 0 : 1)) }) { id in
                            if let list = store.list(id) { linhaLista(list) }
                        }
                    }

                    cabecalhoSecao("Etiquetas", recolhida: $tagsCollapsed) {
                        BotaoIcone(simbolo: "plus", rotulo: "Nova etiqueta", tamanho: 22, tamanhoIcone: 10) {
                            folhas.abrir("Nova etiqueta") {
                                CriadorDeEtiqueta { tag in nav.selection = .tag(tag.id) }
                            }
                        }
                    }
                    if !tagsCollapsed {
                        ListaReordenavel(ids: store.tags.map(\.id), mover: { id, alvo in store.moveTag(id, toIndex: alvo) }) { id in
                            if let tag = store.tag(id) {
                            linha(selecionada: nav.selection == .tag(tag.id), tinta: nil,
                                  titulo: tag.name, contagem: store.tasks(withTag: tag.id).count) {
                                Image(systemName: "number")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(hex: tag.colorHex))
                            } acao: {
                                nav.selection = .tag(tag.id)
                            }
                            .contextMenu {
                                Button("Excluir etiqueta…", role: .destructive) {
                                    folhas.confirmar("Excluir etiqueta",
                                                     mensagem: "A etiqueta “\(tag.name)” sai de todas as tarefas.") {
                                        if nav.selection == .tag(tag.id) { nav.selection = .today }
                                        store.deleteTag(tag)
                                    }
                                }
                            }
                            }
                        }
                        if store.tags.isEmpty {
                            Text("Digite #etiqueta ao criar uma tarefa")
                                .txt(.xs)
                                .foregroundStyle(DS.texto3)
                                .padding(.horizontal, 10)
                        }
                    }
                }
                .padding(.horizontal, DS.e3)
                .padding(.bottom, DS.e4)
                .animation(DS.curva, value: nav.selection)
            }
            .scrollIndicators(.never)

            rodape
        }
        .background(DS.fundo)
    }

    // MARK: Marca + pessoa

    private var marca: some View {
        HStack(spacing: 10) {
            Simbolo(tamanho: 24)
            Text("Tasker").display(.lg).foregroundStyle(DS.texto)
            Spacer()
            Menu {
                if store.prefs.localMode {
                    Text("Usando só neste Mac")
                    Button("Conectar Google…") { nav.selection = .settings }
                } else if let email = auth.profile?.email {
                    Text(email)
                }
                Button("Ajustes") { nav.selection = .settings }
                if !store.prefs.localMode {
                    Divider()
                    Button("Sair da conta") {
                        auth.signOut()
                        store.reset()
                    }
                }
            } label: {
                Image(nsImage: Avatar.menuImage(auth.avatar, side: 26))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(auth.profile?.name ?? "Conta")
        }
        .padding(.horizontal, 10)
    }

    // MARK: Itens

    private func item(_ destino: SidebarItem, _ titulo: String, _ simbolo: String, _ contagem: Int? = nil) -> some View {
        let ativo = nav.selection == destino
        return linha(selecionada: ativo, tinta: nil, titulo: titulo, contagem: contagem) {
            Image(systemName: simbolo)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ativo ? DS.acento : DS.texto2)
        } acao: {
            nav.selection = destino
        }
    }

    private func linhaLista(_ list: TaskList) -> some View {
        let ativa = nav.selection == .list(list.id)
        return linha(selecionada: ativa, tinta: store.color(forList: list.id), titulo: store.displayName(list.id),
                     contagem: store.tasks(inList: list.id).count) {
            ListIconView(listID: list.id, size: 22)
        } acao: {
            nav.selection = .list(list.id)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                .strokeBorder(store.color(forList: list.id), lineWidth: 2)
                .opacity(alvoDeTarefa == list.id ? 1 : 0)
        }
        .dropDestination(for: String.self) { itens, _ in
            guard let item = itens.first, item.hasPrefix("tarefa:") else { return false }
            let taskID = String(item.dropFirst("tarefa:".count))
            guard let task = store.tasks[taskID] else { return false }
            withAnimation(DS.curva) { store.moveTask(task, toList: list.id) }
            return true
        } isTargeted: { dentro in
            withAnimation(DS.curvaRapida) {
                if dentro { alvoDeTarefa = list.id } else if alvoDeTarefa == list.id { alvoDeTarefa = nil }
            }
        }
        .contextMenu {
            Button("Personalizar ícone e cor…") {
                folhas.abrir("Personalizar lista", largura: 440) { EditorDeLista(listID: list.id) }
            }
        }
    }

    /// Linha de navegação: trilho (fundo do ativo) desliza entre as linhas.
    /// Numa lista, o trilho fica na cor da lista.
    private func linha<Icone: View>(selecionada: Bool, tinta: Color?, titulo: String, contagem: Int?,
                                    @ViewBuilder icone: () -> Icone, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: DS.e3) {
                icone().frame(width: 24, height: 22)
                Text(titulo)
                    .txt(.sm, selecionada ? .semibold : .medium)
                    .foregroundStyle(selecionada ? DS.texto : DS.texto2)
                    .lineLimit(1)
                Spacer(minLength: DS.e1)
                if let contagem, contagem > 0 {
                    Text("\(contagem)").txt(.xs, .medium).monospacedDigit().foregroundStyle(DS.texto3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if selecionada {
                    RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                        .fill(tinta.map { $0.opacity(0.16) } ?? DS.superficie2)
                        .matchedGeometryEffect(id: "trilho", in: trilho)
                }
            }
            .contentShape(Rectangle())
        }
        // Sem encolher no clique: a linha também é a alça de arrastar.
        .buttonStyle(Pressionavel(raio: DS.raioM, escala: 1))
    }

    private func cabecalhoSecao(_ titulo: String, recolhida: Binding<Bool>) -> some View {
        cabecalhoSecao(titulo, recolhida: recolhida) { EmptyView() }
    }

    private func cabecalhoSecao<Acao: View>(_ titulo: String, recolhida: Binding<Bool>,
                                           @ViewBuilder acao: () -> Acao) -> some View {
        HStack(spacing: DS.e1) {
            Button {
                withAnimation(DS.curva) { recolhida.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(titulo).rotulo()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(DS.texto3)
                        .rotationEffect(.degrees(recolhida.wrappedValue ? -90 : 0))
                }
                .padding(.vertical, DS.e1)
                .contentShape(Rectangle())
            }
            .buttonStyle(SoAfunda())
            Spacer()
            acao()
        }
        .padding(.leading, 10)
        .padding(.trailing, DS.e1)
        .padding(.top, DS.e5)
        .padding(.bottom, DS.e1)
    }

    // MARK: Rodapé

    private var rodape: some View {
        HStack(spacing: DS.e1) {
            SyncStatusButton()
            Spacer()
            BotaoIcone(simbolo: "gearshape", rotulo: "Ajustes", ativo: nav.selection == .settings) {
                nav.selection = .settings
            }
        }
        .padding(.horizontal, DS.e3)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(DS.borda).frame(height: 1) }
    }
}

/// Símbolo da marca: quadrado de acento (28% de raio) com o check.
struct Simbolo: View {
    var tamanho: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: tamanho * 0.28, style: .continuous)
            .fill(DS.acentoSolido)
            .frame(width: tamanho, height: tamanho)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: tamanho * 0.5, weight: .heavy))
                    .foregroundStyle(DS.acentoSolidoTexto)
            )
    }
}

/// "sincronizado há 2 min" — clique para sincronizar agora.
struct SyncStatusButton: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        Button {
            Task { await store.sync(force: true) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(store.isSyncing ? 360 : 0))
                    .animation(store.isSyncing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: store.isSyncing)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(texto(agora: context.date)).lineLimit(1)
                }
            }
            .txt(.xs, .medium)
            .foregroundStyle(store.lastError == nil ? DS.texto3 : DS.perigoTexto)
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .buttonStyle(Pressionavel(raio: 999))
        .help(store.lastError ?? "Sincronizar agora")
    }

    private func texto(agora: Date) -> String {
        if store.isSyncing { return "Sincronizando…" }
        if store.lastError != nil { return "Erro ao sincronizar" }
        guard let last = store.lastSync else { return "Sincronizar" }
        let s = Int(agora.timeIntervalSince(last))
        if s < 60 { return "Sincronizado agora" }
        if s < 3600 { return "Sincronizado há \(s / 60) min" }
        return "Sincronizado há \(s / 3600) h"
    }
}

/// Pilha de linhas que se reordena segurando e arrastando para cima ou para baixo.
/// O item segue o mouse 1:1; os outros abrem espaço; ao soltar, a nova ordem é salva.
struct ListaReordenavel<Row: View>: View {
    let ids: [String]
    let mover: (String, Int) -> Void
    @ViewBuilder let linha: (String) -> Row

    /// Altura de uma linha (36) + espaço entre linhas (4).
    var passo: CGFloat = 40

    @State private var arrastando: String?
    @State private var dy: CGFloat = 0

    private var origem: Int? { arrastando.flatMap { ids.firstIndex(of: $0) } }

    private var destino: Int? {
        guard let origem else { return nil }
        return max(0, min(ids.count - 1, origem + Int((dy / passo).rounded())))
    }

    var body: some View {
        VStack(spacing: DS.e1) {
            ForEach(Array(ids.enumerated()), id: \.element) { indice, id in
                let ativo = arrastando == id
                linha(id)
                    .frame(height: 36)
                    .background {
                        if ativo {
                            RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                                .fill(DS.superficie)
                                .overlay(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).strokeBorder(DS.borda))
                                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        }
                    }
                    .offset(y: deslocamento(indice, id))
                    .zIndex(ativo ? 1 : 0)
                    .animation(ativo ? nil : DS.curva, value: destino)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 6, coordinateSpace: .global)
                            .onChanged { g in
                                if arrastando == nil { arrastando = id }
                                if arrastando == id { dy = g.translation.height }
                            }
                            .onEnded { _ in soltar() }
                    )
            }
        }
    }

    private func deslocamento(_ indice: Int, _ id: String) -> CGFloat {
        guard let origem, let destino else { return 0 }
        if id == arrastando { return dy }
        if origem < destino, indice > origem, indice <= destino { return -passo }
        if origem > destino, indice >= destino, indice < origem { return passo }
        return 0
    }

    private func soltar() {
        guard let id = arrastando else { return }
        let alvo = destino
        // Sem animação: o item já está visualmente no lugar novo.
        var transacao = Transaction()
        transacao.disablesAnimations = true
        withTransaction(transacao) {
            if let alvo { mover(id, alvo) }
            arrastando = nil
            dy = 0
        }
    }
}
