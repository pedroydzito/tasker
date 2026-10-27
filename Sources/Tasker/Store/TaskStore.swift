import AppKit
import Observation
import SwiftUI

/// Estado central: listas, tarefas e eventos — do Google ou só deste Mac.
@MainActor @Observable
final class TaskStore {
    let auth: GoogleAuth
    let prefs: Preferences
    @ObservationIgnored private let api: GoogleAPI
    @ObservationIgnored private var localBackend: LocalBackend?

    /// Google Tasks, ou o arquivo local no modo sem conta.
    var backend: TaskBackend {
        if prefs.localMode {
            if let localBackend { return localBackend }
            let local = LocalBackend()
            localBackend = local
            return local
        }
        return api
    }

    /// Tem de onde ler tarefas (conta Google ou modo local).
    var hasAccount: Bool { auth.isSignedIn || prefs.localMode }
    /// Agenda só existe com o Google conectado.
    var usesGoogle: Bool { auth.isSignedIn && !prefs.localMode }
    private var accountKey: String { prefs.localMode ? "local" : (auth.profile?.email ?? "") }

    private(set) var lists: [TaskList] = []
    /// Índice pronto (filtros e ordenações), recalculado só quando as tarefas mudam.
    private(set) var index = TaskIndex()
    /// Nome, emoji, cor e ordem de cada lista, pré-calculados.
    private(set) var listMeta: [String: ListMeta] = [:]
    private(set) var calendars: [CalendarInfo] = []
    private(set) var events: [CalendarEvent] = [] { didSet { eventosPorDia = [:] } }
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    var lastError: String?
    /// Problema específico do Google Calendar (API desativada, permissão negada...). Não bloqueia as tarefas.
    private(set) var calendarIssue: APIError?
    private(set) var listPhotos: [String: NSImage] = [:]
    /// Intervalo já sincronizado em `events`.
    private(set) var eventRange: Range<Date>?
    private(set) var today = Calendar.current.startOfDay(for: .now)
    private(set) var tagDB = TagDatabase.load()
    /// Aviso de "excluído — Desfazer" (some sozinho em 3 s).
    private(set) var aviso: AvisoDesfazer?
    /// Aviso de sucesso ("✓ Tarefa adicionada"), some em 2 s. Ações seguidas se somam.
    private(set) var sucesso: AvisoSucesso?
    @ObservationIgnored private var tarefaSucesso: Task<Void, Never>?

    /// Fonte das tarefas. Toda alteração reconstrói o índice uma única vez.
    @ObservationIgnored private var taskMap: [String: TaskItem] = [:] {
        didSet { rebuildIndex() }
    }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var listMarks: [String: Date] = [:]
    @ObservationIgnored private var lastFullSync = Date.distantPast
    @ObservationIgnored private var lastEventSync = Date.distantPast
    @ObservationIgnored private var pendingIDs: Set<String> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var listasSaindo: Set<String> = []
    /// Operações de cada tarefa rodam em fila (salvar e mover não disputam entre si).
    @ObservationIgnored private var filas: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    /// Sincronização forçada pedida enquanto outra rodava: roda de novo ao terminar.
    @ObservationIgnored private var syncPendente = false
    /// Muda a cada reset (sair, trocar de conta ou de modo): respostas de antes são descartadas.
    @ObservationIgnored private var geracao = 0
    /// Id provisório ("local-…") → id definitivo, para edições feitas antes de a tarefa ser criada.
    @ObservationIgnored private var idsCriados: [String: String] = [:]
    @ObservationIgnored private var eventosPorDia: [Date: [CalendarEvent]] = [:]
    @ObservationIgnored private var cacheAgendado: DispatchWorkItem?
    @ObservationIgnored private var tarefaAviso: Task<Void, Never>?

    /// A lista principal do Google ("Minhas tarefas"), sempre a primeira.
    var pinnedListID: String? {
        get { Pastas.defaults.string(forKey: "pinnedListID") }
        set { Pastas.defaults.set(newValue, forKey: "pinnedListID") }
    }

    init(auth: GoogleAuth, api: GoogleAPI, prefs: Preferences) {
        self.auth = auth
        self.api = api
        self.prefs = prefs
    }

    // MARK: Consultas (leituras baratas do índice)

    var tasks: [String: TaskItem] { index.byID }
    var todayTasks: [TaskItem] { porHorario(index.today) }
    var overdueTasks: [TaskItem] { index.overdue }
    var completedToday: [TaskItem] { index.completedToday }
    var completedTasks: [TaskItem] { index.completed }
    var undatedTasks: [TaskItem] { index.undated }
    var laterTasks: [TaskItem] { index.later }
    var activeCount: Int { index.activeCount }

    /// Número exibido na barra de menu.
    var badgeCount: Int {
        index.today.count + (prefs.includeOverdueInCount ? index.overdue.count : 0)
    }

    /// Tarefas do dia; as com horário vêm primeiro, em ordem de hora.
    func tasks(on day: Date) -> [TaskItem] { porHorario(index.byDay[day] ?? []) }

    func porHorario(_ tarefas: [TaskItem]) -> [TaskItem] {
        let comHora = tarefas.filter { $0.horario != nil }
        guard !comHora.isEmpty else { return tarefas }
        return comHora.sorted { ($0.horario ?? "") < ($1.horario ?? "") } + tarefas.filter { $0.horario == nil }
    }
    func tasks(inList listID: String) -> [TaskItem] { index.byList[listID] ?? [] }
    func completedTasks(inList listID: String) -> [TaskItem] { index.completedByList[listID] ?? [] }
    /// Concluídas cuja data era este dia (para o calendário mostrar riscadas).
    func completedTasks(on day: Date) -> [TaskItem] { index.completedByDay[day] ?? [] }

