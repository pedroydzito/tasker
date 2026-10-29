import AppKit
import AuthenticationServices
import SwiftUI
import WebKit

/// A interface do Tasker é a mesma da web: o build de `web/` vai dentro do app (Contents/Resources/web)
/// e é servido por um esquema próprio (`tasker-app://app/`), sem servidor e sem internet.
/// O app nativo fica com o que só ele faz: o ícone na barra de menus (número de hoje e cronômetro),
/// o ⌥Espaço e o login do Google (o Google não deixa entrar por dentro de uma WebView).
@MainActor
@Observable
final class WebPonte: NSObject {
    static let shared = WebPonte()
    static let esquema = "tasker-app"

    /// Pasta do build web dentro do app; nil se o app foi montado sem ele (aí fica a interface nativa antiga).
    static var pasta: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("web"),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("index.html").path) else { return nil }
        return url
    }
    static var disponivel: Bool { pasta != nil }

    /// O que a web informa para a barra de menus.
    var contagemHoje = 0
    /// Estado da web: "carregando", "entrar", "local" ou "conta".
    var modo = "carregando"
    var cronometroInicio: Date?
    var cronometroAntes: Double = 0
    var tique = Date()

    @ObservationIgnored private var webViews: [WeakWebView] = []
    /// A WebView da janela grande (para onde vão "abrir em tela grande" e ⌥Espaço).
    @ObservationIgnored weak var janela: WKWebView?
    /// Rota e tarefa pedidas antes de a janela existir.
    @ObservationIgnored private var pedidoDaJanela: (rota: String, tarefa: String?)?
    @ObservationIgnored private var sessaoLogin: ASWebAuthenticationSession?
    @ObservationIgnored private var relogio: Timer?
    @ObservationIgnored private let esquemaHandler = EsquemaLocal()

    private struct WeakWebView { weak var view: WKWebView? }

    func novaWebView(rota: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Mesmo armazenamento para a janela e o menu: IndexedDB e localStorage são um só.
        config.websiteDataStore = .default()
        config.setURLSchemeHandler(esquemaHandler, forURLScheme: Self.esquema)
        config.userContentController.add(MensagemFraca(self), name: "tasker")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsBackForwardNavigationGestures = false
        if let url = URL(string: "\(Self.esquema)://app/index.html#/\(rota)") {
            view.load(URLRequest(url: url))
        }
        webViews.removeAll { $0.view == nil }
        webViews.append(WeakWebView(view: view))
        return view
    }

    /// Outra janela mexeu nos dados: as demais releem o espelho local.
    func recarregarOutras(que nao: WKWebView?) {
        for w in webViews where w.view !== nao { w.view?.evaluateJavaScript("window.taskerRecarregar && taskerRecarregar()") }
    }

    func executar(_ js: String, em view: WKWebView? = nil) {
        if let view { view.evaluateJavaScript(js); return }
        for w in webViews { w.view?.evaluateJavaScript(js) }
    }

    fileprivate func receber(_ corpo: Any, de view: WKWebView?) {
        guard let m = corpo as? [String: Any], let acao = m["acao"] as? String else { return }
        switch acao {
        case "estado":
            contagemHoje = m["hoje"] as? Int ?? 0
            if let novo = m["modo"] as? String { modo = novo }
            if let c = m["cronometro"] as? [String: Any], let inicio = c["inicio"] as? String {
                cronometroInicio = ISO8601DateFormatter.comFracao.date(from: inicio) ?? ISO8601DateFormatter().date(from: inicio)
                cronometroAntes = c["segundosAntes"] as? Double ?? 0
            } else {
                cronometroInicio = nil
            }
            atualizarRelogio()
            if let modo = m["modo"] as? String { migrarSePreciso(modo: modo, view: view) }
        case "mudou":
            recarregarOutras(que: view)
        case "login":
            if let s = m["url"] as? String, let url = URL(string: s) { entrar(url: url, view: view) }
        case "abrirJanela":
            abrirJanela(rota: m["rota"] as? String ?? "#/hoje", tarefa: m["tarefa"] as? String)
        case "atualizar":
            AppModel.shared.updater.installAvailableUpdate()
        case "procurarAtualizacao":
            Task { await AppModel.shared.updater.check(userInitiated: true) }
        case "abrirAjustesDoSistema":
            AppModel.shared.updater.openAppManagementSettings()
        case "encerrar":
            NSApp.terminate(nil)
        case "abrirLink":
            if let s = m["url"] as? String, let url = URL(string: s) { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    // MARK: Atualização (o Updater nativo continua; a web mostra o aviso e o botão)

    @ObservationIgnored private var ultimaAtualizacao = ""

    /// Conta à web o estado do atualizador (versão atual e se há versão nova).
    func publicarAtualizacao() {
        let u = AppModel.shared.updater
        var estado = "nada", versao = "", erro = ""
        switch u.state {
        case .available(let r): estado = "disponivel"; versao = r.version
        case .installing: estado = "instalando"
        case .installFailed(let v, _, _): estado = "falhou"; versao = v
        case .checking: estado = "procurando"
        case .upToDate: estado = "emDia"
        case .failed(let m): estado = "erro"; erro = m
        default: break
        }
        let dados: [String: Any] = ["atual": u.currentVersion, "estado": estado, "versao": versao, "erro": erro]
        guard let data = try? JSONSerialization.data(withJSONObject: dados) else { return }
        let json = String(decoding: data, as: UTF8.self)
        if json == ultimaAtualizacao { return }
        ultimaAtualizacao = json
        executar("window.taskerAtualizacao && taskerAtualizacao(\(json))")
    }

    /// Uma vez por segundo é barato e não perde nenhuma mudança do atualizador.
    func vigiarAtualizacao() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { WebPonte.shared.publicarAtualizacao() }
        }
    }

    /// O menu abriu: sem conta, quem aparece é a janela grande (é lá que se entra) e o menu fecha.
    func menuAbriu() {
        executar("window.taskerMenuAbriu && taskerMenuAbriu()")
        guard modo == "entrar" else { return }
        DispatchQueue.main.async {
            for janela in NSApp.windows where String(describing: type(of: janela)).contains("MenuBarExtra") { janela.orderOut(nil) }
            self.abrirJanela(rota: "#/hoje")
        }
    }

    /// Abre a janela grande já numa tela (e numa tarefa, se pedida).
    func abrirJanela(rota: String, tarefa: String? = nil) {
        AppDelegate.abrirJanelaWeb()
        if let janela {
            ir(janela, rota: rota, tarefa: tarefa)
        } else {
            pedidoDaJanela = (rota, tarefa)
        }
    }

    /// Cria a WebView da janela grande já na rota pedida (se houve pedido antes de ela existir).
    func novaJanela() -> WKWebView {
        let pedido = pedidoDaJanela
        pedidoDaJanela = nil
        let rota = pedido.map { String($0.rota.drop(while: { $0 == "#" || $0 == "/" })) } ?? "hoje"
        let view = novaWebView(rota: rota)
        janela = view
        tarefaAoCarregar = pedido?.tarefa
        return view
    }

    /// Tarefa a abrir assim que a janela terminar de carregar.
    @ObservationIgnored var tarefaAoCarregar: String?

    func carregou(_ view: WKWebView) {
        ultimaAtualizacao = ""
        guard view === janela, let tarefa = tarefaAoCarregar else { return }
        tarefaAoCarregar = nil
        view.evaluateJavaScript("setTimeout(() => window.taskerSelecionar && taskerSelecionar(\(Self.jsString(tarefa))), 150)")
    }

    private func ir(_ view: WKWebView, rota: String, tarefa: String?) {
        var js = "location.hash = \(Self.jsString(rota));"
        if let tarefa { js += " setTimeout(() => window.taskerSelecionar && taskerSelecionar(\(Self.jsString(tarefa))), 80);" }
        view.evaluateJavaScript(js)
    }

    // MARK: Migração do app antigo

    private static let chaveMigrado = "tasker.migradoParaWeb"

    /// Na primeira vez com a interface web, leva o que o app antigo guardava só no Mac
    /// (despejo, notas, etiquetas, tempos, horários, cores e ícones das listas).
    private func migrarSePreciso(modo: String, view: WKWebView?) {
        let model = AppModel.shared
        let alvo = model.store.prefs.localMode ? "local" : "conta"
        guard modo == alvo, let view, !Pastas.defaults.bool(forKey: Self.chaveMigrado) else { return }
        Pastas.defaults.set(true, forKey: Self.chaveMigrado)
        guard let json = Self.dadosDoMac(model) else { return }
        view.evaluateJavaScript("window.taskerImportarDoMac && taskerImportarDoMac(\(json))")
    }

    static func dadosDoMac(_ model: AppModel) -> String? {
        let store = model.store
        let caderno = model.caderno
        let iso = ISO8601DateFormatter()
        let dia = DateFormatter()
        dia.dateFormat = "yyyy-MM-dd"
        var fotos: [String: String] = [:]
        func foto(_ nome: String?) -> Any {
            guard let nome else { return NSNull() }
            if fotos[nome] == nil, let dados = try? Data(contentsOf: Caderno.urlDaFoto(nome)) {
                fotos[nome] = dados.base64EncodedString()
            }
            return nome
        }
        let notas: [[String: Any]] = caderno.notas.map { n in
            ["id": n.id, "titulo": n.titulo, "texto": n.texto, "dia": n.dia.map { dia.string(from: $0) } ?? NSNull(),
             "criada": iso.string(from: n.criada), "editada": iso.string(from: n.editada), "foto": foto(n.foto)]
        }
        let despejo: [[String: Any]] = caderno.itens.map { i in
            ["id": i.id, "texto": i.texto, "estado": i.estado.rawValue, "criado": iso.string(from: i.criado),
             "movido": i.movido.map { iso.string(from: $0) } ?? NSNull(), "foto": foto(i.foto)]
        }
        let dados: [String: Any] = [
            "etiquetas": store.tagDB.tags.map { ["id": $0.id, "nome": $0.name, "cor": $0.colorHex] },
            "etiquetasDaTarefa": store.tagDB.assignments,
            "horarios": store.tagDB.horarios,
            "tempos": store.tempoDB.total,
            "notas": notas,
            "despejo": despejo,
            "fotos": fotos,
            "coresListas": store.prefs.listColors,
            "iconesListas": store.prefs.listSymbols,
            "listaPadrao": store.prefs.defaultListID ?? NSNull(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dados) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func atualizarRelogio() {
        relogio?.invalidate()
        relogio = nil
        guard cronometroInicio != nil else { return }
        relogio = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { WebPonte.shared.tique = Date() }
        }
    }

    var segundosCronometro: Double? {
        guard let inicio = cronometroInicio else { return nil }
        return cronometroAntes + max(0, tique.timeIntervalSince(inicio))
    }

    /// Login do Google no navegador do sistema; o retorno `tasker://login?code=...` volta para a web.
    private func entrar(url: URL, view: WKWebView?) {
        let sessao = ASWebAuthenticationSession(url: url, callbackURLScheme: "tasker") { retorno, _ in
            DispatchQueue.main.async {
                let ponte = WebPonte.shared
                guard let retorno else { ponte.sessaoLogin = nil; return }
                let js = "window.taskerLoginDoMac && taskerLoginDoMac(\(Self.jsString(retorno.absoluteString)))"
                ponte.executar(js, em: view)
                ponte.sessaoLogin = nil
            }
        }
        sessao.presentationContextProvider = self
        sessao.prefersEphemeralWebBrowserSession = false
        sessaoLogin = sessao
        sessao.start()
    }

    static func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let arr = String(decoding: data, as: UTF8.self)
        return String(arr.dropFirst().dropLast())
    }
}

