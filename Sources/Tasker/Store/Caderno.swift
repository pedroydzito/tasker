import AppKit
import Observation

/// Algo despejado da cabeça: só texto (e uma foto, se quiser), sem data, lista ou etiqueta.
/// É organizado depois: Agora (vira tarefa), Depois (guardado, fora da vista) ou Não (decidi não carregar).
struct ItemDespejo: Identifiable, Codable, Hashable {
    enum Estado: String, Codable { case caixa, depois, nao }

    let id: String
    var texto: String
    let criado: Date
    var estado: Estado = .caixa
    /// Quando foi para Depois / Não (para ordenar essas pilhas).
    var movido: Date?
    /// Nome do arquivo da foto em `Pastas/DespejoFotos`.
    var foto: String?

    init(id: String, texto: String, criado: Date, foto: String? = nil) {
        self.id = id
        self.texto = texto
        self.criado = criado
        self.foto = foto
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        texto = try c.decode(String.self, forKey: .texto)
        criado = try c.decode(Date.self, forKey: .criado)
        estado = try c.decodeIfPresent(Estado.self, forKey: .estado) ?? .caixa
        movido = try c.decodeIfPresent(Date.self, forKey: .movido)
        foto = try c.decodeIfPresent(String.self, forKey: .foto)
    }

    /// Texto para mostrar (uma foto sem descrição ainda tem um rótulo).
    var textoExibido: String { texto.isEmpty ? "Foto sem descrição" : texto }
}

/// Nota livre ou nota do dia (diário de planejamento). Fica só no Tasker.
struct Anotacao: Identifiable, Codable, Hashable {
    let id: String
    var titulo: String
    var texto: String
    /// Preenchido na nota do dia (início do dia); nil numa nota solta.
    var dia: Date?
    let criada: Date
    var editada: Date
    /// Foto trazida do despejo (arquivo em `Pastas/DespejoFotos`).
    var foto: String?

    /// Título para listas e busca: o escrito, senão a primeira linha, senão "Sem título".
    var tituloExibido: String {
        let t = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if let dia { return DayLabel.long(dia).primeiraMaiuscula }
        let primeira = texto.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return primeira.isEmpty ? "Sem título" : primeira
    }
}

/// Resultado da busca (⌘K): tarefas, notas, despejo e eventos.
struct ResultadoBusca: Identifiable, Hashable {
    enum Tipo: String { case tarefa, nota, despejo, evento }
    let tipo: Tipo
    let alvo: String
    let titulo: String
    let trecho: String?
    let data: Date?
    let concluida: Bool
    let pontos: Int
    var id: String { "\(tipo.rawValue):\(alvo)" }
}

/// Despejo e notas: guardados num arquivo do Tasker (o Google Tasks não tem onde guardar isso).
@MainActor @Observable
final class Caderno {
    /// Tudo o que foi despejado (caixa, depois e não), em ordem de chegada.
    private(set) var itens: [ItemDespejo] = []
    /// Caixa de entrada: o que ainda não foi organizado. O mais antigo primeiro.
    var despejo: [ItemDespejo] { itens.filter { $0.estado == .caixa } }
    /// Importante, mas não agora. O mais recente primeiro.
    var depois: [ItemDespejo] { itens.filter { $0.estado == .depois }.sorted { ($0.movido ?? $0.criado) > ($1.movido ?? $1.criado) } }
    /// O que foi decidido não carregar (guardado, dá para trazer de volta).
    var naoCarregar: [ItemDespejo] { itens.filter { $0.estado == .nao }.sorted { ($0.movido ?? $0.criado) > ($1.movido ?? $1.criado) } }
    private(set) var notas: [Anotacao] = []

    @ObservationIgnored let store: TaskStore
    @ObservationIgnored private let arquivo: URL
    @ObservationIgnored private var gravacao: DispatchWorkItem?

