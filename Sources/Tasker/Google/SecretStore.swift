import Foundation

/// Guarda tokens e o client secret num arquivo legível só pelo seu usuário (permissão 600).
/// Não usamos o Keychain porque cada atualização automática muda a assinatura do app
/// e o macOS passaria a pedir a senha a cada nova versão.
enum SecretStore {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tasker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A pasta pode ter sido criada antes por outra parte do app com permissão aberta.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir.appendingPathComponent("secrets.json")
    }

    /// Em memória depois da primeira leitura (o arquivo só muda por aqui).
    @MainActor private static var cache: [String: String]?

    @MainActor private static func load() -> [String: String] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        cache = values
        return values
    }

    @MainActor static func get(_ key: String) -> String? {
        load()[key]
    }

    @MainActor static func set(_ value: String?, for key: String) {
        var values = load()
        values[key] = (value?.isEmpty ?? true) ? nil : value
        cache = values
        guard let data = try? JSONEncoder().encode(values) else { return }
        // Cria o arquivo temporário já com 600 e troca de uma vez: nunca existe uma cópia legível por outros.
        let destino = fileURL
        let temp = destino.deletingLastPathComponent().appendingPathComponent(".secrets-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temp.path, contents: data,
                                            attributes: [.posixPermissions: 0o600]) else { return }
        if rename(temp.path, destino.path) != 0 { try? FileManager.default.removeItem(at: temp) }
    }
}
