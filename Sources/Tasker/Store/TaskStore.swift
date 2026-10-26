import AppKit
import Observation
import SwiftUI

/// Estado central: listas, tarefas e eventos sincronizados com o Google.
@MainActor @Observable
final class TaskStore {
    let auth: GoogleAuth
    let prefs: Preferences
    @ObservationIgnored private let api: GoogleAPI

    private(set) var lists: [TaskList] = []
    private(set) var tasks: [String: TaskItem] = [:]
    private(set) var calendars: [CalendarInfo] = []
    private(set) var events: [CalendarEvent] = []
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    var lastError: String?
    private(set) var today = Calendar.current.startOfDay(for: .now)
    private(set) var tagDB = TagDatabase.load()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var listMarks: [String: Date] = [:]
    @ObservationIgnored private var lastFullSync = Date.distantPast
    @ObservationIgnored private var lastEventSync = Date.distantPast
    @ObservationIgnored private var pendingIDs: Set<String> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(auth: GoogleAuth, api: GoogleAPI, prefs: Preferences) {
        self.auth = auth
        self.api = api
        self.prefs = prefs
    }

    // MARK: Consultas

    private var activeTasks: [TaskItem] { tasks.values.filter { !$0.isCompleted } }

    var todayTasks: [TaskItem] {
        activeTasks.filter { $0.dueDay == today }.sorted(by: order)
    }

    var overdueTasks: [TaskItem] {
        activeTasks.filter { ($0.dueDay ?? .distantFuture) < today }.sorted(by: order)
    }

    var completedToday: [TaskItem] {
        tasks.values
            .filter { $0.isCompleted && $0.completedDate.map { Calendar.current.isDate($0, inSameDayAs: today) } == true }
            .sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
    }

    /// Número exibido na barra de menu.
    var badgeCount: Int {
        let end = Calendar.current.adding(days: 1, to: today)
        return activeTasks.filter { task in
            guard let due = task.dueDay, due < end else { return false }
            return prefs.includeOverdueInCount || due >= today
        }.count
    }

    var completedTasks: [TaskItem] {
        tasks.values.filter(\.isCompleted).sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
    }

    var activeCount: Int { activeTasks.count }

    func tasks(on day: Date) -> [TaskItem] {
        activeTasks.filter { $0.dueDay == day }.sorted(by: order)
    }

    func tasks(inList listID: String) -> [TaskItem] {
        activeTasks.filter { $0.listID == listID }
    }

    var undatedTasks: [TaskItem] {
        activeTasks.filter { $0.due == nil }.sorted(by: order)
    }

    func events(on day: Date) -> [CalendarEvent] {
        events.filter { $0.overlaps(dayStart: day) }
    }

    func list(_ id: String) -> TaskList? { lists.first { $0.id == id } }

    var defaultList: TaskList? {
        prefs.defaultListID.flatMap(list) ?? lists.first
    }

    func color(forList id: String) -> Color {
        if let hex = prefs.listColors[id] { return Color(hex: hex) }
        let index = lists.firstIndex { $0.id == id } ?? abs(id.hashValue)
        return Color(hex: Palette.lists[index % Palette.lists.count])
    }

    func setColor(_ color: Color, forList id: String) {
        prefs.listColors[id] = color.hexString
    }

    func isVisible(_ calendar: CalendarInfo) -> Bool {
        prefs.calendarVisibility[calendar.id] ?? calendar.selectedInGoogle
    }

    func setVisible(_ visible: Bool, calendar: CalendarInfo) {
        prefs.calendarVisibility[calendar.id] = visible
        Task { await syncEvents(force: true) }
    }

    /// Ordem: data, depois ordem das listas, depois posição dentro da lista.
    private func order(_ a: TaskItem, _ b: TaskItem) -> Bool {
        let da = a.dueDay ?? .distantFuture, db = b.dueDay ?? .distantFuture
        if da != db { return da < db }
        if a.listID != b.listID {
            let ia = lists.firstIndex { $0.id == a.listID } ?? .max
            let ib = lists.firstIndex { $0.id == b.listID } ?? .max
            return ia < ib
        }
        return (a.position ?? "") < (b.position ?? "")
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
        if now != today { today = now }
    }