    private struct Arquivo: Codable {
        var despejo: [ItemDespejo] = []
        var notas: [Anotacao] = []

        init(despejo: [ItemDespejo], notas: [Anotacao]) {
            self.despejo = despejo
            self.notas = notas
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            despejo = try c.decodeIfPresent([ItemDespejo].self, forKey: .despejo) ?? []
            notas = try c.decodeIfPresent([Anotacao].self, forKey: .notas) ?? []
        }
    }

    init(store: TaskStore, arquivo: URL = Pastas.base.appendingPathComponent("caderno.json")) {
        self.store = store
        self.arquivo = arquivo
        if let data = try? Data(contentsOf: arquivo), let lido = try? Self.decoder.decode(Arquivo.self, from: data) {
            itens = lido.despejo
            notas = lido.notas
        }
    }

    // MARK: Despejo

    /// Joga na caixa. Um texto com várias linhas (colado de outro lugar) vira um item por linha,
    /// sem os marcadores de lista ("- ", "• ", "1. ", "[ ]"). Com foto, é um item só (o texto é o porquê).
    @discardableResult
    func capturar(_ texto: String, foto: URL? = nil) -> Int {
        let agora = Date()
        if let foto {
            guard let nome = Self.guardarFoto(foto) else { return 0 }
            let porque = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            itens.append(ItemDespejo(id: UUID().uuidString, texto: porque, criado: agora, foto: nome))
            salvar()
            store.avisarSucesso("Foto guardada no despejo", icone: "photo")
            return 1
        }
        let linhas = texto.split(whereSeparator: \.isNewline)
            .map { Self.semMarcador(String($0)) }
            .filter { !$0.isEmpty }
        guard !linhas.isEmpty else { return 0 }
        for (i, linha) in linhas.enumerated() {
            // Milissegundos de diferença mantêm a ordem colada mesmo ordenando por data.
            itens.append(ItemDespejo(id: UUID().uuidString, texto: linha, criado: agora.addingTimeInterval(Double(i) / 1000)))
        }
        salvar()
        store.avisarSucesso(linhas.count == 1 ? "Guardado no despejo" : "\(linhas.count) itens no despejo",
                            plural: "itens no despejo", icone: "brain.head.profile")
        return linhas.count
    }

    func item(_ id: String) -> ItemDespejo? { itens.first { $0.id == id } }

    func editar(_ id: String, texto: String) {
        guard let i = itens.firstIndex(where: { $0.id == id }) else { return }
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpo.isEmpty && itens[i].foto == nil {
            itens.remove(at: i)
        } else {
            itens[i].texto = limpo
        }
        salvar()
    }

    /// Agora: vira tarefa para hoje, na lista padrão, num clique.
    func fazerAgora(_ id: String) {
        guard let item = item(id) else { return }
        virarTarefa(id, titulo: item.textoExibido, listID: nil, due: store.today, horario: nil)
    }

    /// Depois / Não / de volta à caixa. Sai da caixa com "Desfazer".
    func mover(_ id: String, para estado: ItemDespejo.Estado) {
        guard let i = itens.firstIndex(where: { $0.id == id }), itens[i].estado != estado else { return }
        let anterior = itens[i].estado
        itens[i].estado = estado
        itens[i].movido = .now
        salvar()
        switch estado {
        case .depois:
            store.mostrarAviso("Guardado para depois") { [weak self] in self?.voltar(id, para: anterior) } confirmar: {}
        case .nao:
            store.mostrarAviso("Você decidiu não carregar isso") { [weak self] in self?.voltar(id, para: anterior) } confirmar: {}
        case .caixa:
            store.avisarSucesso("De volta à caixa de entrada", icone: "tray.and.arrow.up")
        }
    }

    private func voltar(_ id: String, para estado: ItemDespejo.Estado) {
        guard let i = itens.firstIndex(where: { $0.id == id }) else { return }
        itens[i].estado = estado
        salvar()
    }

