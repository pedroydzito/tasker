import AppKit
import SwiftUI

/// `Tasker --autoteste`: exercita o app de ponta a ponta (store + backend local + disco) numa pasta
/// isolada (`TASKER_HOME`) e sai com 0 se tudo passar. Roda no CI antes de cada release.
@MainActor
enum Autoteste {
    private static var falhas: [String] = []
    private static var passos = 0

    static func iniciar() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let ok = await rodar()
            print(ok ? "AUTOTESTE OK — \(passos) verificações" : "AUTOTESTE FALHOU — \(falhas.count) de \(passos)")
            for f in falhas { print("  ✗ \(f)") }
            exit(ok ? 0 : 1)
        }
        app.run()
    }

    private static func verificar(_ condicao: Bool, _ descricao: String, linha: Int = #line) {
        passos += 1
        if condicao {
            print("  ✓ \(descricao)")
        } else {
            falhas.append("\(descricao) (linha \(linha))")
            print("  ✗ \(descricao)")
        }
    }

    private static func secao(_ nome: String) { print("\n▸ \(nome)") }

    /// Monta um app "sem conta" vazio na pasta isolada.
    static func montar() async -> (TaskStore, Caderno) {
        let prefs = Preferences()
        prefs.localMode = true
        let auth = GoogleAuth()
        let store = TaskStore(auth: auth, api: GoogleAPI(auth: auth), prefs: prefs)
        await store.sync(force: true)
        return (store, Caderno(store: store, arquivo: Pastas.base.appendingPathComponent("caderno-teste-\(UUID().uuidString).json")))
    }

    static func rodar() async -> Bool {
        guard Pastas.isolado != nil else {
            print("Recusado: rode com TASKER_HOME apontando para uma pasta de teste (protege os dados reais).")
            return false
        }
        let (store, caderno) = await montar()

        secao("Base")
        verificar(store.hasAccount, "modo sem conta ativo")
        verificar(store.defaultList != nil, "lista padrão existe")
        guard let listaPadrao = store.defaultList?.id else { return false }

        // MARK: Despejo
        secao("Despejo")
        verificar(caderno.capturar("   \n  ") == 0, "texto vazio não entra")
        let n = caderno.capturar("- comprar pão\n• ligar pro dentista\n\n1. pagar boleto amanhã\n[ ] ler livro")
        verificar(n == 4, "texto colado vira um item por linha (\(n))")
        verificar(caderno.despejo.map(\.texto) == ["comprar pão", "ligar pro dentista", "pagar boleto amanhã", "ler livro"],
                  "marcadores de lista removidos e ordem mantida")

        let ler = caderno.despejo[3]
        caderno.editar(ler.id, texto: "  ler o livro do clube  ")
        verificar(caderno.despejo[3].texto == "ler o livro do clube", "editar apara espaços")
        caderno.editar(ler.id, texto: "   ")
        verificar(caderno.despejo.count == 3, "editar para vazio remove")

        let dentista = caderno.despejo[1]
        caderno.soltar(dentista.id)
        verificar(!caderno.despejo.contains { $0.id == dentista.id }, "soltar tira da caixa")
        verificar(store.aviso != nil, "soltar mostra Desfazer")
        store.desfazerAviso()
        verificar(caderno.despejo.firstIndex { $0.id == dentista.id } == 1, "Desfazer devolve na mesma posição")

        let amanha = Calendar.current.adding(days: 1, to: store.today)
        let boleto = caderno.despejo[2]
        caderno.virarTarefa(boleto.id, titulo: "pagar boleto", listID: listaPadrao, due: amanha, horario: "14:30")
        verificar(!caderno.despejo.contains { $0.id == boleto.id }, "virar tarefa tira do despejo")
        await store.aguardarOperacoes()
        let criada = store.tasks.values.first { $0.title == "pagar boleto" }
        verificar(criada != nil && criada?.isLocal == false, "tarefa criada no backend (id definitivo)")
        verificar(criada?.dueDay == amanha, "tarefa com a data escolhida")
        verificar(criada?.horario == "14:30", "horário guardado nas notas da tarefa")

        let pao = caderno.despejo[0]
        let notaID = caderno.virarNota(pao.id)
        verificar(notaID.flatMap { caderno.nota($0)?.titulo } == "comprar pão", "virar nota cria a nota com o texto")
        verificar(caderno.despejo.count == 1, "sobra 1 item no despejo")
        caderno.virarTarefa("nao-existe", listID: nil, due: nil, horario: nil)
        verificar(caderno.despejo.count == 1, "id inexistente não quebra nada")

        // MARK: Notas
        secao("Notas")
        let hoje = store.today
        caderno.escreverNoDia(hoje, texto: "   ")
        verificar(caderno.notaDoDia(hoje) == nil, "nota do dia não nasce vazia")
        caderno.escreverNoDia(hoje, texto: "Semana puxada.\n[ ] marcar médico\n- [ ] comprar presente\n☐ revisar TCC\n[x] já feito\n[ ]   ")
        let doDia = caderno.notaDoDia(hoje)
        verificar(doDia != nil, "nota do dia criada no primeiro texto")
        verificar(caderno.diasComNota.contains(hoje), "dia aparece como dia com nota")
        let pendentes = Caderno.pendentes(em: doDia?.texto ?? "")
        verificar(pendentes.map(\.titulo) == ["marcar médico", "comprar presente", "revisar TCC"],
                  "linhas [ ], - [ ] e ☐ viram pendentes; [x] e vazias não")

        if let doDia, let primeira = pendentes.first {
            caderno.criarTarefa(daLinha: primeira.linha, naNota: doDia.id, listID: nil, due: doDia.dia)
            await store.aguardarOperacoes()
            let linhas = caderno.notaDoDia(hoje)?.texto.components(separatedBy: "\n") ?? []
            verificar(linhas.indices.contains(1) && linhas[1] == "→ marcar médico", "linha marcada como enviada")
            let tarefa = store.tasks.values.first { $0.title == "marcar médico" }
            verificar(tarefa?.dueDay == hoje, "tarefa da nota do dia ganha a data do dia")
            verificar(Caderno.pendentes(em: caderno.notaDoDia(hoje)?.texto ?? "").count == 2, "sobram 2 pendentes")
            caderno.criarTarefa(daLinha: 0, naNota: doDia.id, listID: nil, due: nil)
            verificar(store.tasks.values.filter { $0.title == "Semana puxada." }.isEmpty, "linha sem [ ] não vira tarefa")
        }

        let solta = caderno.novaNota()
        caderno.descartarSeVazia(solta)
        verificar(caderno.nota(solta) == nil, "nota solta vazia é descartada ao sair")
        let ideia = caderno.novaNota(titulo: "Ideias", texto: "Reunião com Ana sobre o app")
        caderno.atualizar(ideia, titulo: "Ideias do app")
        verificar(caderno.nota(ideia)?.titulo == "Ideias do app", "atualizar título")
        verificar(caderno.notasOrdenadas.first?.id == ideia, "nota editada por último vem primeiro")
        caderno.excluirNota(ideia)
        verificar(caderno.nota(ideia) == nil, "excluir nota")
        store.desfazerAviso()
        verificar(caderno.nota(ideia) != nil, "Desfazer devolve a nota")
        caderno.escreverNoDia(hoje, texto: "")
        verificar(caderno.notaDoDia(hoje) == nil, "apagar o texto da nota do dia remove a nota")
        caderno.escreverNoDia(hoje, texto: "De volta")

        // MARK: Busca
        secao("Busca")
        verificar(caderno.buscar("   ").isEmpty, "consulta vazia não traz nada")
        let r1 = caderno.buscar("reuniao ANA")
        verificar(r1.first?.tipo == .nota && r1.first?.alvo == ideia, "sem acento e sem maiúscula, várias palavras (nota)")
        verificar(caderno.buscar("boleto").first?.tipo == .tarefa, "acha tarefa")
        verificar(caderno.buscar("dentista").first?.tipo == .despejo, "acha item do despejo")
        verificar(caderno.buscar("dentista boleto").isEmpty, "todas as palavras precisam aparecer")
        _ = caderno.novaNota(titulo: "Lista", texto: "pagar a escola")
        let ordem = caderno.buscar("pagar")
        verificar(ordem.first?.titulo == "pagar boleto", "título vale mais que o corpo")

        // MARK: Disco
        secao("Disco")
        let arquivo = Pastas.base.appendingPathComponent("caderno-persistencia.json")
        let cadernoDisco = Caderno(store: store, arquivo: arquivo)
        cadernoDisco.capturar("item persistido")
        let nd = cadernoDisco.novaNota(titulo: "Persistida", texto: "corpo")
        cadernoDisco.escreverNoDia(hoje, texto: "dia persistido")
        cadernoDisco.salvarAgora(sincrono: true)
        let relido = Caderno(store: store, arquivo: arquivo)
        verificar(relido.despejo.map(\.texto) == ["item persistido"], "despejo relido do disco")
        verificar(relido.nota(nd)?.texto == "corpo", "nota relida do disco")
        verificar(relido.notaDoDia(hoje)?.texto == "dia persistido", "nota do dia relida (mesmo dia)")
        let vazio = Pastas.base.appendingPathComponent("caderno-vazio.json")
        try? Data("{}".utf8).write(to: vazio)
        verificar(Caderno(store: store, arquivo: vazio).notas.isEmpty, "arquivo antigo/sem campos abre sem erro")
        try? Data("lixo".utf8).write(to: vazio)
        verificar(Caderno(store: store, arquivo: vazio).despejo.isEmpty, "arquivo corrompido não derruba o app")

        // MARK: Tarefas (regressões)
        secao("Tarefas")
        store.addTask(title: "recém-criada", listID: listaPadrao, due: hoje)
        if let temp = store.tasks.values.first(where: { $0.title == "recém-criada" }) {
            verificar(temp.isLocal, "tarefa nova aparece na hora (provisória)")
            store.setCompleted(temp, true)
        }
        await store.aguardarOperacoes()
        let remotas = (try? await store.backend.fetchTasks(listID: listaPadrao, updatedMin: nil)) ?? []
        verificar(remotas.first { $0.title == "recém-criada" }?.status == "completed",
                  "concluir antes de o backend responder não se perde")

        if let mae = store.tasks.values.first(where: { $0.title == "pagar boleto" }) {
            store.addSubtask(title: "separar comprovante", parent: mae)
            store.addSubtask(title: "  ", parent: mae)
            await store.aguardarOperacoes()
            let filhas = store.subtarefas(de: mae.id)
            verificar(filhas.map(\.title) == ["separar comprovante"], "subtarefa criada (vazia ignorada)")
            store.delete(mae)
            verificar(store.tasks[mae.id] == nil && store.subtarefas(de: mae.id).isEmpty, "excluir mãe some com as filhas")
            store.desfazerAviso()
            verificar(store.tasks[mae.id] != nil && store.subtarefas(de: mae.id).count == 1, "Desfazer devolve mãe e filhas")
        }

        secao("Criação rápida")
        let lido = QuickAddParser.parse("pagar conta amanhã #casa", lists: store.lists, today: hoje)
        verificar(lido.title == "pagar conta" && lido.due == Optional(Optional(amanha)) && lido.tagNames == ["casa"], "entende data e etiqueta")
        verificar(QuickAddParser.parse("festa 31/02", lists: store.lists, today: hoje).due == nil, "31/02 não vira outra data")

        return falhas.isEmpty
    }
}