extension WebPonte: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    }
}

extension ISO8601DateFormatter {
    static let comFracao: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// O WKUserContentController segura o handler com força: este intermediário evita o ciclo.
private final class MensagemFraca: NSObject, WKScriptMessageHandler {
    weak var alvo: WebPonte?
    init(_ alvo: WebPonte) { self.alvo = alvo }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let corpo = message.body
        let view = message.webView
        MainActor.assumeIsolated { alvo?.receber(corpo, de: view) }
    }
}

/// Serve os arquivos do build web de dentro do app.
private final class EsquemaLocal: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let pasta = MainActor.assumeIsolated({ WebPonte.pasta }) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        var caminho = url.path
        if caminho.isEmpty || caminho == "/" { caminho = "/index.html" }
        let arquivo = pasta.appendingPathComponent(String(caminho.dropFirst())).standardizedFileURL
        guard arquivo.path.hasPrefix(pasta.standardizedFileURL.path), let dados = try? Data(contentsOf: arquivo) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let resposta = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": Self.tipo(arquivo.pathExtension), "Cache-Control": "no-cache"])!
        urlSchemeTask.didReceive(resposta)
        urlSchemeTask.didReceive(dados)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    static func tipo(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "webmanifest": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }
}

/// A WebView dentro do SwiftUI (janela principal e popover do menu).
struct TelaWeb: NSViewRepresentable {
    let rota: String
    var ehJanela = false

