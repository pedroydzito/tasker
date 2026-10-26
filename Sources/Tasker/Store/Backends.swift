import Foundation

/// De onde vêm as tarefas: Google Tasks ou só este Mac. O store não sabe a diferença.
@MainActor
protocol TaskBackend: AnyObject {
    func fetchTaskLists() async throws -> [GTaskList]
    func fetchTasks(listID: String, updatedMin: Date?) async throws -> [GTask]
    func insertTask(listID: String, title: String, notes: String?, due: String?) async throws -> GTask
    func patchTask(listID: String, taskID: String, fields: [String: Any]) async throws -> GTask
    func deleteTask(listID: String, taskID: String) async throws
    func insertList(title: String) async throws -> GTaskList
    func renameList(id: String, title: String) async throws -> GTaskList
    func deleteList(id: String) async throws
}

extension GoogleAPI: TaskBackend {}

/// Tarefas guardadas só neste Mac (modo sem conta). Sem servidor: um arquivo JSON.
@MainActor
final class LocalBackend: TaskBackend {
    private struct Banco: Codable {
        var lists: [GTaskList] = []
        var tasks: [String: [GTask]] = [:] // listID → tarefas
    }

    private var banco: Banco

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tasker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("local.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let banco = try? JSONDecoder().decode(Banco.self, from: data) {
            self.banco = banco
        } else {
            banco = Banco(lists: [GTaskList(id: "local-inbox", title: "Minhas tarefas")], tasks: [:])
            salvar()
        }
    }

    private func salvar() {
        guard let data = try? JSONEncoder().encode(banco) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private static func agora() -> String { RFC3339.string(.now) }

    /// Posição que coloca a tarefa nova no topo (como o Google faz).
    private static func posicaoNoTopo() -> String {
        String(format: "%020d", Int64.max / 2 - Int64(Date().timeIntervalSince1970 * 1000))
    }

    func fetchTaskLists() async throws -> [GTaskList] { banco.lists }

    func fetchTasks(listID: String, updatedMin: Date?) async throws -> [GTask] {
        banco.tasks[listID] ?? []
    }

    func insertTask(listID: String, title: String, notes: String?, due: String?) async throws -> GTask {
        let task = GTask(id: "t-\(UUID().uuidString)", title: title, notes: notes, status: "needsAction", due: due,
                         completed: nil, updated: Self.agora(), parent: nil, position: Self.posicaoNoTopo(),
                         deleted: nil, hidden: nil, webViewLink: nil)
        banco.tasks[listID, default: []].append(task)
        salvar()
        return task
    }

    func patchTask(listID: String, taskID: String, fields: [String: Any]) async throws -> GTask {
        guard var tasks = banco.tasks[listID], let i = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw LocalError.naoEncontrado
        }
        var task = tasks[i]
        if let title = fields["title"] as? String { task.title = title }
        if let notes = fields["notes"] as? String { task.notes = notes }
        if fields.keys.contains("due") { task.due = fields["due"] as? String }
        if let status = fields["status"] as? String {
            task.status = status
            task.completed = status == "completed" ? Self.agora() : nil
        }
        task.updated = Self.agora()
        tasks[i] = task
        banco.tasks[listID] = tasks
        salvar()
        return task
    }

    func deleteTask(listID: String, taskID: String) async throws {
        banco.tasks[listID]?.removeAll { $0.id == taskID }
        salvar()
    }

    func insertList(title: String) async throws -> GTaskList {
        let list = GTaskList(id: "l-\(UUID().uuidString)", title: title)
        banco.lists.append(list)
        salvar()
        return list
    }

    func renameList(id: String, title: String) async throws -> GTaskList {
        guard let i = banco.lists.firstIndex(where: { $0.id == id }) else { throw LocalError.naoEncontrado }
        banco.lists[i].title = title
        salvar()
        return banco.lists[i]
    }

    func deleteList(id: String) async throws {
        banco.lists.removeAll { $0.id == id }
        banco.tasks[id] = nil
        salvar()
    }

    enum LocalError: LocalizedError {
        case naoEncontrado
        var errorDescription: String? { "Item não encontrado." }
    }
}