    /// Apaga de vez (com "Desfazer"). A foto só é apagada se não for desfeito.
    func soltar(_ id: String) {
        guard let i = itens.firstIndex(where: { $0.id == id }) else { return }
        let item = itens.remove(at: i)
        salvar()
        store.mostrarAviso("Item apagado") { [weak self] in
            self?.devolver(item, em: i)
        } confirmar: {
            if let foto = item.foto { try? FileManager.default.removeItem(at: Self.urlDaFoto(foto)) }
        }
    }

    /// Esvazia a pilha "Não carregar" (com "Desfazer").
    func esvaziarNao() {
        let removidos = itens.enumerated().filter { $0.element.estado == .nao }
        guard !removidos.isEmpty else { return }
        itens.removeAll { $0.estado == .nao }
        salvar()
        store.mostrarAviso("\(removidos.count) \(removidos.count == 1 ? "item apagado" : "itens apagados")") { [weak self] in
            guard let self else { return }
            for (i, item) in removidos where !self.itens.contains(where: { $0.id == item.id }) {
                self.itens.insert(item, at: min(i, self.itens.count))
            }
            self.salvar()
        } confirmar: {
            for (_, item) in removidos { if let foto = item.foto { try? FileManager.default.removeItem(at: Self.urlDaFoto(foto)) } }
        }
    }

    /// Vira tarefa (na lista e data escolhidas).
    func virarTarefa(_ id: String, titulo: String? = nil, listID: String?, due: Date?, horario: String?, tagIDs: [String] = []) {
        guard let i = itens.firstIndex(where: { $0.id == id }) else { return }
        let nome = (titulo ?? itens[i].texto).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty else { return }
        // A foto não vai para o Google Tasks: fica numa nota com o mesmo nome, para não se perder.
        if let foto = itens[i].foto {
            let n = novaNota(titulo: nome, texto: "Foto guardada junto da tarefa “\(nome)”.", avisar: false)
            if let j = notas.firstIndex(where: { $0.id == n }) { notas[j].foto = foto }
        }
        store.addTask(title: nome, listID: listID, due: due, tagIDs: tagIDs, horario: due == nil ? nil : horario)
        itens.remove(at: i)
        salvar()
    }

    /// Vira nota solta (o texto do item é o título; a foto vai junto). Devolve o id da nota.
    @discardableResult
    func virarNota(_ id: String) -> String? {
        guard let i = itens.firstIndex(where: { $0.id == id }) else { return nil }
        let item = itens.remove(at: i)
        let nota = novaNota(titulo: item.texto.isEmpty ? "Foto" : item.texto)
        if let foto = item.foto, let j = notas.firstIndex(where: { $0.id == nota }) { notas[j].foto = foto }
        salvar()
        return nota
    }

    private func devolver(_ item: ItemDespejo, em indice: Int) {
        guard !itens.contains(where: { $0.id == item.id }) else { return }
        itens.insert(item, at: min(indice, itens.count))
        salvar()
    }

    // MARK: Fotos

    static func urlDaFoto(_ nome: String) -> URL { Pastas.pasta("DespejoFotos").appendingPathComponent(nome) }

