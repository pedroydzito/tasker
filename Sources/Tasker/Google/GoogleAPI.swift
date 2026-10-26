import Foundation

struct APIError: LocalizedError {
    let status: Int
    let body: String

    private struct Body: Decodable {
        struct Detail: Decodable {
            let reason: String?
            let metadata: [String: String]?
        }
        struct Item: Decodable {
            let reason: String?
        }
        struct Inner: Decodable {
            let message: String?
            let details: [Detail]?
            let errors: [Item]?
        }
        let error: Inner
    }

    private var parsed: Body? { try? JSONDecoder().decode(Body.self, from: Data(body.utf8)) }

    private var reasons: [String] {
        (parsed?.error.details?.compactMap(\.reason) ?? []) + (parsed?.error.errors?.compactMap(\.reason) ?? [])
    }

    /// A API não foi ativada no projeto do Google Cloud.
    var isServiceDisabled: Bool {
        reasons.contains("SERVICE_DISABLED") || reasons.contains("accessNotConfigured") || body.contains("has not been used in project")
    }

    /// O usuário desmarcou essa permissão na tela de login do Google.
    var isScopeInsufficient: Bool {
        reasons.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") || reasons.contains("insufficientPermissions")
    }

    var serviceTitle: String? {
        parsed?.error.details?.compactMap { $0.metadata?["serviceTitle"] }.first
    }

    /// Link direto para ativar a API no Console.
    var activationURL: URL? {
        if let url = parsed?.error.details?.compactMap({ $0.metadata?["activationUrl"] }).first { return URL(string: url) }
        guard let start = body.range(of: "https://console.developers.google.com/apis/api/") else { return nil }
        let tail = body[start.lowerBound...]
        let end = tail.firstIndex { $0 == " " || $0 == "\"" || $0 == "\n" } ?? tail.endIndex
        return URL(string: String(tail[..<end]))
    }

    var errorDescription: String? {
        if isServiceDisabled {
            return "A \(serviceTitle ?? "API do Google") não está ativada no seu projeto do Google Cloud."
        }
        if isScopeInsufficient {
            return "O Tasker não recebeu todas as permissões. Entre de novo e marque todas as caixas na tela do Google."
        }
        if status == 403 { return "Acesso negado pelo Google (403): \(parsed?.error.message ?? "sem detalhes")" }
        if status == 429 { return "Muitas requisições ao Google. Tentando de novo em instantes." }
        return "Erro do Google (\(status)): \(parsed?.error.message ?? "")"
    }
}

/// Cliente HTTP das APIs Google Tasks e Google Calendar.
@MainActor
final class GoogleAPI {
    private let auth: GoogleAuth
    private let session: URLSession

    init(auth: GoogleAuth) {
        self.auth = auth
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    // MARK: Infra

    @discardableResult
    func send(_ method: String, _ url: URL, json: [String: Any]? = nil) async throws -> Data {
        var retried = false
        while true {
            let token = try await auth.validAccessToken()
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let json {
                request.httpBody = try JSONSerialization.data(withJSONObject: json)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, !retried {
                retried = true
                auth.invalidateAccessToken()
                continue
            }
            guard (200..<300).contains(status) else {
                throw APIError(status: status, body: String(decoding: data, as: UTF8.self))
            }
            return data
        }
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await send("GET", url))
    }

    private func paginate<R: PagedResponse>(_ type: R.Type, _ makeURL: (String?) -> URL) async throws -> [R.Item] {
        var all: [R.Item] = []
        var pageToken: String?
        repeat {
            let page: R = try await get(makeURL(pageToken))
            all += page.items ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    private static func url(_ base: String, _ path: [String], _ query: [String: String?] = [:]) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~@"))
        let encodedPath = path.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
        var components = URLComponents(string: "\(base)/\(encodedPath)")!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        return components.url!
    }

    // MARK: Google Tasks

    private static let tasksBase = "https://tasks.googleapis.com/tasks/v1"

    func fetchTaskLists() async throws -> [GTaskList] {
        try await paginate(GTaskListsResponse.self) { token in
            Self.url(Self.tasksBase, ["users", "@me", "lists"], ["maxResults": "100", "pageToken": token])
        }
    }

    /// Com `updatedMin` traz só o que mudou (incluindo tarefas apagadas).
    func fetchTasks(listID: String, updatedMin: Date?) async throws -> [GTask] {
        try await paginate(GTasksResponse.self) { token in
            Self.url(Self.tasksBase, ["lists", listID, "tasks"], [
                "maxResults": "100",
                "showCompleted": "true",
                "showHidden": "true",
                "showDeleted": updatedMin == nil ? "false" : "true",
                "updatedMin": updatedMin.map(RFC3339.string),
                "pageToken": token,
            ])
        }
    }

    func insertTask(listID: String, title: String, notes: String?, due: String?) async throws -> GTask {
        var body: [String: Any] = ["title": title]
        if let notes, !notes.isEmpty { body["notes"] = notes }
        if let due { body["due"] = due }
        let data = try await send("POST", Self.url(Self.tasksBase, ["lists", listID, "tasks"]), json: body)
        return try JSONDecoder().decode(GTask.self, from: data)
    }

    func patchTask(listID: String, taskID: String, fields: [String: Any]) async throws -> GTask {
        let data = try await send("PATCH", Self.url(Self.tasksBase, ["lists", listID, "tasks", taskID]), json: fields)
        return try JSONDecoder().decode(GTask.self, from: data)
    }

    func deleteTask(listID: String, taskID: String) async throws {
        try await send("DELETE", Self.url(Self.tasksBase, ["lists", listID, "tasks", taskID]))
    }

    func insertList(title: String) async throws -> GTaskList {
        let data = try await send("POST", Self.url(Self.tasksBase, ["users", "@me", "lists"]), json: ["title": title])
        return try JSONDecoder().decode(GTaskList.self, from: data)
    }

    func renameList(id: String, title: String) async throws -> GTaskList {
        let data = try await send("PATCH", Self.url(Self.tasksBase, ["users", "@me", "lists", id]), json: ["title": title])
        return try JSONDecoder().decode(GTaskList.self, from: data)
    }

    func deleteList(id: String) async throws {
        try await send("DELETE", Self.url(Self.tasksBase, ["users", "@me", "lists", id]))
    }

    // MARK: Google Calendar

    private static let calendarBase = "https://www.googleapis.com/calendar/v3"

    func fetchCalendars() async throws -> [GCalendar] {
        try await paginate(GCalendarListResponse.self) { token in
            Self.url(Self.calendarBase, ["users", "me", "calendarList"], ["maxResults": "250", "pageToken": token])
        }
    }

    func fetchEvents(calendarID: String, from: Date, to: Date) async throws -> [GEvent] {
        try await paginate(GEventsResponse.self) { token in
            Self.url(Self.calendarBase, ["calendars", calendarID, "events"], [
                "timeMin": RFC3339.string(from),
                "timeMax": RFC3339.string(to),
                "singleEvents": "true",
                "orderBy": "startTime",
                "maxResults": "250",
                "pageToken": token,
            ])
        }
    }
}
