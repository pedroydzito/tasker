import AppKit
import Observation
import SwiftUI
import UserNotifications

/// Atualização automática via GitHub Releases.
/// Cada push gera um release "v0.1.<build>" com o Tasker.zip; o app compara com o próprio
/// número de build, avisa por notificação e, ao confirmar, troca o app e reinicia.
@MainActor @Observable
final class Updater: NSObject {
    struct Release: Equatable {
        let version: String
        let build: Int
        let notes: String
        let downloadURL: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate
        case available(Release)
        case installing
        case failed(String)
        /// A troca do app não aconteceu (ex.: macOS bloqueou). Guarda o app novo para instalar à mão.
        case installFailed(version: String, newApp: URL?, log: String)
    }

    static let repository = "pedroydzito/tasker"
    private static let assetName = "Tasker.zip"
    private static let notificationCategory = "TASKER_UPDATE"
    private static let updateAction = "UPDATE"

    private(set) var state: State = .idle
    private(set) var lastCheck: Date?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var notifiedBuild: Int?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    var availableRelease: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    private static let pendingBuildKey = "update.pendingBuild"
    private static let pendingVersionKey = "update.pendingVersion"

    private static var updateDir: URL {
        let dir = Pastas.pasta("Update")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var logURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Tasker-update.log")
    }

    /// Ao abrir, confere se a última atualização realmente trocou o app.
    private func verifyPendingUpdate() {
        let defaults = UserDefaults.standard
        let pending = defaults.integer(forKey: Self.pendingBuildKey)
        guard pending > 0 else { return }
        let version = defaults.string(forKey: Self.pendingVersionKey) ?? "\(pending)"
        defaults.removeObject(forKey: Self.pendingBuildKey)
        defaults.removeObject(forKey: Self.pendingVersionKey)

        if currentBuild >= pending {
            try? FileManager.default.removeItem(at: Self.updateDir)
            return
        }
        let log = (try? String(contentsOf: Self.logURL, encoding: .utf8)) ?? ""
        let newApp = Self.updateDir.appendingPathComponent("Tasker.app")
        state = .installFailed(version: version,
                               newApp: FileManager.default.fileExists(atPath: newApp.path) ? newApp : nil,
                               log: String(log.suffix(1500)))
        notifiedBuild = pending // não insiste com a mesma versão em loop
    }

    func start() {
        verifyPendingUpdate()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let update = UNNotificationAction(identifier: Self.updateAction, title: "Atualizar", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.notificationCategory, actions: [update], intentIdentifiers: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    // MARK: Verificação

    func check(userInitiated: Bool = false) async {
        if case .installing = state { return }
        if case .installFailed = state, !userInitiated { return }
        if userInitiated { state = .checking }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                state = userInitiated ? .upToDate : state
                lastCheck = .now
                return
            }
            let latest = try JSONDecoder().decode(GitHubRelease.self, from: data)
            lastCheck = .now

            guard let build = Self.build(fromTag: latest.tag_name),
                  let asset = latest.assets.first(where: { $0.name == Self.assetName }),
                  let url = URL(string: asset.browser_download_url),
                  // Só baixa de release deste repositório no GitHub, por HTTPS.
                  url.scheme == "https", url.host == "github.com",
                  url.path.hasPrefix("/\(Self.repository)/releases/download/")
            else {
                if userInitiated { state = .upToDate }
                return
            }

            // Build 0 = compilado localmente; nunca se sobrescreve sozinho.
            guard currentBuild > 0, build > currentBuild else {
                state = .upToDate
                return
            }

            let release = Release(version: String(latest.tag_name.drop { $0 == "v" }), build: build,
                                  notes: latest.body ?? "", downloadURL: url)
            state = .available(release)
            if notifiedBuild != build {
                notifiedBuild = build
                notify(release)
            }
        } catch {
            if userInitiated { state = .failed("Não foi possível verificar: \(error.localizedDescription)") }
        }
    }

    /// "v0.1.42" → 42
    private static func build(fromTag tag: String) -> Int? {
        tag.split(separator: ".").last.flatMap { Int($0) }
    }