    func makeNSView(context: Context) -> WKWebView {
        let view = ehJanela ? WebPonte.shared.novaJanela() : WebPonte.shared.novaWebView(rota: rota)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordenador { Coordenador() }

    final class Coordenador: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated { WebPonte.shared.carregou(webView) }
        }

        /// Links para fora (eventos da agenda, release do app) abrem no navegador.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, url.scheme != WebPonte.esquema, url.scheme != "about", url.scheme != "blob" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { NSWorkspace.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
            let painel = NSOpenPanel()
            painel.allowsMultipleSelection = parameters.allowsMultipleSelection
            painel.canChooseDirectories = false
            painel.begin { r in completionHandler(r == .OK ? painel.urls : nil) }
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
            let a = NSAlert()
            a.messageText = message
            a.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
            let a = NSAlert()
            a.messageText = message
            a.addButton(withTitle: "OK")
            a.addButton(withTitle: "Cancelar")
            completionHandler(a.runModal() == .alertFirstButtonReturn)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
            let a = NSAlert()
            a.messageText = prompt
            let campo = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            campo.stringValue = defaultText ?? ""
            a.accessoryView = campo
            a.addButton(withTitle: "OK")
            a.addButton(withTitle: "Cancelar")
            completionHandler(a.runModal() == .alertFirstButtonReturn ? campo.stringValue : nil)
        }
    }
}

/// Ícone da barra quando a interface é a web: número de hoje ou o cronômetro.
struct MenuBarLabelWeb: View {
    let ponte = WebPonte.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let s = ponte.segundosCronometro {
                Image(nsImage: MenuBarLabel.cronometro(Duracao.relogio(s)))
            } else {
                Image(nsImage: MenuBarLabel.icon(count: ponte.contagemHoje > 0 ? ponte.contagemHoje : nil, style: AppModel.shared.store.prefs.menuBarStyle))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.abrirJanelaPrincipal)) { _ in
            openWindow(id: WindowID.main)
        }
    }
}
