import Foundation

/// Guarda tokens e o client secret num arquivo legível só pelo seu usuário (permissão 600).
/// Não usamos o Keychain porque cada atualização automática muda a assinatura do app
/// e o macOS passaria a pedir a senha a cada nova versão.
enum SecretStore {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tasker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("secrets.json")
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }

    static func get(_ key: String) -> String? {
        load()[key]
    }

    static func set(_ value: String?, for key: String) {
        var values = load()
        values[key] = (value?.isEmpty ?? true) ? nil : value
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
