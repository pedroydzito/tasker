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

        secao("Tempo")
        verificar(Duracao.ler("20") == 1200 && Duracao.ler("20m") == 1200, "\"20\" e \"20m\" = 20 minutos")
        verificar(Duracao.ler("1h20") == 4800 && Duracao.ler("1h 20m") == 4800, "\"1h20\" e \"1h 20m\"")
        verificar(Duracao.ler("1:20") == 4800 && Duracao.ler("1:20:30") == 4830, "\"1:20\" (h:min) e \"1:20:30\"")
        verificar(Duracao.ler("45s") == 45 && Duracao.ler("2h") == 7200, "segundos e horas")
        verificar(Duracao.ler("abc") == nil && Duracao.ler("") == nil && Duracao.ler("1x") == nil, "texto inválido é recusado")
        verificar(Duracao.relogio(65) == "01:05" && Duracao.relogio(3725) == "1:02:05", "formato de relógio")
        verificar(Duracao.curto(8100) == "2h 15m" && Duracao.curto(45) == "45s", "formato curto")
        let t0 = Date()
        store.addTask(title: "cronometrada", listID: listaPadrao, due: hoje)
        if let temp = store.tasks.values.first(where: { $0.title == "cronometrada" }) {
            store.alternarCronometro(temp.id, agora: t0)
            verificar(store.cronometroAtivo == temp.id, "play liga o cronômetro (mesmo antes de a tarefa existir no backend)")
            await store.aguardarOperacoes()
            let real = store.tasks.values.first { $0.title == "cronometrada" }
            verificar(real.map { store.cronometroAtivo == $0.id && !$0.isLocal } == true, "cronômetro segue a tarefa quando ganha o id definitivo")
            if let real {
                verificar(abs(store.tempo(de: real.id, agora: t0.addingTimeInterval(90)) - 90) < 0.5, "tempo corre enquanto roda")
                store.alternarCronometro(real.id, agora: t0.addingTimeInterval(90))
                verificar(store.cronometroAtivo == nil, "pausa")
                verificar(abs(store.tempo(de: real.id, agora: t0.addingTimeInterval(500)) - 90) < 0.5, "pausado não conta")
                store.alternarCronometro(real.id, agora: t0.addingTimeInterval(600))
                verificar(abs(store.tempo(de: real.id, agora: t0.addingTimeInterval(630)) - 120) < 0.5, "continuar soma ao total")
                if let outra = store.tasks.values.first(where: { $0.title == "pagar boleto" }) {
                    store.alternarCronometro(outra.id, agora: t0.addingTimeInterval(630))
                    verificar(store.cronometroAtivo == outra.id && abs(store.tempo(de: real.id) - 120) < 0.5,
                              "dar play em outra pausa a primeira")
                    store.setCompleted(outra, true)
                    verificar(store.cronometroAtivo == nil, "concluir pausa o cronômetro")
                }
                store.definirTempo(real.id, segundos: 1200)
                verificar(store.tempo(de: real.id) == 1200, "tempo digitado à mão substitui o total")
                verificar(TempoDB.load().total[real.id] == 1200, "tempo salvo em disco")
            }
        }

        secao("Agora · Depois · Não")
        let cad = Caderno(store: store, arquivo: Pastas.base.appendingPathComponent("caderno-adn.json"))
        cad.capturar("ligar pro banco\nideia de podcast\ncomprar tênis\nler sobre TOC")
        let ids = cad.despejo.map(\.id)
        verificar(ids.count == 4, "4 itens na caixa")
        cad.fazerAgora(ids[0])
        await store.aguardarOperacoes()
        let agora = store.tasks.values.first { $0.title == "ligar pro banco" }
        verificar(agora?.dueDay == hoje && !cad.despejo.contains { $0.id == ids[0] }, "Agora vira tarefa de hoje e sai da caixa")
        cad.mover(ids[1], para: .depois)
        verificar(cad.depois.map(\.id) == [ids[1]] && cad.despejo.count == 2, "Depois sai da caixa e vai para a pilha Depois")
        cad.mover(ids[2], para: .nao)
        verificar(cad.naoCarregar.map(\.id) == [ids[2]], "Não vai para a pilha Não (guardado, não apagado)")
        verificar(store.aviso != nil, "Não mostra Desfazer")
        store.desfazerAviso()
        verificar(cad.despejo.contains { $0.id == ids[2] } && cad.naoCarregar.isEmpty, "Desfazer devolve à caixa")
        cad.mover(ids[2], para: .nao)
        cad.mover(ids[1], para: .caixa)
        verificar(cad.despejo.contains { $0.id == ids[1] } && cad.depois.isEmpty, "trazer de volta de Depois")
        cad.mover(ids[3], para: .nao)
        cad.esvaziarNao()
        verificar(cad.naoCarregar.isEmpty && cad.item(ids[3]) == nil, "apagar tudo em Não")
        store.desfazerAviso()
        verificar(cad.naoCarregar.count == 2, "Desfazer devolve os apagados")
        verificar(caderno.buscar("tenis").isEmpty && cad.buscar("tenis").first?.tipo == .despejo, "busca acha itens de Não também")
        cad.salvarAgora(sincrono: true)
        let relidoADN = Caderno(store: store, arquivo: Pastas.base.appendingPathComponent("caderno-adn.json"))
        verificar(relidoADN.naoCarregar.count == 2 && relidoADN.despejo.count == 1, "pilhas relidas do disco")
        let antigo = Pastas.base.appendingPathComponent("caderno-antigo.json")
        try? Data(#"{"despejo":[{"id":"a","texto":"velho","criado":"2026-10-01T10:00:00Z"}],"notas":[]}"#.utf8).write(to: antigo)
        verificar(Caderno(store: store, arquivo: antigo).despejo.map(\.texto) == ["velho"], "item salvo antes das pilhas abre na caixa")

        secao("Foto no despejo")
        let png = Pastas.base.appendingPathComponent("teste.png")
        let img = NSImage(size: NSSize(width: 2400, height: 1200), flipped: false) { r in
            NSColor.systemTeal.setFill(); r.fill(); return true
        }
        if let tiff = img.tiffRepresentation, let dado = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? dado.write(to: png)
        }
        verificar(cad.capturar("print do horário", foto: png) == 1, "foto com o porquê vira 1 item")
        let comFoto = cad.despejo.first { $0.foto != nil }
        let arquivoFoto = comFoto.flatMap { $0.foto.map(Caderno.urlDaFoto) }
        verificar(arquivoFoto.map { FileManager.default.fileExists(atPath: $0.path) } == true, "foto copiada para a pasta do Tasker")
        if let arquivoFoto, let lida = NSImage(contentsOf: arquivoFoto) {
            verificar(max(lida.size.width, lida.size.height) <= 1600.5, "foto reduzida a no máximo 1600 px")
        }
        verificar(cad.capturar("", foto: Pastas.base.appendingPathComponent("nao-existe.png")) == 0, "arquivo que não é imagem é recusado")
        if let comFoto, let nota = cad.virarNota(comFoto.id) {
            verificar(cad.nota(nota)?.foto == comFoto.foto, "virar nota leva a foto junto")
        }
        cad.capturar("", foto: png)
        if let semTexto = cad.despejo.first(where: { $0.foto != nil }) {
            verificar(semTexto.textoExibido == "Foto sem descrição", "foto sem texto tem rótulo")
            cad.editar(semTexto.id, texto: "")
            verificar(cad.item(semTexto.id) != nil, "apagar o texto de uma foto não apaga a foto")
        }

        secao("Revisão da semana")
        let rev = cad.revisaoDaSemana()
        let textoRev = cad.nota(rev)?.texto ?? ""
        verificar(cad.nota(rev)?.titulo.hasPrefix("Semana de") == true, "nota da semana com título do período")
        verificar(textoRev.contains("Concluídas (") && textoRev.contains("Como foi a semana?")
                  && textoRev.contains("O que eu quero da próxima semana?"), "tem concluídas e as perguntas")
        verificar(textoRev.contains("✓ "), "lista o que foi concluído na semana")
        verificar(cad.revisaoDaSemana() == rev, "abrir de novo na mesma semana não duplica")

        secao("Lembrete e energia")
        let cal = Calendar.current
        let manha = cal.date(bySettingHour: 8, minute: 0, second: 0, of: hoje)!
        let noite = cal.date(bySettingHour: 22, minute: 0, second: 0, of: hoje)!
        verificar(LembreteDespejo.proximoDisparo(hora: 18, agora: manha) == cal.date(bySettingHour: 18, minute: 0, second: 0, of: hoje),
                  "lembrete ainda hoje se o horário não passou")
        verificar(LembreteDespejo.proximoDisparo(hora: 18, agora: noite)
                  == cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.adding(days: 1, to: hoje)),
                  "lembrete amanhã se o horário já passou")
        verificar(LembreteDespejo.texto(quantidade: 1).contains("1 coisa") && LembreteDespejo.texto(quantidade: 7).contains("só 3"),
                  "texto do lembrete gentil")
        store.prefs.energiaBaixa = true
        verificar(store.prefs.energiaBaixa, "modo sem energia liga")
        store.prefs.energiaBaixa = false

        secao("Criação rápida")
        let lido = QuickAddParser.parse("pagar conta amanhã #casa", lists: store.lists, today: hoje)
        verificar(lido.title == "pagar conta" && lido.due == Optional(Optional(amanha)) && lido.tagNames == ["casa"], "entende data e etiqueta")
        verificar(QuickAddParser.parse("festa 31/02", lists: store.lists, today: hoje).due == nil, "31/02 não vira outra data")
        let colada = QuickAddParser.linhas("- leite\n• pão amanhã\n\n3. ovos #mercado\n   ")
        verificar(colada == ["leite", "pão amanhã", "ovos #mercado"], "lista colada vira uma linha por tarefa")
        verificar(QuickAddParser.parse(colada[1], lists: store.lists, today: hoje).due == Optional(Optional(amanha)),
                  "data escrita numa linha vale para ela")
        verificar(QuickAddParser.linhas("uma tarefa só").count == 1, "texto de uma linha continua uma tarefa")

        return falhas.isEmpty
    }
}