    func reset() {
        lists = []
        tasks = [:]
        calendars = []
        events = []
        listMarks = [:]
        lastSync = nil
        lastEventSync = .distantPast
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    // MARK: Sincronização

    func sync(force: Bool = false) async {
        guard auth.isSignedIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        refreshToday()

        do {
            let full = force || Date().timeIntervalSince(lastFullSync) > 15 * 60
            try await syncTasks(full: full)
            if full { lastFullSync = .now }
            if force || Date().timeIntervalSince(lastEventSync) > 90 {
                try await syncEventsNow()
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
        let remoteLists = try await api.fetchTaskLists()
        lists = remoteLists.map { TaskList(id: $0.id, title: $0.title ?? "Sem título") }
        let listIDs = Set(lists.map(\.id))
        tasks = tasks.filter { listIDs.contains($0.value.listID) }

        for list in lists {
            let started = Date()
            let since = full ? nil : listMarks[list.id]
            // Margem de 2 min para não perder alterações por diferença de relógio.
            let remote = try await api.fetchTasks(listID: list.id, updatedMin: since?.addingTimeInterval(-120))

            if since == nil {
                let remoteIDs = Set(remote.map(\.id))
                tasks = tasks.filter { _, task in
                    task.listID != list.id || remoteIDs.contains(task.id) || task.isLocal || pendingIDs.contains(task.id)
                }
            }
            for g in remote where !pendingIDs.contains(g.id) {
                if g.deleted == true {
                    tasks[g.id] = nil
                } else {
                    tasks[g.id] = TaskItem(g, listID: list.id)
                }
            }
            listMarks[list.id] = started
        }
    }

    func syncEvents(force: Bool = false) async {
        do {
            try await syncEventsNow()
            saveCache()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func syncEventsNow() async throws {
        let remote = try await api.fetchCalendars()
        calendars = remote
            .filter { $0.hidden != true }
            .map {
                CalendarInfo(id: $0.id, title: $0.summaryOverride ?? $0.summary ?? $0.id,
                             colorHex: $0.backgroundColor ?? "#4285F4", isPrimary: $0.primary == true,
                             selectedInGoogle: $0.selected == true || $0.primary == true)
            }
            .sorted { ($0.isPrimary ? 0 : 1, $0.title) < ($1.isPrimary ? 0 : 1, $1.title) }

        let from = Calendar.current.adding(days: -7, to: today)
        let to = Calendar.current.adding(days: 60, to: today)
        events = await loadEvents(from: from, to: to)
        lastEventSync = .now
    }

    /// Busca eventos de todos os calendários visíveis em um intervalo (usado também pela tela de calendário).
    func loadEvents(from: Date, to: Date) async -> [CalendarEvent] {
        var result: [CalendarEvent] = []
        for calendar in calendars where isVisible(calendar) {
            guard let items = try? await api.fetchEvents(calendarID: calendar.id, from: from, to: to) else { continue }
            result += items.compactMap { CalendarEvent($0, calendar: calendar) }
        }
        return result.sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// Move todas as tarefas atrasadas para hoje (botão "Adiar" do TickTick).
    func postponeOverdue() {
        for task in overdueTasks { setDue(task, today) }
    }

    // MARK: Etiquetas locais

    var tags: [Tag] { tagDB.tags }

    func tags(for task: TaskItem) -> [Tag] {
        let ids = tagDB.assignments[task.id] ?? []
        return tagDB.tags.filter { ids.contains($0.id) }
    }

    func tasks(withTag tagID: String) -> [TaskItem] {
        activeTasks.filter { tagDB.assignments[$0.id]?.contains(tagID) == true }.sorted(by: order)
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
        tagDB.tags.removeAll { $0.id == tag.id }
        for (taskID, ids) in tagDB.assignments {
            let remaining = ids.filter { $0 != tag.id }
            tagDB.assignments[taskID] = remaining.isEmpty ? nil : remaining
        }
        tagDB.save()
    }

    func toggleTag(_ tag: Tag, on task: TaskItem) {
        var ids = tagDB.assignments[task.id] ?? []
        if let index = ids.firstIndex(of: tag.id) { ids.remove(at: index) } else { ids.append(tag.id) }
        tagDB.assignments[task.id] = ids.isEmpty ? nil : ids
        tagDB.save()
    }

    // MARK: Alterações (otimistas)

    func addTask(title: String, listID: String? = nil, due: Date?, notes: String? = nil, tagIDs: [String] = []) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let listID = listID ?? defaultList?.id else { return }

        let tempID = "local-\(UUID().uuidString)"
        let dueString = due.map(TaskItem.dueString)
        tasks[tempID] = TaskItem(id: tempID, listID: listID, title: title, notes: notes, due: dueString, position: "")
        if !tagIDs.isEmpty { tagDB.assignments[tempID] = tagIDs }

        Task {
            do {
                let created = try await api.insertTask(listID: listID, title: title, notes: notes, due: dueString)
                tasks[tempID] = nil
                tasks[created.id] = TaskItem(created, listID: listID)
                if let tags = tagDB.assignments.removeValue(forKey: tempID) {
                    tagDB.assignments[created.id] = tags
                    tagDB.save()
                }
                saveCache()
            } catch {
                tasks[tempID] = nil
                tagDB.assignments[tempID] = nil
                lastError = "Não foi possível criar a tarefa: \(error.localizedDescription)"
            }
        }
    }

    func setCompleted(_ task: TaskItem, _ done: Bool) {
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

    func update(_ task: TaskItem, title: String, notes: String) {
        mutate(task, fields: ["title": title, "notes": notes]) {
            $0.title = title
            $0.notes = notes
        }
    }

    func delete(_ task: TaskItem) {
        guard !task.isLocal, let original = tasks[task.id] else { return }
        tasks[task.id] = nil
        pendingIDs.insert(task.id)
        Task {
            defer { pendingIDs.remove(task.id) }
            do {
                try await api.deleteTask(listID: task.listID, taskID: task.id)
                tagDB.assignments[task.id] = nil
                tagDB.save()
                saveCache()
            } catch {
                tasks[task.id] = original
                lastError = "Não foi possível excluir: \(error.localizedDescription)"
            }
        }
    }

    private func mutate(_ task: TaskItem, fields: [String: Any], local: (inout TaskItem) -> Void) {
        guard !task.isLocal else { return }
        let original = tasks[task.id] ?? task
        var updated = original
        local(&updated)
        tasks[task.id] = updated
        pendingIDs.insert(task.id)

        Task {
            defer { pendingIDs.remove(task.id) }
            do {
                let result = try await api.patchTask(listID: task.listID, taskID: task.id, fields: fields)
                tasks[result.id] = TaskItem(result, listID: task.listID)
                saveCache()
            } catch {
                tasks[task.id] = original
                lastError = "Não foi possível salvar: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Cache em disco (abre instantaneamente, mesmo offline)

    private struct Snapshot: Codable {
        var email: String?
        var lists: [TaskList]
        var tasks: [TaskItem]
        var calendars: [CalendarInfo]
        var events: [CalendarEvent]
        var listMarks: [String: Date]
    }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tasker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cache.json")
    }

    private func saveCache() {
        let snapshot = Snapshot(email: auth.profile?.email, lists: lists, tasks: tasks.values.filter { !$0.isLocal },
                                calendars: calendars, events: events, listMarks: listMarks)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    private func loadCache() {
        guard auth.isSignedIn,
              let data = try? Data(contentsOf: Self.cacheURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.email == auth.profile?.email
        else { return }
        lists = snapshot.lists
        tasks = Dictionary(snapshot.tasks.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        calendars = snapshot.calendars
        events = snapshot.events
        listMarks = snapshot.listMarks
    }
}

struct IndentedTask: Identifiable {
    let task: TaskItem
    let depth: Int
    var id: String { task.id }
}
