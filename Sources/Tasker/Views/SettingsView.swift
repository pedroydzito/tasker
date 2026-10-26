import ServiceManagement
import SwiftUI

/// Ajustes em cartões próprios (nada do formulário cinza padrão).
struct SettingsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Updater.self) private var updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var prefs = store.prefs
        PageScaffold(title: "Ajustes", subtitle: "Tasker \(updater.currentVersion)") {
            SettingsCard("Conta", symbol: "person.crop.circle") {
                HStack(spacing: 12) {
                    Avatar(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.profile?.name ?? "Conta Google").font(.system(size: 14, weight: .semibold))
                        Text(auth.profile?.email ?? "").font(.system(size: 12)).foregroundStyle(Theme.subtle)
                    }
                    Spacer()
                    Button("Sair da conta") {
                        auth.signOut()
                        store.reset()
                    }
                    .buttonStyle(.soft)
                }
                .padding(.vertical, 4)
            }

            SettingsCard("Aparência", symbol: "paintbrush") {
                SettingsRow("Tema", "Vale para a janela e para o menu, mesmo com a barra escura") {
                    PillPicker(selection: $prefs.appearance,
                               options: AppAppearance.allCases.map { ($0, $0.title) })
                }
            }

            SettingsCard("Barra de menu", symbol: "menubar.rectangle") {
                SettingsRow("Mostrar contador", "Número de tarefas de hoje no ícone") {
                    Toggle("", isOn: $prefs.showCountInMenuBar).toggleStyle(.switch).labelsHidden()
                }
                SettingsDivider()
                SettingsRow("Estilo do ícone") {
                    PillPicker(selection: $prefs.menuBarStyle,
                               options: MenuBarStyle.allCases.map { ($0, $0.title) })
                }
                SettingsDivider()
                SettingsRow("Contar atrasadas", "Agora: \(store.badgeCount) tarefa\(store.badgeCount == 1 ? "" : "s")") {
                    Toggle("", isOn: $prefs.includeOverdueInCount).toggleStyle(.switch).labelsHidden()
                }
            }

            SettingsCard("Listas", symbol: "list.bullet") {
                SettingsRow("Lista padrão", "Para onde vão as tarefas novas") {
                    Menu {
                        ForEach(store.lists) { list in
                            Button(store.displayName(list.id)) { prefs.defaultListID = list.id }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if let id = store.defaultList?.id { ListIconView(listID: id, size: 16) }
                            Text(store.defaultList.map { store.displayName($0.id) } ?? "—")
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                ForEach(store.lists) { list in
                    SettingsDivider()
                    ListSettingsRow(listID: list.id)
                }
            }

            SettingsCard("Calendários", symbol: "calendar") {
                if store.calendars.isEmpty {
                    Text("Nenhum calendário carregado.").font(.system(size: 12.5)).foregroundStyle(Theme.subtle)
                }
                ForEach(Array(store.calendars.enumerated()), id: \.element.id) { index, calendar in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: calendar.colorHex)).frame(width: 10, height: 10)
                        Text(calendar.title).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.isVisible(calendar) },
                            set: { store.setVisible($0, calendar: calendar) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                    .padding(.vertical, 3)
                }
            }

            SettingsCard("Sincronização", symbol: "arrow.triangle.2.circlepath") {
                SettingsRow("Verificar mudanças") {
                    PillPicker(selection: $prefs.syncInterval,
                               options: [(15.0, "15s"), (30.0, "30s"), (60.0, "1 min"), (300.0, "5 min")])
                }
                .onChange(of: prefs.syncInterval) { store.scheduleTimer() }
                SettingsDivider()
                HStack {
                    SyncStatusButton()
                    Spacer()
                    Button("Sincronizar agora") { Task { await store.sync(force: true) } }.buttonStyle(.soft)
                }
            }

            SettingsCard("Atualizações", symbol: "arrow.down.circle") {
                UpdateBanner()
                SettingsRow("Versão instalada", "Build \(updater.currentBuild) · verifica sozinho a cada 30 min") {
                    HStack(spacing: 8) {
                        switch updater.state {
                        case .checking: ProgressView().controlSize(.small)
                        case .upToDate: Text("Em dia").font(.system(size: 12)).foregroundStyle(.green)
                        case .failed(let message): Text(message).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                        default: EmptyView()
                        }
                        Button("Procurar") { Task { await updater.check(userInitiated: true) } }.buttonStyle(.soft)
                    }
                }
            }

            SettingsCard("Geral", symbol: "gearshape") {
                SettingsRow("Abrir ao iniciar o Mac") {
                    Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch {
                                store.lastError = "Não foi possível alterar o início automático: \(error.localizedDescription)"
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
                SettingsDivider()
                SettingsRow("Adicionar de qualquer lugar") { KeyCap("⌥ Espaço") }
                SettingsDivider()
                SettingsRow("Criação rápida", "hoje · amanhã · sexta · 30/10 · ~lista · #etiqueta") { EmptyView() }
                SettingsDivider()
                HStack {
                    Spacer()
                    Button("Encerrar Tasker") { NSApp.terminate(nil) }.buttonStyle(.soft)
                }
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.subtle)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke.opacity(0.7)))
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    init(_ title: String, _ subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.subtle) }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 2)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.stroke.opacity(0.7)).frame(height: 1)
    }
}

struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Linha de lista nos Ajustes: ícone, nome, pílula e editor.
private struct ListSettingsRow: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    @State private var editing = false

    var body: some View {
        HStack(spacing: 10) {
            ListIconView(listID: listID, size: 24)
            Text(store.displayName(listID)).font(.system(size: 13))
            Spacer()
            ListChip(listID: listID)
            Button("Personalizar") { editing = true }
                .buttonStyle(.soft)
                .popover(isPresented: $editing, arrowEdge: .trailing) { ListAppearanceEditor(listID: listID) }
        }
    }
}
