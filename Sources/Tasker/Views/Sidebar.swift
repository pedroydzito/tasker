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
    @State private var dropTarget: String?

    var body: some View {
        VStack(spacing: 0) {
            marca
                .padding(.horizontal, DS.e4)
                .padding(.top, 38) // botões da janela
                .padding(.bottom, DS.e6)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.e1) {
                    item(.today, "hoje", "sun.max", store.badgeCount)
                    item(.tomorrow, "amanhã", "sunrise", store.tasks(on: Calendar.current.adding(days: 1, to: store.today)).count)
                    item(.upcoming, "próximas", "calendar.day.timeline.left")
                    item(.calendar, "calendário", "calendar")
                    item(.all, "todas", "tray.full", store.activeCount)
                    item(.completed, "concluídas", "checkmark.circle")

                    cabecalhoSecao("listas", recolhida: $listsCollapsed)
                    if !listsCollapsed {
                        ForEach(store.lists) { list in linhaLista(list) }
                    }

                    cabecalhoSecao("etiquetas", recolhida: $tagsCollapsed) {
                        BotaoIcone(simbolo: "plus", rotulo: "Nova etiqueta", tamanho: 22, tamanhoIcone: 10) {
                            folhas.abrir("nova etiqueta") {
                                CriadorDeEtiqueta { tag in nav.selection = .tag(tag.id) }
                            }
                        }
                    }
                    if !tagsCollapsed {
                        ForEach(store.tags) { tag in
                            linha(selecionada: nav.selection == .tag(tag.id), tinta: nil,
                                  titulo: tag.name, contagem: store.tasks(withTag: tag.id).count) {
                                Image(systemName: "number")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(hex: tag.colorHex))
                            } acao: {
                                nav.selection = .tag(tag.id)
                            }
                            .contextMenu {
                                Button("Excluir etiqueta", role: .destructive) {
                                    if nav.selection == .tag(tag.id) { nav.selection = .today }
                                    store.deleteTag(tag)
                                }
                            }
                        }
                        if store.tags.isEmpty {
                            Text("digite #etiqueta ao criar uma tarefa")
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
            Simbolo(tamanho: 26)
            Text("tasker").display(.lg).foregroundStyle(DS.texto)
            Spacer()
            Menu {
                if let email = auth.profile?.email { Text(email) }
                Button("Ajustes") { nav.selection = .settings }
                Divider()
                Button("Sair da conta") {
                    auth.signOut()
                    store.reset()
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
            ListIconView(listID: list.id, size: 20)
        } acao: {
            nav.selection = .list(list.id)
        }
        .overlay(alignment: .top) {
            // Linha-guia de onde a lista vai cair ao soltar.
            Capsule().fill(DS.acento).frame(height: 2).padding(.horizontal, 6).offset(y: -2)
                .opacity(dropTarget == list.id ? 1 : 0)
        }
        .draggable(list.id) {
            HStack(spacing: DS.e2) {
                ListIconView(listID: list.id, size: 18)
                Text(store.displayName(list.id)).txt(.sm, .medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            withAnimation(DS.curva) { store.moveList(id, to: list.id) }
            return true
        } isTargeted: { targeted in
            if targeted { dropTarget = list.id } else if dropTarget == list.id { dropTarget = nil }
        }
        .contextMenu {
            Button("Personalizar ícone e cor…") {
                folhas.abrir("personalizar lista", largura: 440) { EditorDeLista(listID: list.id) }
            }
        }
    }

    /// Linha de navegação: trilho (fundo do ativo) desliza entre as linhas.
    /// Numa lista, o trilho fica na cor da lista.
    private func linha<Icone: View>(selecionada: Bool, tinta: Color?, titulo: String, contagem: Int?,
                                    @ViewBuilder icone: () -> Icone, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            HStack(spacing: DS.e3) {
                icone().frame(width: 20, height: 20)
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
        .buttonStyle(Pressionavel(raio: DS.raioM))
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
            .foregroundStyle(store.lastError == nil ? DS.texto3 : DS.acentoTexto)
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .buttonStyle(Pressionavel(raio: 999))
        .help(store.lastError ?? "Sincronizar agora")
    }

    private func texto(agora: Date) -> String {
        if store.isSyncing { return "sincronizando…" }
        if store.lastError != nil { return "erro ao sincronizar" }
        guard let last = store.lastSync else { return "sincronizar" }
        let s = Int(agora.timeIntervalSince(last))
        if s < 60 { return "sincronizado agora" }
        if s < 3600 { return "sincronizado há \(s / 60) min" }
        return "sincronizado há \(s / 3600) h"
    }
}
