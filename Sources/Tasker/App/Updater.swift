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

    func start() {
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
                  let url = URL(string: asset.browser_download_url)
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
        let work = fm.temporaryDirectory.appendingPathComponent("tasker-update-\(release.build)", isDirectory: true)
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
        try? await Self.run("/usr/bin/xattr", ["-cr", newApp.path])

        // Um script separado espera o app fechar, troca o bundle e abre a versão nova.
        let target = Bundle.main.bundleURL
        let script = work.appendingPathComponent("install.sh")
        try """
        #!/bin/sh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(target.path)"
        mv "\(newApp.path)" "\(target.path)"
        open "\(target.path)"
        rm -rf "\(work.path)"
        """.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        try process.run()

        NSApp.terminate(nil)
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
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                Text("Nova versão \(release.version) disponível").font(.system(size: 12.5, weight: .medium))
                Spacer()
                Button("Atualizar") { updater.installAvailableUpdate() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Atualizando… o Tasker vai reiniciar").font(.system(size: 12.5))
                Spacer()
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        default:
            EmptyView()
        }
    }
}
