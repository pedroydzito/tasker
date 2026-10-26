import SwiftUI
import UniformTypeIdentifiers

/// Primeira abertura: escolher entre conectar o Google ou usar só neste Mac.
struct OnboardingView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.e6) {
                VStack(alignment: .leading, spacing: DS.e3) {
                    Simbolo(tamanho: 52)
                    Text("Bem-vindo ao Tasker").display().foregroundStyle(DS.texto)
                    Text("Suas tarefas e os eventos do dia, direto na barra de menu.")
                        .txt(.lg)
                        .foregroundStyle(DS.texto2)
                }
                .encadeado(0)

                ConectarGoogle()
                    .cartao()
                    .encadeado(1)

                VStack(alignment: .leading, spacing: DS.e3) {
                    HStack(spacing: DS.e3) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.texto2)
                            .frame(width: 36, height: 36)
                            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Usar sem conta").txt(.md, .semibold).foregroundStyle(DS.texto)
                            Text("Tudo fica só neste Mac. Dá para exportar e conectar o Google depois.")
                                .txt(.sm)
                                .foregroundStyle(DS.texto3)
                        }
                        Spacer()
                        Button("Começar") { store.useLocalMode() }
                            .buttonStyle(Botao(variante: .superficie, tamanho: .m))
                    }
                }
                .cartao()
                .encadeado(2)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, DS.e8)
            .padding(.vertical, 64)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

/// Conectar a conta Google: passos com links diretos e o arquivo de credenciais arrastável.
struct ConectarGoogle: View {
    @Environment(GoogleAuth.self) private var auth
    @Environment(TaskStore.self) private var store

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var erro: String?
    @State private var mostrarCampos = false
    @State private var arrastandoArquivo = false

