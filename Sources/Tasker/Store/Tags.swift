import Foundation

/// Etiqueta local: vive só no Tasker, não é enviada ao Google Tasks.
struct Tag: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var colorHex: String
}

/// Persistência das etiquetas e de quais tarefas as usam (por ID da tarefa no Google).
struct TagDatabase: Codable {
    var tags: [Tag] = []
    var assignments: [String: [String]] = [:] // taskID → [tagID]
    /// Horário da tarefa ("HH:mm"). O Google Tasks só guarda a data, então o horário fica no app.
    var horarios: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tags = try c.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        assignments = try c.decodeIfPresent([String: [String]].self, forKey: .assignments) ?? [:]
        horarios = try c.decodeIfPresent([String: String].self, forKey: .horarios) ?? [:]
    }

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tasker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tags.json")
    }

    static func load() -> TagDatabase {
        guard let data = try? Data(contentsOf: fileURL),
              let db = try? JSONDecoder().decode(TagDatabase.self, from: data) else { return TagDatabase() }
        return db
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
