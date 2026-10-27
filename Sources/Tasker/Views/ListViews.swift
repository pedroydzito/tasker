import SwiftUI

/// Todas as tarefas abertas, por prazo ou por lista.
struct AllTasksView: View {
    @Environment(TaskStore.self) private var store
    @AppStorage("allGroupByList") private var groupByList = false

    var body: some View {
        PageScaffold(rotulo: taskCountText(store.activeCount), title: "Todas") {
            VStack(alignment: .leading, spacing: DS.e6) {
                Segmentado(selecao: $groupByList, opcoes: [(false, "Por data"), (true, "Por lista")])

                if groupByList {
                    ForEach(store.lists) { list in
                        let items = store.hierarchy(store.tasks(inList: list.id)).filter { $0.depth == 0 }
                        if !items.isEmpty {
                            SecaoTarefas(store.displayName(list.id), contagem: items.count, tom: store.color(forList: list.id)) {
                                ForEach(items) { TaskRow(task: $0.task, showList: false, depth: $0.depth) }
                            }
                        }
                    }
                } else {
                    grupo("Em atraso", store.overdueTasks, tom: DS.perigoTexto)
                    grupo("Hoje", store.todayTasks)
                    grupo("Em breve", store.laterTasks)
                    grupo("Sem data", store.undatedTasks)
                }
            }
        }
    }

    @ViewBuilder
    private func grupo(_ titulo: String, _ items: [TaskItem], tom: Color = DS.texto3) -> some View {
        if !items.isEmpty {
            SecaoTarefas(titulo, contagem: items.count, tom: tom) {
                ForEach(items) { TaskRow(task: $0) }
            }
        }
    }
}

/// Uma lista do Google Tasks. A foto ganha um anel na cor da lista, para identificar de relance.
struct ListDetailView: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    let listID: String

    var body: some View {
        let items = store.hierarchy(store.tasks(inList: listID)).filter { $0.depth == 0 }
        let done = store.completedTasks(inList: listID)
        let cor = store.color(forList: listID)
        PageScaffold(rotulo: taskCountText(items.count), title: store.displayName(listID)) {
            Button {
                folhas.abrir("Personalizar lista", largura: 440) { EditorDeLista(listID: listID) }
            } label: {
                ListIconComAnel(listID: listID, size: 52, espessura: 2.5)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(cor))
                            .overlay(Circle().strokeBorder(DS.fundo, lineWidth: 2))
                            .offset(x: 4, y: 4)
                    }
            }
            .buttonStyle(SoAfunda(escala: 0.94))
            .help("Personalizar ícone e cor")
        } content: {
            VStack(alignment: .leading, spacing: DS.e6) {
                SecaoTarefas("Tarefas", contagem: items.count, tom: cor) {
                    if items.isEmpty {
                        EstadoVazio(icone: "checklist", titulo: "Lista vazia", descricao: "Use a barra abaixo para criar a primeira tarefa.")
                    } else {
                        ForEach(items) { TaskRow(task: $0.task, showList: false, depth: $0.depth) }
                    }
                }
                if !done.isEmpty {
                    SecaoTarefas("Concluídas", contagem: done.count, recolhida: true) {
                        ForEach(done.prefix(30)) { TaskRow(task: $0, showList: false) }
                    }
                }
            }
        }
    }
}

/// Tarefas com uma etiqueta local.
struct TagDetailView: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    let tagID: String

    var body: some View {
        if let tag = store.tag(tagID) {
            let items = store.tasks(withTag: tagID)
            PageScaffold(rotulo: "Etiqueta · só no Tasker", title: "#\(tag.name)") {
                VStack(alignment: .leading, spacing: DS.e6) {
                    HStack {
                        Button {
                            folhas.abrir("Editar etiqueta", largura: 380) { EditorDeEtiqueta(tag: tag) }
                        } label: { Label("Editar etiqueta", systemImage: "pencil") }
                        .buttonStyle(.superficie)
                        Spacer()
                    }
                    SecaoTarefas("Tarefas", contagem: items.count) {
                        if items.isEmpty {
                            EstadoVazio(icone: "number", titulo: "Nenhuma tarefa aqui",
                                        descricao: "Clique com o botão direito numa tarefa → Etiquetas.")
                        } else {
                            ForEach(items) { TaskRow(task: $0) }
                        }
                    }
                }
            }
        } else {
            EstadoVazio(icone: "number", titulo: "Etiqueta não encontrada")
        }
    }
}

/// Histórico de concluídas, agrupado por dia, carregando aos poucos.
struct CompletedView: View {
    @Environment(TaskStore.self) private var store
    @State private var limit = 40

    var body: some View {
        let items = Array(store.completedTasks.prefix(limit))
        let groups = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.completedDate ?? .distantPast) }
        PageScaffold(rotulo: "\(store.completedTasks.count) tarefas até aqui", title: "Concluídas") {
            VStack(alignment: .leading, spacing: DS.e6) {
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    SecaoTarefas(day == .distantPast ? "Sem data" : DayLabel.short(day, today: store.today),
                                 contagem: groups[day]?.count ?? 0) {
                        ForEach(groups[day] ?? []) { TaskRow(task: $0, showDate: false) }
                    }
                }
                if store.completedTasks.count > limit {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(DS.e3)
                        .onAppear { limit += 40 }
                }
            }
        }
    }
}

/// Folha "Editar etiqueta": nome e cor — só salva ao clicar em "Salvar".
struct EditorDeEtiqueta: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    @Environment(Navigation.self) private var nav
    let tag: Tag
    @State private var nome = ""
    @State private var cor = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e4) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nome").rotulo()
                TextField("Nome", text: $nome).campo()
            }
            VStack(alignment: .leading, spacing: DS.e2) {
                Text("Cor").rotulo()
                AmostrasDeCor(selecao: $cor)
            }
            RodapeFolha {
                Button("Excluir etiqueta") {
                    let alvo = tag
                    folhas.confirmar("Excluir etiqueta", mensagem: "A etiqueta “\(alvo.name)” sai de todas as tarefas.") {
                        if nav.selection == .tag(alvo.id) { nav.selection = .today }
                        store.deleteTag(alvo)
                    }
                }
                .buttonStyle(Botao(variante: .fantasma))
                Spacer()
                Button("Cancelar") { folhas.fechar() }.buttonStyle(.superficie)
                Button("Salvar") {
                    var novo = tag
                    novo.name = nome.trimmingCharacters(in: .whitespaces).isEmpty ? tag.name : nome
                    novo.colorHex = cor
                    store.updateTag(novo)
                    withAnimation(DS.curvaSaida) { folhas.fechar() }
                }
                .buttonStyle(.primario)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            nome = tag.name
            cor = tag.colorHex
        }
    }
}
