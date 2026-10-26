import Foundation
import Network

/// Servidor HTTP mínimo em 127.0.0.1 que recebe o redirect do OAuth do Google.
final class LoopbackServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "tasker.oauth.loopback")
    private var continuation: CheckedContinuation<URL, Error>?
    private var receivedURL: URL?

    init() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }

    /// Começa a escutar e devolve a porta escolhida pelo sistema.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = self?.listener.port?.rawValue ?? 0
                    once.run { cont.resume(returning: port) }
                case .failed(let error):
                    once.run { cont.resume(throwing: error) }
                case .cancelled:
                    once.run { cont.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: queue)
        }
    }

    /// Aguarda o navegador voltar com `?code=...`.
    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                if let url = self.receivedURL {
                    cont.resume(returning: url)
                } else {
                    self.continuation = cont
                }
            }
        }
    }

    func stop() {
        listener.cancel()
        queue.async {
            self.continuation?.resume(throwing: CancellationError())
            self.continuation = nil
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, _, _ in
            guard let self,
                  let data, let text = String(data: data, encoding: .utf8),
                  let requestLine = text.components(separatedBy: "\r\n").first
            else { conn.cancel(); return }

            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2, let url = URL(string: "http://127.0.0.1\(parts[1])"), url.path != "/favicon.ico" else {
                self.respond(conn, status: "404 Not Found", html: "")
                return
            }

            self.respond(conn, status: "200 OK", html: Self.successPage)
            if let cont = self.continuation {
                self.continuation = nil
                cont.resume(returning: url)
            } else {
                self.receivedURL = url
            }
        }
    }

    private func respond(_ conn: NWConnection, status: String, html: String) {
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static let successPage = """
    <!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Tasker</title>
    <body style="font-family:-apple-system,system-ui;display:grid;place-items:center;height:100vh;margin:0;background:#f6f7f9;color:#1d1d1f">
    <div style="text-align:center"><div style="font-size:48px">✓</div>
    <h2 style="margin:8px 0">Tasker conectado</h2><p style="color:#6e6e73">Pode fechar esta aba e voltar para o app.</p></div>
    </body></html>
    """
}

/// Executa um bloco no máximo uma vez (os callbacks do listener chegam na mesma fila serial).
private final class Once: @unchecked Sendable {
    private var done = false
    func run(_ block: () -> Void) {
        guard !done else { return }
        done = true
        block()
    }
}