    private func rebuildIndex() {
        let order = Dictionary(uniqueKeysWithValues: lists.enumerated().map { ($1.id, $0) })
        index = TaskIndex(map: taskMap, today: today, listOrder: order)
    }

    func events(on day: Date) -> [CalendarEvent] {
        if let pronto = eventosPorDia[day] { return pronto }
        let doDia = events.filter { $0.overlaps(dayStart: day) }
        eventosPorDia[day] = doDia
        return doDia
    }

    func list(_ id: String) -> TaskList? { lists.first { $0.id == id } }

    var defaultList: TaskList? {
        prefs.defaultListID.flatMap(list) ?? lists.first
    }

    func color(forList id: String) -> Color {
        listMeta[id]?.color ?? .gray
    }

    func setColor(_ color: Color, forList id: String) {
        prefs.listColors[id] = color.hexString
        rebuildListMeta()
    }

    private func rebuildListMeta() {
        var meta: [String: ListMeta] = [:]
        let colors = prefs.listColors
        let symbols = prefs.listSymbols
        for (i, list) in lists.enumerated() {
            let (prefix, rest) = Self.splitLeadingSymbols(list.title)
            _ = prefix // o emoji do nome no Google é ignorado: o ícone é escolhido no app
            let symbol: String? = symbols[list.id].flatMap { $0.isEmpty ? nil : $0 }
            let hex = colors[list.id] ?? Self.corDaChave(list.id)
            meta[list.id] = ListMeta(name: rest.isEmpty ? list.title : rest, symbol: symbol, color: Color(hex: hex), order: i)
        }
        listMeta = meta
    }

    /// Cor estável que sai do próprio id (não muda ao reordenar nem entre aparelhos).
    /// Passo 3 sobre 10: chaves vizinhas não caem em cores vizinhas.
    static func corDaChave(_ id: String) -> String {
        var hash: UInt64 = 5381
        for byte in id.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Palette.lists[Int((hash &* 3) % UInt64(Palette.lists.count))]
    }

    /// Aplica a ordem escolhida pelo usuário; listas novas vão para o fim, na ordem do Google.
    private func ordered(_ input: [TaskList]) -> [TaskList] {
        let order = prefs.listOrder
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        var result = input.enumerated().sorted { a, b in
            let pa = position[a.element.id] ?? (order.count + a.offset)
            let pb = position[b.element.id] ?? (order.count + b.offset)
            return pa < pb
        }.map(\.element)
        // "Minhas tarefas" fica sempre em primeiro.
        if let pinned = pinnedListID, let i = result.firstIndex(where: { $0.id == pinned }), i != 0 {
            result.insert(result.remove(at: i), at: 0)
        }
        return result
    }

    /// Move uma lista para uma posição (arrastar na barra lateral).
    func moveList(_ id: String, toIndex target: Int) {
        guard id != pinnedListID, let from = lists.firstIndex(where: { $0.id == id }) else { return }
        let minimo = pinnedListID == nil ? 0 : 1
        let to = max(minimo, min(target, lists.count - 1))
        guard from != to else { return }
        var reordered = lists
        let item = reordered.remove(at: from)
        reordered.insert(item, at: to)
        prefs.listOrder = reordered.map(\.id)
        lists = reordered
        listsChanged()
    }

