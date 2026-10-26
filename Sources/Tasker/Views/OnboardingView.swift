import SwiftUI

/// Primeira abertura: credenciais do Google Cloud + login, uma camada por vez.
struct OnboardingView: View {
    @Environment(GoogleAuth.self) private var auth
    @Environment(TaskStore.self) private var store

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.e6) {
                VStack(alignment: .leading, spacing: DS.e4) {
                    Simbolo(tamanho: 56)
                    Text("Bem-vindo ao Tasker").display().foregroundStyle(DS.texto)
                    Text("Suas tarefas do Google Tasks e os eventos do Google Calendar, direto na barra de menu.")
                        .txt(.lg)
                        .foregroundStyle(DS.texto2)
                }
                .encadeado(0)

                VStack(alignment: .leading, spacing: DS.e4) {
                    Text("1 · Credenciais do Google").rotulo()
                    Nota("No Google Cloud Console, ative as APIs Google Tasks e Google Calendar, configure a tela de consentimento e crie um ID do cliente OAuth do tipo “App para computador”. O passo a passo está no README.")
                    Link("Abrir o Google Cloud Console", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                        .txt(.sm, .medium)
                        .foregroundStyle(DS.link)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client ID").rotulo()
                        TextField("….apps.googleusercontent.com", text: $clientID).campo()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client secret").rotulo()
                        SecureField("GOCSPX-…", text: $clientSecret).campo()
                    }
                }
                .cartao()
                .encadeado(1)

                VStack(alignment: .leading, spacing: DS.e4) {
                    Text("2 · Conectar a conta").rotulo()
                    HStack(spacing: DS.e3) {
                        Button {
                            Task { await signIn() }
                        } label: {
                            Label("Entrar com Google", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .buttonStyle(Botao(variante: .primario, tamanho: .g, largo: true))
                        .disabled(clientID.isEmpty || clientSecret.isEmpty || auth.isSigningIn)

                        if auth.isSigningIn {
                            Button("Cancelar") { auth.cancelSignIn() }.buttonStyle(Botao(variante: .superficie, tamanho: .g))
                        }
                    }
                    if auth.isSigningIn {
                        Text("Continue o login no navegador…").txt(.xs).foregroundStyle(DS.texto3)
                    }
                    if let error {
                        Nota(tom: .erro, error)
                    }
                }
                .cartao()
                .encadeado(2)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, DS.e8)
            .padding(.vertical, 72)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            clientID = auth.clientID
            clientSecret = auth.clientSecret
        }
    }

    private func signIn() async {
        error = nil
        auth.saveCredentials(clientID: clientID, clientSecret: clientSecret)
        do {
            try await auth.signIn()
            await store.sync(force: true)
        } catch is CancellationError {
            // a pessoa cancelou
        } catch {
            self.error = error.localizedDescription
        }
    }
}