    private var temCredenciais: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e4) {
            HStack(spacing: DS.e3) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.acento)
                    .frame(width: 36, height: 36)
                    .background(DS.acento.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conectar Google Tasks e Agenda").txt(.md, .semibold).foregroundStyle(DS.texto)
                    Text("Sincroniza com o celular e com o navegador.").txt(.sm).foregroundStyle(DS.texto3)
                }
            }

            if !temCredenciais {
                VStack(alignment: .leading, spacing: DS.e2) {
                    passo(1, "Ativar as APIs Tasks e Calendar", "Cria o projeto e liga as duas APIs de uma vez.",
                          "https://console.cloud.google.com/flows/enableapi?apiid=tasks.googleapis.com,calendar-json.googleapis.com")
                    passo(2, "Configurar a tela de consentimento", "Tipo Externo, seu e-mail como usuário e “Publicar app”.",
                          "https://console.cloud.google.com/auth/overview")
                    passo(3, "Criar a credencial “App para computador”", "No fim, clique em “Baixar JSON”.",
                          "https://console.cloud.google.com/auth/clients/create")
                }
                areaDoArquivo
            } else {
                HStack(spacing: DS.e2) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(DS.sucesso)
                    Text("Credenciais prontas").txt(.sm, .medium).foregroundStyle(DS.texto)
                    Spacer()
                    Button("Trocar") {
                        clientID = ""
                        clientSecret = ""
                    }
                    .buttonStyle(Botao(variante: .fantasma))
                }
            }

            Button { withAnimation(DS.curva) { mostrarCampos.toggle() } } label: {
                HStack(spacing: 4) {
                    Text(mostrarCampos ? "Esconder campos" : "Preencher à mão")
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(mostrarCampos ? 180 : 0))
                }
                .txt(.xs, .medium)
                .foregroundStyle(DS.texto3)
            }
            .buttonStyle(SoAfunda())

            if mostrarCampos {
                VStack(alignment: .leading, spacing: DS.e3) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client ID").rotulo()
                        TextField("….apps.googleusercontent.com", text: $clientID).campo()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client secret").rotulo()
                        SecureField("GOCSPX-…", text: $clientSecret).campo()
                    }
                }
                .transition(.opacity)
            }

            HStack(spacing: DS.e3) {
                Button {
                    Task { await entrar() }
                } label: {
                    Label("Entrar com Google", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(Botao(variante: .primario, tamanho: .m, largo: true))
                .disabled(!temCredenciais || auth.isSigningIn)

                if auth.isSigningIn {
                    Button("Cancelar") { auth.cancelSignIn() }.buttonStyle(Botao(variante: .superficie, tamanho: .m))
                }
            }
            if auth.isSigningIn {
                Text("Continue o login no navegador…").txt(.xs).foregroundStyle(DS.texto3)
            }
            if let erro {
                Nota(tom: .erro, erro)
            }
        }
        .onAppear {
            clientID = auth.clientID
            clientSecret = auth.clientSecret
        }
    }

    private func passo(_ n: Int, _ titulo: String, _ detalhe: String, _ link: String) -> some View {
        Button { if let url = URL(string: link) { NSWorkspace.shared.open(url) } } label: {
            HStack(alignment: .top, spacing: DS.e3) {
                Text("\(n)")
                    .txt(.xs, .bold)
                    .foregroundStyle(DS.acento)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(DS.acento.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).txt(.sm, .semibold).foregroundStyle(DS.texto)
                    Text(detalhe).txt(.xs).foregroundStyle(DS.texto3)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.texto3)
            }
            .padding(DS.e3)
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressionavel(raio: DS.raioM, escala: 0.99))
    }

    /// Solte aqui o JSON baixado do Google (ou clique para escolher).
    private var areaDoArquivo: some View {
        Button(action: escolherArquivo) {
            VStack(spacing: 6) {
                Image(systemName: "doc.badge.plus").font(.system(size: 20, weight: .medium)).foregroundStyle(DS.acento)
                Text("4 · Solte aqui o arquivo JSON baixado").txt(.sm, .semibold).foregroundStyle(DS.texto)
                Text("ou clique para escolher — o Tasker lê o ID e o secret sozinho").txt(.xs).foregroundStyle(DS.texto3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.e5)
            .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                .fill(arrastandoArquivo ? DS.acento.opacity(0.08) : DS.superficie2))
            .overlay(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                .strokeBorder(arrastandoArquivo ? DS.acento : DS.bordaForte, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(SoAfunda(escala: 0.99))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return lerCredenciais(url)
        } isTargeted: { arrastandoArquivo = $0 }
    }

    private func escolherArquivo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Escolha o arquivo JSON da credencial do Google"
        if panel.runModal() == .OK, let url = panel.url { _ = lerCredenciais(url) }
    }

    /// Lê {"installed": {"client_id", "client_secret"}} (formato do Google).
    @discardableResult
    private func lerCredenciais(_ url: URL) -> Bool {
        struct Arquivo: Decodable {
            struct Cliente: Decodable {
                let client_id: String
                let client_secret: String
            }
            let installed: Cliente?
            let web: Cliente?
        }
        guard let data = try? Data(contentsOf: url),
              let arquivo = try? JSONDecoder().decode(Arquivo.self, from: data),
              let cliente = arquivo.installed ?? arquivo.web
        else {
            erro = "Esse arquivo não parece ser a credencial do Google. Baixe o JSON da credencial “App para computador”."
            return false
        }
        withAnimation(DS.curva) {
            clientID = cliente.client_id
            clientSecret = cliente.client_secret
            erro = nil
        }
        return true
    }

    private func entrar() async {
        erro = nil
        auth.saveCredentials(clientID: clientID, clientSecret: clientSecret)
        do {
            try await auth.signIn()
            if store.prefs.localMode {
                store.useGoogleMode()
            } else {
                await store.sync(force: true)
            }
        } catch is CancellationError {
            // a pessoa cancelou
        } catch {
            erro = error.localizedDescription
        }
    }
}
