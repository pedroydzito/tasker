import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Updater.self) private var updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var prefs = store.prefs
        Form {
            Section("Atualizações") {
                UpdateBanner()
                LabeledContent("Versão instalada", value: "\(updater.currentVersion) (build \(updater.currentBuild))")
                HStack {
                    Button("Procurar atualizações") { Task { await updater.check(userInitiated: true) } }
                    switch updater.state {
                    case .checking: ProgressView().controlSize(.small)
                    case .upToDate: Text("Você está na versão mais recente").foregroundStyle(.secondary)
                    case .failed(let message): Text(message).foregroundStyle(.red)
                    default: EmptyView()
                    }
                }
                Text("O Tasker verifica sozinho a cada 30 minutos e avisa por notificação.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Conta") {
                HStack(spacing: 12) {
                    Avatar(profile: auth.profile, size: 40)
                    VStack(alignment: .leading) {
                        Text(auth.profile?.name ?? "Conta Google").font(.headline)
                        Text(auth.profile?.email ?? "").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sair da conta") {
                        auth.signOut()
                        store.reset()
                    }
                }
            }

            Section("Barra de menu") {
                Toggle("Mostrar contador de tarefas", isOn: $prefs.showCountInMenuBar)
                Picker("Estilo", selection: $prefs.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Contar tarefas atrasadas", isOn: $prefs.includeOverdueInCount)
                LabeledContent("Agora", value: "\(store.badgeCount) tarefa\(store.badgeCount == 1 ? "" : "s")")
            }

            Section("Tarefas") {
                Picker("Lista padrão", selection: Binding(
                    get: { store.defaultList?.id ?? "" },
                    set: { store.prefs.defaultListID = $0 }
                )) {
                    ForEach(store.lists) { Text($0.title).tag($0.id) }
                }
                ForEach(store.lists) { list in
                    ColorPicker(list.title, selection: Binding(
                        get: { store.color(forList: list.id) },
                        set: { store.setColor($0, forList: list.id) }
                    ), supportsOpacity: false)
                }
            }

            Section("Calendários") {
                if store.calendars.isEmpty {
                    Text("Nenhum calendário carregado ainda.").foregroundStyle(.secondary)
                }
                ForEach(store.calendars) { calendar in
                    Toggle(isOn: Binding(
                        get: { store.isVisible(calendar) },
                        set: { store.setVisible($0, calendar: calendar) }
                    )) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: calendar.colorHex)).frame(width: 9, height: 9)
                            Text(calendar.title)
                        }
                    }
                }
            }

            Section("Sincronização") {
                Picker("Verificar mudanças a cada", selection: $prefs.syncInterval) {
                    Text("15 segundos").tag(15.0)
                    Text("30 segundos").tag(30.0)
                    Text("1 minuto").tag(60.0)
                    Text("2 minutos").tag(120.0)
                    Text("5 minutos").tag(300.0)
                }
                .onChange(of: prefs.syncInterval) { store.scheduleTimer() }
                LabeledContent("Última sincronização") {
                    if let last = store.lastSync {
                        Text(last, style: .relative) + Text(" atrás")
                    } else {
                        Text("—")
                    }
                }
                Button("Sincronizar agora") { Task { await store.sync(force: true) } }
            }

            Section("Geral") {
                Toggle("Abrir ao iniciar o Mac", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            store.lastError = "Não foi possível alterar o início automático: \(error.localizedDescription)"
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                LabeledContent("Adicionar de qualquer lugar", value: "⌥ Espaço")
                LabeledContent("Na criação rápida") {
                    Text("hoje · amanhã · sexta · 30/10 · ~lista · #etiqueta").foregroundStyle(.secondary)
                }
                Button("Encerrar Tasker", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
    }
}