    private func notify(_ release: Release) {
        let content = UNMutableNotificationContent()
        content.title = "Atualização do Tasker disponível"
        content.body = "Versão \(release.version) pronta para instalar. Clique em Atualizar."
        content.categoryIdentifier = Self.notificationCategory
        let request = UNNotificationRequest(identifier: "update-\(release.build)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Instalação

    func installAvailableUpdate() {
        guard let release = availableRelease else { return }
        state = .installing
        Task {
            do {
                try await install(release)
            } catch {
                state = .failed("Falha ao atualizar: \(error.localizedDescription)")
            }
        }
    }

    private func install(_ release: Release) async throws {
        let fm = FileManager.default
        let work = Self.updateDir
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let (downloaded, response) = try await URLSession.shared.download(from: release.downloadURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
        let zip = work.appendingPathComponent(Self.assetName)
        try fm.moveItem(at: downloaded, to: zip)

        try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let newApp = work.appendingPathComponent("Tasker.app")
        guard fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/Tasker").path) else {
            throw UpdateError.invalidPackage
        }
        // Confere que o pacote é mesmo o Tasker antes de tirar a quarentena.
        guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier
        else { throw UpdateError.invalidPackage }
        try? await Self.run("/usr/bin/xattr", ["-cr", newApp.path])

        // Script separado: espera o app fechar, guarda o antigo, move o novo e reabre.
        // Se qualquer passo falhar, restaura o antigo. Tudo vai para o log.
        let target = Bundle.main.bundleURL.path
        let backup = target + ".old"
        let log = Self.logURL.path
        try? fm.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = work.appendingPathComponent("install.sh")
        try """
        #!/bin/sh
        exec >> "\(log)" 2>&1
        echo "=== $(date) atualizando para \(release.version)"
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        set -x
        rm -rf "\(backup)"
        if mv "\(target)" "\(backup)"; then
            if ditto "\(newApp.path)" "\(target)"; then
                rm -rf "\(backup)"
                echo "OK"
            else
                echo "FALHA ao copiar o app novo; restaurando o antigo"
                rm -rf "\(target)"
                mv "\(backup)" "\(target)"
            fi
        else
            echo "FALHA ao mover o app atual (provável bloqueio do macOS: Gerenciamento de Apps)"
        fi
        open "\(target)"
        """.write(to: script, atomically: true, encoding: .utf8)

        UserDefaults.standard.set(release.build, forKey: Self.pendingBuildKey)
        UserDefaults.standard.set(release.version, forKey: Self.pendingVersionKey)

        // Desacoplado do processo do app, para sobreviver ao encerramento.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "nohup /bin/sh \"\(script.path)\" >/dev/null 2>&1 &"]
        try process.run()
        process.waitUntilExit()

        NSApp.terminate(nil)
    }

    /// Ajustes do Sistema → Privacidade e Segurança → Gerenciamento de Apps.
    func openAppManagementSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AppBundles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    func revealNewApp(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func dismissFailure() {
        state = .idle
    }

    private static func run(_ tool: String, _ args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = args
            process.terminationHandler = { p in
                if p.terminationStatus == 0 { cont.resume() } else { cont.resume(throwing: UpdateError.tool(tool)) }
            }
            do { try process.run() } catch { cont.resume(throwing: error) }
        }
    }

    enum UpdateError: LocalizedError {
        case download, invalidPackage
        case tool(String)

        var errorDescription: String? {
            switch self {
            case .download: "download falhou"
            case .invalidPackage: "pacote inválido"
            case .tool(let name): "\(name) falhou"
            }
        }
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }

        let tag_name: String
        let body: String?
        let assets: [Asset]
    }
}

extension Updater: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == "TASKER_UPDATE" else { return }
        await MainActor.run { self.installAvailableUpdate() }
    }
}

/// Faixa "Atualização disponível" usada no popover e nos Ajustes.

struct UpdateBanner: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        switch updater.state {
        case .available(let release):
            Nota(tom: .info, texto: "A versão \(release.version) está pronta para instalar.") {
                HStack {
                    Spacer()
                    Button("Atualizar agora") { updater.installAvailableUpdate() }.buttonStyle(.primario)
                }
            }
        case .installing:
            HStack(spacing: DS.e2) {
                ProgressView().controlSize(.small)
                Text("Atualizando — o Tasker vai reiniciar.").txt(.xs).foregroundStyle(DS.texto2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, DS.e3)
            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
        case .installFailed(let version, let newApp, _):
            Nota(tom: .aviso, texto: "A atualização para \(version) não foi aplicada: o macOS bloqueou a troca do app. Libere o Tasker em Ajustes do Sistema → Privacidade e Segurança → Gerenciamento de Apps e tente de novo, ou instale à mão.") {
                HStack(spacing: DS.e2) {
                    Button("Abrir Ajustes") { updater.openAppManagementSettings() }.buttonStyle(.superficie)
                    if let newApp {
                        Button("Instalar à mão") { updater.revealNewApp(newApp) }.buttonStyle(.superficie)
                    }
                    Spacer()
                    Button("Tentar de novo") {
                        Task { await updater.check(userInitiated: true); updater.installAvailableUpdate() }
                    }
                    .buttonStyle(.primario)
                }
            }
        default:
            EmptyView()
        }
    }
}