    /// Cria a lista (no Google, aparece lá também) com ícone e cor do app.
    @discardableResult
    func createList(title: String, symbol: String?, colorHex: String?) async -> String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        do {
            let created = try await backend.insertList(title: name)
            if let symbol { prefs.listSymbols[created.id] = symbol }
            if let colorHex { prefs.listColors[created.id] = colorHex }
            lists.append(TaskList(id: created.id, title: created.title ?? name))
            prefs.listOrder = lists.map(\.id)
            listMarks[created.id] = .now
            listsChanged()
            avisarSucesso("Lista criada", plural: "listas criadas")
            saveCache()
            return created.id
        } catch {
            lastError = "Não consegui criar a lista: \(error.localizedDescription)"
            return nil
        }
    }

    func renameList(_ id: String, to title: String) async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = lists.firstIndex(where: { $0.id == id }) else { return }
        let original = lists[i].title
        lists[i].title = name
        listsChanged()
        do {
            _ = try await backend.renameList(id: id, title: name)
            saveCache()
        } catch {
            if let j = lists.firstIndex(where: { $0.id == id }) { lists[j].title = original }
            listsChanged()
            lastError = "Não consegui renomear a lista: \(error.localizedDescription)"
        }
    }

    /// Exclui a lista: some na hora, e só é apagada de verdade se não houver "Desfazer" em 3 s.
    func deleteList(_ id: String) async {
        guard id != pinnedListID, let i = lists.firstIndex(where: { $0.id == id }) else { return }
        let lista = lists[i]
        let tarefas = taskMap.filter { $0.value.listID == id }
        listasSaindo.insert(id)
        lists.remove(at: i)
        taskMap = taskMap.filter { $0.value.listID != id }
        listsChanged()
        mostrarAviso("Lista “\(displayNameFallback(lista))” excluída") { [weak self] in
            guard let self else { return }
            self.listasSaindo.remove(id)
            self.lists.insert(lista, at: min(i, self.lists.count))
            self.taskMap.merge(tarefas) { a, _ in a }
            self.listsChanged()
        } confirmar: { [weak self] in
            guard let self else { return }
            do {
                try await self.backend.deleteList(id: id)
                self.listasSaindo.remove(id)
                self.removePhoto(forList: id)
                self.prefs.listSymbols[id] = nil
                self.prefs.listColors[id] = nil
                self.prefs.listOrder.removeAll { $0 == id }
                if self.prefs.defaultListID == id { self.prefs.defaultListID = nil }
                self.saveCache()
            } catch {
                self.listasSaindo.remove(id)
                self.lastError = "Não consegui excluir a lista: \(error.localizedDescription)"
                await self.sync(force: true)
            }
        }
    }

    private func displayNameFallback(_ list: TaskList) -> String {
        let (_, nome) = Self.splitLeadingSymbols(list.title)
        return nome.isEmpty ? list.title : nome
    }

    // MARK: Desfazer

    /// Mostra o aviso por 3 s. Se ninguém desfizer, roda `confirmar` (a exclusão de verdade).
    func mostrarAviso(_ texto: String, desfazer: @escaping () -> Void, confirmar: @escaping () async -> Void) {
        if let anterior = aviso { anterior.expirar() }
        tarefaAviso?.cancel()
        let novo = AvisoDesfazer(texto: texto, desfazer: desfazer, confirmar: confirmar)
        aviso = novo
        tarefaAviso = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.aviso?.id == novo.id else { return }
            self.aviso = nil
            novo.expirar()
        }
    }

    /// "✓ Tarefa adicionada"; repetido em seguida vira "3 tarefas adicionadas".
    func avisarSucesso(_ singular: String, plural: String? = nil, icone: String = "checkmark.circle.fill") {
        var novo = AvisoSucesso(singular: singular, plural: plural ?? singular, icone: icone)
        if let atual = sucesso, atual.singular == singular { novo.quantidade = atual.quantidade + 1 }
        sucesso = novo
        tarefaSucesso?.cancel()
        tarefaSucesso = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.sucesso?.id == novo.id else { return }
            self.sucesso = nil
        }
    }

    func desfazerAviso() {
        guard let atual = aviso else { return }
        tarefaAviso?.cancel()
        aviso = nil
        atual.cancelar()
    }

    // MARK: Modo de uso

    /// Usar sem conta: troca para o arquivo local.
    func useLocalMode() {
        prefs.localMode = true
        reset()
        Task { await sync(force: true) }
    }

    /// Depois de entrar com o Google: sai do modo local.
    func useGoogleMode() {
        prefs.localMode = false
        reset()
        Task { await sync(force: true) }
    }

    /// Move uma lista para a posição de outra (arrastar na barra lateral).
    func moveList(_ id: String, to targetID: String) {
        guard id != targetID, id != pinnedListID, targetID != pinnedListID,
              let from = lists.firstIndex(where: { $0.id == id }),
              let to = lists.firstIndex(where: { $0.id == targetID }) else { return }
        var reordered = lists
        let item = reordered.remove(at: from)
        reordered.insert(item, at: to)
        prefs.listOrder = reordered.map(\.id)
        lists = reordered
        listsChanged()
    }

    /// Chamado sempre que `lists` muda.
    private func listsChanged() {
        rebuildListMeta()
        rebuildIndex()
    }

    // MARK: Aparência das listas (emoji / foto)

    /// Nome sem o emoji inicial ("🎨 Taís" → "Taís").
    func displayName(_ listID: String) -> String {
        listMeta[listID]?.name ?? ""
    }

    /// Ícone escolhido no app (SF Symbol); sem escolha, a lista mostra a inicial.
    func symbol(forList id: String) -> String? {
        listMeta[id]?.symbol
    }

    func setSymbol(_ symbol: String?, forList id: String) {
        prefs.listSymbols[id] = symbol ?? ""
        rebuildListMeta()
    }

    func photo(forList id: String) -> NSImage? { listPhotos[id] }

    func setPhoto(from url: URL, forList id: String) {
        guard let image = NSImage(contentsOf: url) else { return }
        let side: CGFloat = 160
        let square = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let s = image.size
            let scale = max(side / max(s.width, 1), side / max(s.height, 1))
            let w = s.width * scale, h = s.height * scale
            image.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
            return true
        }
        guard let tiff = square.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: Self.photoURL(id), options: .atomic)
        listPhotos[id] = NSImage(data: png)
    }

    func removePhoto(forList id: String) {
        try? FileManager.default.removeItem(at: Self.photoURL(id))
        listPhotos[id] = nil
    }

    private static func photoURL(_ listID: String) -> URL {
        let dir = Pastas.pasta("ListPhotos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = listID.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(safe).png")
    }

    private func loadPhotos() {
        for list in lists {
            if let image = NSImage(contentsOf: Self.photoURL(list.id)) { listPhotos[list.id] = image }
        }
    }

    /// Separa símbolos/emojis do começo do texto do restante.
    static func splitLeadingSymbols(_ text: String) -> (String, String) {
        let index = text.firstIndex { ch in ch.unicodeScalars.first.map { CharacterSet.alphanumerics.contains($0) } ?? false }
            ?? text.endIndex
        let prefix = text[..<index].trimmingCharacters(in: .whitespaces)
        let rest = text[index...].trimmingCharacters(in: .whitespaces)
        return (prefix, rest)
    }

    func isVisible(_ calendar: CalendarInfo) -> Bool {
        prefs.calendarVisibility[calendar.id] ?? calendar.selectedInGoogle
    }

    func setVisible(_ visible: Bool, calendar: CalendarInfo) {
        prefs.calendarVisibility[calendar.id] = visible
        Task { await syncEvents(force: true) }
    }

    /// Tarefas de uma lista com subtarefas logo abaixo da tarefa-mãe.
    func hierarchy(_ items: [TaskItem]) -> [IndentedTask] {
        let ids = Set(items.map(\.id))
        let byParent = Dictionary(grouping: items) { task in task.parent.flatMap { ids.contains($0) ? $0 : nil } ?? "" }
        var out: [IndentedTask] = []
        func walk(_ parentID: String, _ depth: Int) {
            for task in (byParent[parentID] ?? []).sorted(by: { ($0.position ?? "") < ($1.position ?? "") }) {
                out.append(IndentedTask(task: task, depth: depth))
                walk(task.id, depth + 1)
            }
        }
        walk("", 0)
        return out
    }

    // MARK: Ciclo de vida

    func start() {
        loadCache()
        loadPhotos()
        scheduleTimer()

        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshToday()
                await self?.sync(force: true)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshToday()
                await self?.sync(force: true)
            }
        })

        Task { await sync(force: true) }
    }

    func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(10, prefs.syncInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
        timer?.tolerance = 3
    }

    func refreshToday() {
        let now = Calendar.current.startOfDay(for: .now)
        if now != today {
            today = now
            rebuildIndex()
        }
    }

    func reset() {
        geracao += 1
        tarefaAviso?.cancel()
        aviso = nil
        pendingIDs = []
        filas = [:]
        idsCriados = [:]
        syncPendente = false
        eventRange = nil
        lastFullSync = .distantPast
        listPhotos = [:]
        lists = []
        listsChanged()
        taskMap = [:]
        calendars = []
        events = []
        calendarIssue = nil
        listMarks = [:]
        lastSync = nil
        lastEventSync = .distantPast
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    // MARK: Sincronização

    func sync(force: Bool = false) async {
        guard hasAccount else { return }
        guard !isSyncing else {
            if force { syncPendente = true }
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            if syncPendente {
                syncPendente = false
                Task { await sync(force: true) }
            }
        }
        refreshToday()

        do {
            let full = force || Date().timeIntervalSince(lastFullSync) > 15 * 60
            try await syncTasks(full: full)
            if full { lastFullSync = .now }
            if force || Date().timeIntervalSince(lastEventSync) > 90 {
                await syncEventsSafely()
            }
            lastSync = .now
            lastError = nil
            saveCache()
        } catch {
            if (error as? URLError)?.code != .cancelled {
                lastError = error.localizedDescription
            }
        }
    }

    private func syncTasks(full: Bool) async throws {
        let geracaoInicial = geracao
        let remoteLists = try await backend.fetchTaskLists()
        guard geracao == geracaoInicial else { return }
        let hadLists = !lists.isEmpty
        // O Google devolve a lista principal primeiro; ela fica fixa no topo.
        if let first = remoteLists.first?.id { pinnedListID = first }
        let newLists = ordered(remoteLists.filter { !listasSaindo.contains($0.id) }
            .map { TaskList(id: $0.id, title: $0.title ?? "Sem título") })
        if newLists != lists {
            lists = newLists
            listsChanged()
        }
        if !hadLists { loadPhotos() }
        let listIDs = Set(lists.map(\.id))

        // Junta tudo numa cópia e aplica de uma vez (um único rebuild do índice).
        let inicio = taskMap
        var map = taskMap.filter { listIDs.contains($0.value.listID) }
        var changed = map.count != taskMap.count
        // Busca todas as listas ao mesmo tempo.
        let backend = self.backend
        let pedidos = lists.map { ($0.id, full ? nil : listMarks[$0.id]) }
        let started = Date()
        let respostas = try await withThrowingTaskGroup(of: (String, [GTask]).self) { group in
            for (id, since) in pedidos {
                // Margem de 2 min para não perder alterações por diferença de relógio.
                group.addTask { (id, try await backend.fetchTasks(listID: id, updatedMin: since?.addingTimeInterval(-120))) }
            }
            var todas: [String: [GTask]] = [:]
            for try await (id, tarefas) in group { todas[id] = tarefas }
            return todas
        }
        guard geracao == geracaoInicial else { return }
        for (listID, since) in pedidos {
            let remote = respostas[listID] ?? []

            if since == nil {
                let remoteIDs = Set(remote.map(\.id))
                let before = map.count
                map = map.filter { _, task in
                    task.listID != listID || remoteIDs.contains(task.id) || task.isLocal || pendingIDs.contains(task.id)
                }
                if map.count != before { changed = true }
            }
            for g in remote where !pendingIDs.contains(g.id) {
                if g.deleted == true {
                    if map.removeValue(forKey: g.id) != nil { changed = true }
                } else {
                    let item = TaskItem(g, listID: listID)
                    if map[g.id] != item {
                        map[g.id] = item
                        changed = true
                    }
                }
            }
            listMarks[listID] = started
        }
        // O que mudou aqui enquanto a rede respondia vale mais que a resposta.
        for (id, atual) in taskMap where inicio[id] != atual {
            map[id] = atual
            changed = true
        }
        for id in inicio.keys where taskMap[id] == nil {
            if map.removeValue(forKey: id) != nil { changed = true }
        }
        if changed { taskMap = map }
    }

    func syncEvents(force: Bool = false) async {
        await syncEventsSafely()
        saveCache()
    }

    private func syncEventsSafely() async {
        guard usesGoogle else {
            calendars = []
            events = []
            calendarIssue = nil
            return
        }
        do {
            try await syncEventsNow()
            calendarIssue = nil
        } catch let error as APIError {
            calendarIssue = error
            lastEventSync = .now
        } catch {
            lastEventSync = .now
        }
    }

    private func syncEventsNow() async throws {
        let geracaoInicial = geracao
        let remote = try await api.fetchCalendars()
        guard geracao == geracaoInicial else { return }
        calendars = remote
            .filter { $0.hidden != true }
            .map {
                CalendarInfo(id: $0.id, title: $0.summaryOverride ?? $0.summary ?? $0.id,
                             colorHex: $0.backgroundColor ?? "#4285F4", isPrimary: $0.primary == true,
                             selectedInGoogle: $0.selected == true || $0.primary == true)
            }
            .sorted { ($0.isPrimary ? 0 : 1, $0.title) < ($1.isPrimary ? 0 : 1, $1.title) }

        // Do mês anterior até dois meses à frente (com a grade de semanas), para o
        // calendário abrir já preenchido, sem esperar a rede.
        let cal = Calendar.current
        let month = cal.dateInterval(of: .month, for: today)?.start ?? today
        let from = cal.adding(days: -7, to: cal.date(byAdding: .month, value: -1, to: month) ?? month)
        let to = cal.adding(days: 14, to: cal.date(byAdding: .month, value: 3, to: month) ?? month)
        let novos = await loadEvents(from: from, to: to)
        guard geracao == geracaoInicial else { return }
        events = novos
        eventRange = from..<to
        lastEventSync = .now
    }

    /// Busca eventos de todos os calendários visíveis em um intervalo (usado também pela tela de calendário).
    func loadEvents(from: Date, to: Date) async -> [CalendarEvent] {
        guard usesGoogle else { return [] }
        let api = self.api
        let visiveis = calendars.filter { isVisible($0) }
        let result = await withTaskGroup(of: [CalendarEvent].self) { group in
            for calendar in visiveis {
                group.addTask {
                    guard let items = try? await api.fetchEvents(calendarID: calendar.id, from: from, to: to) else { return [] }
                    return items.compactMap { CalendarEvent($0, calendar: calendar) }
                }
            }
            var todos: [CalendarEvent] = []
            for await parte in group { todos += parte }
            return todos
        }
        return result.sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// Move todas as tarefas atrasadas para hoje (botão "Adiar" do TickTick).
    func postponeOverdue() {
        for task in overdueTasks { setDue(task, today) }
    }

    // MARK: Etiquetas locais

    var tags: [Tag] {
        if let tagsOrdenadas, let base = tagsOrdenadasBase, base == (tagDB.tags, prefs.tagOrder) { return tagsOrdenadas }
        let ordenadas = ordenarTags()
        tagsOrdenadas = ordenadas
        tagsOrdenadasBase = (tagDB.tags, prefs.tagOrder)
        return ordenadas
    }
    @ObservationIgnored private var tagsOrdenadas: [Tag]?
    @ObservationIgnored private var tagsOrdenadasBase: ([Tag], [String])?

    private func ordenarTags() -> [Tag] {
        let order = prefs.tagOrder
        guard !order.isEmpty else { return tagDB.tags }
        let pos = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return tagDB.tags.enumerated().sorted {
            (pos[$0.element.id] ?? order.count + $0.offset) < (pos[$1.element.id] ?? order.count + $1.offset)
        }.map(\.element)
    }

    func moveTag(_ id: String, toIndex target: Int) {
        var ordered = tags
        guard let from = ordered.firstIndex(where: { $0.id == id }) else { return }
        let to = max(0, min(target, ordered.count - 1))
        guard from != to else { return }
        let item = ordered.remove(at: from)
        ordered.insert(item, at: to)
        prefs.tagOrder = ordered.map(\.id)
    }

    func tags(for task: TaskItem) -> [Tag] {
        let ids = tagDB.assignments[task.id] ?? []
        return tags.filter { ids.contains($0.id) }
    }

    func tasks(withTag tagID: String) -> [TaskItem] {
        index.active.filter { tagDB.assignments[$0.id]?.contains(tagID) == true }
    }

    func tag(_ id: String) -> Tag? { tagDB.tags.first { $0.id == id } }

    /// Encontra etiquetas pelo nome (ignorando acentos/maiúsculas) e cria as que não existem.
    func resolveTags(named names: [String]) -> [String] {
        names.compactMap { name in
            let key = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            if let existing = tagDB.tags.first(where: {
                $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) == key
            }) {
                return existing.id
            }
            return createTag(name: name).id
        }
    }

    @discardableResult
    func createTag(name: String, colorHex: String? = nil) -> Tag {
        let tag = Tag(id: UUID().uuidString, name: name,
                      colorHex: colorHex ?? Palette.lists[tagDB.tags.count % Palette.lists.count])
        tagDB.tags.append(tag)
        tagDB.save()
        return tag
    }

    func updateTag(_ tag: Tag) {
        guard let index = tagDB.tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tagDB.tags[index] = tag
        tagDB.save()
    }

    func deleteTag(_ tag: Tag) {
        let copia = tagDB
        tagDB.tags.removeAll { $0.id == tag.id }
        for (taskID, ids) in tagDB.assignments {
            let remaining = ids.filter { $0 != tag.id }
            tagDB.assignments[taskID] = remaining.isEmpty ? nil : remaining
        }
        tagDB.save()
        mostrarAviso("Etiqueta “\(tag.name)” excluída") { [weak self] in
            self?.tagDB = copia
            self?.tagDB.save()
        } confirmar: {}
    }

    /// Horário opcional da tarefa ("HH:mm"), guardado no app.
    func horario(of task: TaskItem) -> String? { task.horario }

    /// Define as etiquetas de uma tarefa de uma vez (usado ao salvar uma edição).
    func setTags(_ ids: [String], on task: TaskItem) {
        tagDB.assignments[task.id] = ids.isEmpty ? nil : ids
        tagDB.save()
    }

    func toggleTag(_ tag: Tag, on task: TaskItem) {
        var ids = tagDB.assignments[task.id] ?? []
        if let index = ids.firstIndex(of: tag.id) { ids.remove(at: index) } else { ids.append(tag.id) }
        tagDB.assignments[task.id] = ids.isEmpty ? nil : ids
        tagDB.save()
    }

    // MARK: Alterações (otimistas)

    func addTask(title: String, listID: String? = nil, due: Date?, notes: String? = nil, tagIDs: [String] = [],
                 horario: String? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let listID = listID ?? defaultList?.id else { return }

        let tempID = "local-\(UUID().uuidString)"
        let dueString = due.map(TaskItem.dueString)
        let notas = horario.map { HorarioNasNotas.juntar(notes ?? "", $0) } ?? notes
        taskMap[tempID] = TaskItem(id: tempID, listID: listID, title: title, notes: notas, due: dueString, position: "")
        avisarSucesso("Tarefa adicionada", plural: "tarefas adicionadas")
        if !tagIDs.isEmpty { tagDB.assignments[tempID] = tagIDs }

        enfileirar(tempID) { [self] in
            do {
                let created = try await backend.insertTask(listID: listID, title: title, notes: notas, due: dueString)
                idsCriados[tempID] = created.id
                // Mantém o que foi mudado aqui enquanto o Google criava (as mudanças seguem na fila).
                var item = TaskItem(created, listID: listID)
                if let local = taskMap[tempID] {
                    item.title = local.title
                    item.notes = local.notes
                    item.due = local.due
                    item.isCompleted = local.isCompleted
                    item.completed = local.completed
                }
                taskMap[tempID] = nil
                taskMap[created.id] = item
                if let tags = tagDB.assignments.removeValue(forKey: tempID) {
                    tagDB.assignments[created.id] = tags
                }
                tagDB.save()
                saveCache()
            } catch {
                taskMap[tempID] = nil
                tagDB.assignments[tempID] = nil
                lastError = "Não foi possível criar a tarefa: \(error.localizedDescription)"
            }
        }
    }

    /// Subtarefas de uma tarefa, na ordem do Google.
    func subtarefas(de id: String) -> [TaskItem] {
        index.filhas[id] ?? []
    }

    /// Cria uma subtarefa (no Google também). Aparece na hora; some se o Google recusar.
    func addSubtask(title: String, parent: TaskItem) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !parent.isLocal else { return }
        let tempID = "local-\(UUID().uuidString)"
        // Posição alta: entra no fim das subtarefas até o Google devolver a real.
        var provisoria = TaskItem(id: tempID, listID: parent.listID, title: title, position: "~")
        provisoria.parent = parent.id
        taskMap[tempID] = provisoria
        avisarSucesso("Subtarefa adicionada", plural: "subtarefas adicionadas")
        enfileirar(tempID) { [self] in
            do {
                let created = try await backend.insertTask(listID: parent.listID, title: title, notes: nil, due: nil,
                                                           parent: parent.id)
                idsCriados[tempID] = created.id
                var item = TaskItem(created, listID: parent.listID)
                if let local = taskMap[tempID] {
                    item.title = local.title
                    item.isCompleted = local.isCompleted
                    item.completed = local.completed
                }
                taskMap[tempID] = nil
                taskMap[created.id] = item
                saveCache()
            } catch {
                taskMap[tempID] = nil
                lastError = "Não foi possível criar a subtarefa: \(error.localizedDescription)"
            }
        }
    }

    func setCompleted(_ task: TaskItem, _ done: Bool) {
        if done && prefs.completionSound { NSSound(named: "Pop")?.play() }
        let fields: [String: Any] = done
            ? ["status": "completed"]
            : ["status": "needsAction", "completed": NSNull()]
        mutate(task, fields: fields) {
            $0.isCompleted = done
            $0.completed = done ? RFC3339.string(.now) : nil
        }
    }

    func setDue(_ task: TaskItem, _ day: Date?) {
        let due = day.map(TaskItem.dueString)
        mutate(task, fields: ["due": due.map { $0 as Any } ?? NSNull()]) { $0.due = due }
    }

    /// Salva título, notas e data numa única chamada (só envia o que mudou).
    func save(_ task: TaskItem, title: String, notes: String, due day: Date?) {
        var fields: [String: Any] = [:]
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != task.title { fields["title"] = title }
        if notes != (task.notes ?? "") { fields["notes"] = notes }
        let due = day.map(TaskItem.dueString)
        if day != task.dueDay { fields["due"] = due.map { $0 as Any } ?? NSNull() }
        guard !fields.isEmpty else { return }
        mutate(task, fields: fields) {
            if let t = fields["title"] as? String { $0.title = t }
            if fields["notes"] != nil { $0.notes = notes }
            if fields["due"] != nil { $0.due = due }
        }
    }

    /// Troca a tarefa de lista (arrastar para a barra lateral ou escolher no detalhe).
    func moveTask(_ task: TaskItem, toList destino: String) {
        guard !task.isLocal, task.listID != destino, let original = taskMap[task.id] else { return }
        var movida = original
        movida.listID = destino
        movida.parent = nil
        taskMap[task.id] = movida
        enfileirar(task.id) { [self] in
            do {
                let result = try await backend.moveTask(listID: original.listID, taskID: task.id, toList: destino)
                taskMap[task.id] = nil
                taskMap[result.id] = TaskItem(result, listID: destino)
                if result.id != task.id, let tags = tagDB.assignments.removeValue(forKey: task.id) {
                    tagDB.assignments[result.id] = tags
                    tagDB.save()
                }
                saveCache()
            } catch {
                taskMap[task.id] = original
                lastError = "Não consegui mudar a tarefa de lista: \(error.localizedDescription)"
            }
        }
    }

    /// Exclui a tarefa: some na hora; só é apagada de verdade se não houver "Desfazer" em 3 s.
    func delete(_ task: TaskItem) {
        guard !task.isLocal, let original = taskMap[task.id] else { return }
        // O Google apaga as subtarefas junto; aqui elas somem (e voltam no Desfazer) também.
        let filhas = taskMap.values.filter { $0.parent == task.id }
        var semElas = taskMap
        semElas[task.id] = nil
        for filha in filhas { semElas[filha.id] = nil }
        taskMap = semElas
        pendingIDs.insert(task.id)
        mostrarAviso("Tarefa excluída") { [weak self] in
            guard let self else { return }
            var de_volta = self.taskMap
            de_volta[task.id] = original
            for filha in filhas { de_volta[filha.id] = filha }
            self.taskMap = de_volta
            self.pendingIDs.remove(task.id)
        } confirmar: { [weak self] in
            guard let self else { return }
            defer { self.pendingIDs.remove(task.id) }
            do {
                try await self.backend.deleteTask(listID: task.listID, taskID: task.id)
                self.tagDB.assignments[task.id] = nil
                self.tagDB.horarios[task.id] = nil
                self.tagDB.save()
                self.saveCache()
            } catch {
                self.taskMap[task.id] = original
                self.lastError = "Não foi possível excluir: \(error.localizedDescription)"
            }
        }
    }

    private func mutate(_ task: TaskItem, fields: [String: Any], local: (inout TaskItem) -> Void) {
        if task.isLocal {
            mutarRecemCriada(task, fields: fields, local: local)
            return
        }
        let original = taskMap[task.id] ?? task
        var updated = original
        local(&updated)
        taskMap[task.id] = updated
        // Lista em que a tarefa estará quando o pedido rodar (a fila garante a ordem).
        let listID = original.listID
        enfileirar(task.id) { [self] in
            do {
                let result = try await backend.patchTask(listID: listID, taskID: task.id, fields: fields)
                if var atual = taskMap[result.id] {
                    // Mantém o que outros pedidos na fila já mudaram localmente.
                    let novo = TaskItem(result, listID: listID)
                    if fields["title"] != nil { atual.title = novo.title }
                    if fields["notes"] != nil { atual.notes = novo.notes }
                    if fields["due"] != nil { atual.due = novo.due }
                    if fields["status"] != nil { atual.isCompleted = novo.isCompleted; atual.completed = novo.completed }
                    taskMap[result.id] = atual
                }
                saveCache()
            } catch {
                taskMap[task.id] = original
                lastError = "Não foi possível salvar: \(error.localizedDescription)"
            }
        }
    }

    /// Tarefa ainda sendo criada: muda na hora e envia depois que o Google devolver o id definitivo.
    private func mutarRecemCriada(_ task: TaskItem, fields: [String: Any], local: (inout TaskItem) -> Void) {
        guard var atual = taskMap[task.id] else { return }
        local(&atual)
        taskMap[task.id] = atual
        let tempID = task.id
        enfileirar(tempID) { [self] in
            guard let id = idsCriados[tempID], let criada = taskMap[id] else { return }
            do {
                _ = try await backend.patchTask(listID: criada.listID, taskID: id, fields: fields)
            } catch {
                lastError = "Não foi possível salvar: \(error.localizedDescription)"
            }
        }
    }

    /// Espera todas as operações em andamento terminarem (autoteste e encerramento).
    func aguardarOperacoes() async {
        while let (id, fila) = filas.first {
            await fila.task.value
            // A fila se remove sozinha ao terminar; se ainda estiver aqui, não espera de novo.
            if filas[id]?.token == fila.token {
                filas[id] = nil
                pendingIDs.remove(id)
            }
        }
    }

    /// Roda `op` depois das operações anteriores da mesma tarefa; a sync não a sobrescreve enquanto houver fila.
    private func enfileirar(_ id: String, _ op: @escaping @MainActor () async -> Void) {
        let anterior = filas[id]?.task
        let token = UUID()
        pendingIDs.insert(id)
        let task = Task { @MainActor [weak self] in
            await anterior?.value
            await op()
            guard let self, self.filas[id]?.token == token else { return }
            self.filas[id] = nil
            self.pendingIDs.remove(id)
        }
        filas[id] = (token, task)
    }

    // MARK: Cache em disco (abre instantaneamente, mesmo offline)

    private struct Snapshot: Codable {
        var email: String?
        var lists: [TaskList]
        var tasks: [TaskItem]
        var calendars: [CalendarInfo]
        var events: [CalendarEvent]
        var listMarks: [String: Date]
        var eventFrom: Date?
        var eventTo: Date?
    }

    private static var cacheURL: URL {
        let dir = Pastas.base
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cache.json")
    }

    /// Junta várias gravações seguidas numa só e grava fora da thread principal.
    private func saveCache() {
        cacheAgendado?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.gravarCache() }
        cacheAgendado = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    private func gravarCache() {
        let snapshot = Snapshot(email: accountKey, lists: lists, tasks: taskMap.values.filter { !$0.isLocal },
                                calendars: calendars, events: events, listMarks: listMarks,
                                eventFrom: eventRange?.lowerBound, eventTo: eventRange?.upperBound)
        let url = Self.cacheURL
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadCache() {
        guard hasAccount,
              let data = try? Data(contentsOf: Self.cacheURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.email == accountKey
        else { return }
        lists = snapshot.lists
        listsChanged()
        taskMap = Dictionary(snapshot.tasks.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        calendars = snapshot.calendars
        events = snapshot.events
        listMarks = snapshot.listMarks
        if let from = snapshot.eventFrom, let to = snapshot.eventTo, from < to { eventRange = from..<to }
    }
}

struct ListMeta {
    var name: String
    var symbol: String?
    var color: Color
    var order: Int
}

/// Visões pré-calculadas das tarefas. Construída em O(n log n) só quando algo muda,
/// para que trocar de tela e redesenhar sejam instantâneos.
struct TaskIndex {
    var byID: [String: TaskItem] = [:]
    var active: [TaskItem] = []
    var activeCount = 0
    var today: [TaskItem] = []
    var overdue: [TaskItem] = []
    var later: [TaskItem] = []
    var undated: [TaskItem] = []
    var byDay: [Date: [TaskItem]] = [:]
    var byList: [String: [TaskItem]] = [:]
    var completed: [TaskItem] = []
    var completedToday: [TaskItem] = []
    var completedByList: [String: [TaskItem]] = [:]
    var completedByDay: [Date: [TaskItem]] = [:]
    /// Subtarefas (abertas e concluídas) de cada tarefa-mãe, na ordem do Google.
    var filhas: [String: [TaskItem]] = [:]

    init() {}

    init(map: [String: TaskItem], today: Date, listOrder: [String: Int]) {
        byID = map
        var open: [TaskItem] = []
        var done: [TaskItem] = []
        open.reserveCapacity(map.count)
        for task in map.values {
            if task.isCompleted { done.append(task) } else { open.append(task) }
            if let mae = task.parent { filhas[mae, default: []].append(task) }
        }
        for (mae, lista) in filhas {
            filhas[mae] = lista.sorted { ($0.position ?? "") < ($1.position ?? "") }
        }

        // Ordem: data, depois ordem das listas, depois posição dentro da lista.
        open.sort { a, b in
            let da = a.dueDay ?? .distantFuture, db = b.dueDay ?? .distantFuture
            if da != db { return da < db }
            if a.listID != b.listID { return (listOrder[a.listID] ?? .max) < (listOrder[b.listID] ?? .max) }
            return (a.position ?? "") < (b.position ?? "")
        }
        done.sort { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }

        active = open
        activeCount = open.count
        let tomorrow = Calendar.current.adding(days: 1, to: today)
        for task in open {
            byList[task.listID, default: []].append(task)
            guard let due = task.dueDay else {
                undated.append(task)
                continue
            }
            byDay[due, default: []].append(task)
            if due < today { overdue.append(task) } else if due < tomorrow { self.today.append(task) } else { later.append(task) }
        }
        completed = done
        for task in done {
            completedByList[task.listID, default: []].append(task)
            if let due = task.dueDay { completedByDay[due, default: []].append(task) }
            if let date = task.completedDate, date >= today, date < tomorrow { completedToday.append(task) }
        }
    }
}

struct IndentedTask: Identifiable {
    let task: TaskItem
    let depth: Int
    var id: String { task.id }
}

/// "Excluído — Desfazer". Roda a exclusão de verdade quando expira; nada se for desfeito.
@MainActor
struct AvisoSucesso: Identifiable, Equatable {
    let id = UUID()
    let singular: String
    let plural: String
    let icone: String
    var quantidade = 1

    var texto: String { quantidade == 1 ? singular : "\(quantidade) \(plural)" }
}

final class AvisoDesfazer: Identifiable {
    let id = UUID()
    let texto: String
    private var desfazerAcao: (() -> Void)?
    private var confirmarAcao: (() async -> Void)?

    init(texto: String, desfazer: @escaping () -> Void, confirmar: @escaping () async -> Void) {
        self.texto = texto
        desfazerAcao = desfazer
        confirmarAcao = confirmar
    }

    func cancelar() {
        desfazerAcao?()
        desfazerAcao = nil
        confirmarAcao = nil
    }

    func expirar() {
        guard let confirmar = confirmarAcao else { return }
        confirmarAcao = nil
        desfazerAcao = nil
        Task { await confirmar() }
    }
}
