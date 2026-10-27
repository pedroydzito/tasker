import Foundation

/// Onde o Tasker guarda os arquivos. Com `TASKER_HOME` (autoteste e capturas de tela),
/// tudo vai para essa pasta e as preferências para um domínio separado — nada toca nos dados reais.
enum Pastas {
    static let isolado = ProcessInfo.processInfo.environment["TASKER_HOME"]

    static let base: URL = {
        let dir = isolado.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Tasker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func pasta(_ nome: String) -> URL {
        let dir = base.appendingPathComponent(nome, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard isolado != nil else { return .standard }
        let nome = "tasker.isolado.\(ProcessInfo.processInfo.processIdentifier)"
        let d = UserDefaults(suiteName: nome) ?? .standard
        d.removePersistentDomain(forName: nome)
        return d
    }()
}
