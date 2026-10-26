import SwiftUI

/// Primeiro acesso: credenciais do Google Cloud + login.
struct OnboardingView: View {
    @Environment(GoogleAuth.self) private var auth
    @Environment(TaskStore.self) private var store

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 84, height: 84)
                }
                VStack(spacing: 6) {
                    Text("Bem-vindo ao Tasker").font(.system(size: 26, weight: .bold))
                    Text("Suas tarefas do Google Tasks e eventos do Google Calendar, direto na barra de menu.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("1. Crie suas credenciais (uma vez só)").font(.headline)
                    Text("""
                    No [Google Cloud Console](https://console.cloud.google.com/apis/credentials), ative as APIs **Google Tasks** e **Google Calendar**, \
                    configure a tela de consentimento e crie um **ID do cliente OAuth** do tipo **App para computador**. \
                    O passo a passo completo está no README do projeto.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    TextField("Client ID (….apps.googleusercontent.com)", text: $clientID)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Client Secret", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)

                    Text("2. Conecte sua conta").font(.headline).padding(.top, 8)
                    HStack {
                        Button {
                            Task { await signIn() }
                        } label: {
                            Label("Entrar com Google", systemImage: "person.crop.circle.badge.checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(clientID.isEmpty || clientSecret.isEmpty || auth.isSigningIn)

                        if auth.isSigningIn {
                            ProgressView().controlSize(.small)
                            Button("Cancelar") { auth.cancelSignIn() }
                        }
                    }
                    if auth.isSigningIn {
                        Text("Continue o login no navegador…").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(20)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(maxWidth: 520)
            .padding(40)
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
            // usuário cancelou
        } catch {
            self.error = error.localizedDescription
        }
    }
}
