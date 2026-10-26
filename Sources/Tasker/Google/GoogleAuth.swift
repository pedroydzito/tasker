import AppKit
import CryptoKit
import Foundation
import Observation

enum AuthError: LocalizedError {
    case missingCredentials, notSignedIn, invalidCallback, noRefreshToken, revoked
    case denied(String)
    case tokenFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: "Preencha o Client ID e o Client Secret do Google Cloud."
        case .notSignedIn: "Você não está conectado ao Google."
        case .invalidCallback: "Resposta inválida do Google. Tente novamente."
        case .noRefreshToken: "O Google não devolveu um refresh token. Remova o acesso do Tasker em myaccount.google.com/permissions e tente de novo."
        case .revoked: "O acesso ao Google expirou ou foi revogado. Entre novamente."
        case .denied(let reason): "Login cancelado (\(reason))."
        case .tokenFailed(let body): "Falha ao obter token do Google: \(body)"
        }
    }
}

/// OAuth 2.0 para apps instalados (loopback + PKCE), com refresh automático.
@MainActor @Observable
final class GoogleAuth {
    struct Profile: Codable, Equatable {
        var name: String?
        var email: String?
        var picture: String?
    }

    static let scopes = [
        "openid", "email", "profile",
        "https://www.googleapis.com/auth/tasks",
        "https://www.googleapis.com/auth/calendar.readonly",
    ]

    private enum Keys {
        static let clientID = "google.clientID"
        static let clientSecret = "google.clientSecret"
        static let refreshToken = "google.refreshToken"
        static let profile = "google.profile"
    }

    private(set) var clientID: String
    private(set) var clientSecret: String
    private(set) var profile: Profile?
    private(set) var refreshToken: String?
    private(set) var isSigningIn = false

    var isSignedIn: Bool { refreshToken != nil }
    var hasCredentials: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessTokenExpiry = Date.distantPast
    @ObservationIgnored private var refreshTask: Task<String, Error>?
    @ObservationIgnored private var loopback: LoopbackServer?

    init() {
        clientID = UserDefaults.standard.string(forKey: Keys.clientID) ?? ""
        clientSecret = SecretStore.get(Keys.clientSecret) ?? ""
        refreshToken = SecretStore.get(Keys.refreshToken)
        if let data = UserDefaults.standard.data(forKey: Keys.profile) {
            profile = try? JSONDecoder().decode(Profile.self, from: data)
        }
    }

    func saveCredentials(clientID: String, clientSecret: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.clientID, forKey: Keys.clientID)
        SecretStore.set(self.clientSecret, for: Keys.clientSecret)
    }

    // MARK: Login

    func signIn() async throws {
        guard hasCredentials else { throw AuthError.missingCredentials }
        isSigningIn = true
        defer {
            isSigningIn = false
            loopback?.stop()
            loopback = nil
        }

        let server = try LoopbackServer()
        loopback = server
        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)"
        let verifier = PKCE.verifier()
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: state),
        ]
        NSWorkspace.shared.open(components.url!)

        let callback = try await server.waitForCallback()
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") { throw AuthError.denied(error) }
        guard value("state") == state, let code = value("code") else { throw AuthError.invalidCallback }

        let token = try await tokenRequest([
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        guard let refresh = token.refresh_token else { throw AuthError.noRefreshToken }

        SecretStore.set(refresh, for: Keys.refreshToken)
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(token.expires_in ?? 3600)
        refreshToken = refresh
        try? await loadProfile()
        NSApp.activate()
    }

    func cancelSignIn() {
        loopback?.stop()
    }

    func signOut() {
        if let token = refreshToken {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke?token=\(token)")!)
            request.httpMethod = "POST"
            URLSession.shared.dataTask(with: request).resume()
        }
        SecretStore.set(nil, for: Keys.refreshToken)
        UserDefaults.standard.removeObject(forKey: Keys.profile)
        refreshToken = nil
        accessToken = nil
        accessTokenExpiry = .distantPast
        profile = nil
    }

    // MARK: Tokens

    func validAccessToken() async throws -> String {
        if let accessToken, accessTokenExpiry > Date().addingTimeInterval(60) { return accessToken }
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken else { throw AuthError.notSignedIn }

        let task = Task { () throws -> String in
            let token = try await self.tokenRequest([
                "client_id": self.clientID,
                "client_secret": self.clientSecret,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token",
            ])
            self.accessToken = token.access_token
            self.accessTokenExpiry = Date().addingTimeInterval(token.expires_in ?? 3600)
            return token.access_token
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch AuthError.revoked {
            signOut()
            throw AuthError.revoked
        }
    }

    func invalidateAccessToken() {
        accessToken = nil
    }

    func loadProfile() async throws {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        let token = try await validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let profile = try JSONDecoder().decode(Profile.self, from: data)
        self.profile = profile
        UserDefaults.standard.set(try? JSONEncoder().encode(profile), forKey: Keys.profile)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double?
        let refresh_token: String?
    }

    private func tokenRequest(_ params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(decoding: data, as: UTF8.self)
            if body.contains("invalid_grant") { throw AuthError.revoked }
            throw AuthError.tokenFailed(body)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