    /// Copia a imagem para a pasta do Tasker (reduzida a 1600 px, em JPEG). Devolve o nome do arquivo.
    static func guardarFoto(_ origem: URL) -> String? {
        guard let imagem = NSImage(contentsOf: origem), imagem.size.width > 0, imagem.size.height > 0 else { return nil }
        let escala = min(1, 1600 / max(imagem.size.width, imagem.size.height))
        let tamanho = NSSize(width: (imagem.size.width * escala).rounded(), height: (imagem.size.height * escala).rounded())
        let reduzida = NSImage(size: tamanho, flipped: false) { rect in
            imagem.draw(in: rect)
            return true
        }
        guard let tiff = reduzida.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return nil }
        let nome = "\(UUID().uuidString).jpg"
        do {
            try jpeg.write(to: urlDaFoto(nome), options: .atomic)
            return nome
        } catch {
            return nil
        }
    }

    nonisolated static func semMarcador(_ linha: String) -> String {
        var s = linha.trimmingCharacters(in: .whitespaces)
        for prefixo in ["- [ ] ", "[ ] ", "☐ ", "- ", "• ", "* ", "– "] where s.hasPrefix(prefixo) {
            s.removeFirst(prefixo.count)
            break
        }
        // "1. " / "2) "
        if let ponto = s.firstIndex(where: { $0 == "." || $0 == ")" }), s[..<ponto].allSatisfy(\.isNumber),
           !s[..<ponto].isEmpty, s.index(after: ponto) < s.endIndex, s[s.index(after: ponto)] == " " {
            s = String(s[s.index(ponto, offsetBy: 2)...])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Notas

    /// Mais recentes primeiro.
    var notasOrdenadas: [Anotacao] { notas.sorted { $0.editada > $1.editada } }

    var diasComNota: Set<Date> { Set(notas.compactMap(\.dia)) }

    func nota(_ id: String) -> Anotacao? { notas.first { $0.id == id } }

    func notaDoDia(_ dia: Date) -> Anotacao? {
        let d = Calendar.current.startOfDay(for: dia)
        return notas.first { $0.dia == d }
    }

    /// Escreve a nota do dia; criada no primeiro caractere e apagada quando fica vazia.
    func escreverNoDia(_ dia: Date, texto: String) {
        let d = Calendar.current.startOfDay(for: dia)
        let vazio = texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let i = notas.firstIndex(where: { $0.dia == d }) {
            if vazio && notas[i].titulo.isEmpty {
                notas.remove(at: i)
            } else if notas[i].texto != texto {
                notas[i].texto = texto
                notas[i].editada = .now
            }
        } else if !vazio {
            notas.append(Anotacao(id: UUID().uuidString, titulo: "", texto: texto, dia: d, criada: .now, editada: .now))
            store.avisarSucesso("Nota do dia criada", icone: "note.text")
        }
        salvar()
    }

    @discardableResult
    func novaNota(titulo: String = "", texto: String = "", avisar: Bool = true) -> String {
        let nota = Anotacao(id: UUID().uuidString, titulo: titulo, texto: texto, dia: nil, criada: .now, editada: .now)
        notas.append(nota)
        if avisar { store.avisarSucesso("Nota criada", plural: "notas criadas", icone: "note.text") }
        salvar()
        return nota.id
    }

    func atualizar(_ id: String, titulo: String? = nil, texto: String? = nil) {
        guard let i = notas.firstIndex(where: { $0.id == id }) else { return }
        var mudou = false
        if let titulo, titulo != notas[i].titulo { notas[i].titulo = titulo; mudou = true }
        if let texto, texto != notas[i].texto { notas[i].texto = texto; mudou = true }
        guard mudou else { return }
        notas[i].editada = .now
        salvar()
    }

    /// Exclui a nota (com "Desfazer").
    func excluirNota(_ id: String) {
        guard let i = notas.firstIndex(where: { $0.id == id }) else { return }
        let nota = notas.remove(at: i)
        salvar()
        store.mostrarAviso("Nota excluída") { [weak self] in
            guard let self, !self.notas.contains(where: { $0.id == nota.id }) else { return }
            self.notas.append(nota)
            self.salvar()
        } confirmar: {}
    }

    /// Uma nota sem nada escrito some ao sair dela (não acumula notas vazias).
    func descartarSeVazia(_ id: String) {
        guard let i = notas.firstIndex(where: { $0.id == id }) else { return }
        let n = notas[i]
        if n.titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && n.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notas.remove(at: i)
            salvar()
        }
    }

    // MARK: Revisão da semana

    /// Nota da semana já montada: o que foi concluído, o que ficou, como está o despejo e as
    /// perguntas para a próxima. Abrir de novo na mesma semana devolve a mesma nota.
    @discardableResult
    func revisaoDaSemana(agora: Date = .now) -> String {
        let cal = Calendar.current
        let semana = cal.dateInterval(of: .weekOfYear, for: agora) ?? DateInterval(start: agora, duration: 7 * 86400)
        let fim = cal.adding(days: -1, to: semana.end)
        let titulo = "Semana de \(semana.start.formatted(.dateTime.day().month(.abbreviated))) a \(fim.formatted(.dateTime.day().month(.abbreviated)))"
        if let existente = notas.first(where: { $0.titulo == titulo && $0.dia == nil }) { return existente.id }

        let feitas = store.completedTasks.filter { ($0.completedDate ?? .distantPast) >= semana.start }
        let ficou = store.overdueTasks + store.todayTasks
        let tempo = feitas.reduce(0) { $0 + store.tempo(de: $1.id) }
        var linhas: [String] = []
        linhas.append("Concluídas (\(feitas.count))" + (tempo > 0 ? " · \(Duracao.curto(tempo)) registrados" : ""))
        linhas += feitas.prefix(30).map { "✓ \($0.displayTitle)" }
        if feitas.isEmpty { linhas.append("Nenhuma ainda — e tudo bem.") }
        linhas.append("")
        linhas.append("Ficou para depois (\(ficou.count))")
        linhas += ficou.prefix(15).map { "• \($0.displayTitle)" }
        linhas.append("")
        linhas.append("Despejo: \(despejo.count) na caixa · \(depois.count) em Depois")
        linhas.append("")
        linhas.append("Como foi a semana?")
        linhas.append("")
        linhas.append("")
        linhas.append("O que eu quero da próxima semana?")
        linhas.append("[ ] ")
        return novaNota(titulo: titulo, texto: linhas.joined(separator: "\n"))
    }

    // MARK: Tarefas dentro da nota ("[ ] comprar pão")

    struct Pendente: Hashable {
        let linha: Int
        let titulo: String
    }

    /// Linhas "[ ] algo" (ou "- [ ] algo", "☐ algo") que ainda não viraram tarefa.
    static func pendentes(em texto: String) -> [Pendente] {
        texto.components(separatedBy: "\n").enumerated().compactMap { i, linha in
            guard let resto = restoDoMarcador(linha) else { return nil }
            return resto.isEmpty ? nil : Pendente(linha: i, titulo: resto)
        }
    }

    private static func restoDoMarcador(_ linha: String) -> String? {
        let s = linha.trimmingCharacters(in: .whitespaces)
        for prefixo in ["- [ ]", "[ ]", "☐"] where s.hasPrefix(prefixo) {
            return String(s.dropFirst(prefixo.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Cria a tarefa da linha e marca a linha como enviada ("→ comprar pão").
    func criarTarefa(daLinha linha: Int, naNota id: String, listID: String?, due: Date?) {
        guard let i = notas.firstIndex(where: { $0.id == id }) else { return }
        var linhas = notas[i].texto.components(separatedBy: "\n")
        guard linhas.indices.contains(linha), let titulo = Self.restoDoMarcador(linhas[linha]), !titulo.isEmpty else { return }
        let recuo = linhas[linha].prefix { $0 == " " || $0 == "\t" }
        linhas[linha] = "\(recuo)→ \(titulo)"
        notas[i].texto = linhas.joined(separator: "\n")
        notas[i].editada = .now
        store.addTask(title: titulo, listID: listID, due: due)
        salvar()
    }

    // MARK: Busca

    /// Todas as palavras precisam aparecer (sem diferença de acento e maiúscula).
    /// O título pesa mais que o corpo; tarefas abertas e coisas recentes vêm antes.
    func buscar(_ consulta: String, limite: Int = 40) -> [ResultadoBusca] {
        let q = Self.normalizar(consulta).trimmingCharacters(in: .whitespacesAndNewlines)
        let palavras = q.split(separator: " ").map(String.init)
        guard !palavras.isEmpty else { return [] }

        func pontos(titulo: String, corpo: String) -> Int? {
            let t = Self.normalizar(titulo), c = Self.normalizar(corpo)
            guard palavras.allSatisfy({ t.contains($0) || c.contains($0) }) else { return nil }
            if t.hasPrefix(q) { return 100 }
            if t.contains(q) { return 70 }
            if palavras.allSatisfy({ t.contains($0) }) { return 50 }
            return 20
        }

        var resultado: [ResultadoBusca] = []
        for tarefa in store.tasks.values where !tarefa.isLocal {
            guard let p = pontos(titulo: tarefa.title, corpo: tarefa.notasVisiveis) else { continue }
            resultado.append(ResultadoBusca(tipo: .tarefa, alvo: tarefa.id, titulo: tarefa.displayTitle,
                                            trecho: Self.trecho(tarefa.notasVisiveis, palavras),
                                            data: tarefa.dueDay, concluida: tarefa.isCompleted,
                                            pontos: p + (tarefa.isCompleted ? 0 : 5)))
        }
        for nota in notas {
            guard let p = pontos(titulo: nota.tituloExibido, corpo: nota.texto) else { continue }
            resultado.append(ResultadoBusca(tipo: .nota, alvo: nota.id, titulo: nota.tituloExibido,
                                            trecho: Self.trecho(nota.texto, palavras), data: nota.dia ?? nota.editada,
                                            concluida: false, pontos: p + 3))
        }
        for item in itens {
            guard let p = pontos(titulo: item.texto, corpo: "") else { continue }
            resultado.append(ResultadoBusca(tipo: .despejo, alvo: item.id, titulo: item.texto, trecho: nil,
                                            data: item.criado, concluida: false, pontos: p + 2))
        }
        var eventosVistos = Set<String>()
        for evento in store.events where eventosVistos.insert(evento.id).inserted {
            guard let p = pontos(titulo: evento.title, corpo: "") else { continue }
            resultado.append(ResultadoBusca(tipo: .evento, alvo: evento.id, titulo: evento.title,
                                            trecho: nil, data: evento.start, concluida: false, pontos: p))
        }
        return Array(resultado.sorted {
            if $0.pontos != $1.pontos { return $0.pontos > $1.pontos }
            return ($0.data ?? .distantPast) > ($1.data ?? .distantPast)
        }.prefix(limite))
    }

    static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    /// Trecho do corpo em volta da primeira palavra encontrada.
    private static func trecho(_ corpo: String, _ palavras: [String]) -> String? {
        let linhas = corpo.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let linha = linhas.first(where: { l in palavras.contains { normalizar(l).contains($0) } }) ?? linhas.first
        else { return nil }
        let limpa = linha.trimmingCharacters(in: .whitespaces)
        return limpa.count > 90 ? String(limpa.prefix(90)) + "…" : limpa
    }

    // MARK: Disco

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Grava logo depois de parar de digitar (agrupa várias mudanças) e fora da thread principal.
    private func salvar() {
        gravacao?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.salvarAgora() }
        gravacao = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Grava já (ao fechar o app e nos testes).
    func salvarAgora(sincrono: Bool = false) {
        gravacao?.cancel()
        gravacao = nil
        LembreteDespejo.agendar(quantidade: despejo.count, prefs: store.prefs)
        let copia = Arquivo(despejo: itens, notas: notas)
        let url = arquivo
        let gravar = {
            guard let data = try? Self.encoder.encode(copia) else { return }
            try? data.write(to: url, options: .atomic)
        }
        if sincrono { gravar() } else { DispatchQueue.global(qos: .utility).async(execute: gravar) }
    }
}
