import ServiceManagement
import SwiftUI

/// Ajustes como lista de assuntos (pastas): uma aberta, o resto fechado, o que não tem volta por último.
struct SettingsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Updater.self) private var updater
    @Environment(Folhas.self) private var folhas
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var prefs = store.prefs
        PageScaffold(rotulo: "Tasker \(updater.currentVersion)", title: "Ajustes") {
            VStack(alignment: .leading, spacing: DS.e3) {
                Pasta(icone: "paintbrush", titulo: "Aparência e barra de menu",
                      subtitulo: "Tema, contador e estilo do ícone", aberta: true) {
                    LinhaAjuste("Tema", "Vale para a janela e para o menu da barra") {
                        Segmentado(selecao: $prefs.appearance, opcoes: AppAppearance.allCases.map { ($0, $0.title) })
                    }
                    LinhaAjuste("Mostrar contador", "Número de tarefas de hoje no ícone") {
                        Toggle("", isOn: $prefs.showCountInMenuBar).toggleStyle(.chave).labelsHidden()
                    }
                    LinhaAjuste("Estilo do ícone") {
                        Segmentado(selecao: $prefs.menuBarStyle, opcoes: [(.badge, "Selo"), (.iconAndNumber, "Número ao lado")])
                    }
                    LinhaAjuste("Contar atrasadas", "Agora: \(store.badgeCount) tarefa\(store.badgeCount == 1 ? "" : "s")") {
                        Toggle("", isOn: $prefs.includeOverdueInCount).toggleStyle(.chave).labelsHidden()
                    }
                }

                Pasta(icone: "list.bullet", titulo: "Listas",
                      subtitulo: "Lista padrão, ícone e cor de cada lista") {
                    LinhaAjuste("Lista padrão", "Para onde vão as tarefas novas") {
                        Menu {
                            ForEach(store.lists) { list in
                                Button(store.displayName(list.id)) { prefs.defaultListID = list.id }
                            }
                        } label: {
                            if let id = store.defaultList?.id { ListChip(listID: id) }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    ForEach(store.lists) { list in
                        HStack(spacing: DS.e3) {
                            ListIconView(listID: list.id, size: 28)
                            Text(store.displayName(list.id)).txt(.sm, .medium).foregroundStyle(DS.texto)
                            Spacer()
                            Button("Personalizar") {
                                folhas.abrir("Personalizar lista", largura: 440) { EditorDeLista(listID: list.id) }
                            }
                            .buttonStyle(.superficie)
                        }
                    }
                    Nota("Arraste as listas na barra lateral para mudar a ordem.")
                }

                Pasta(icone: "calendar", titulo: "Calendários",
                      subtitulo: "Quais agendas do Google aparecem no Tasker") {
                    if store.calendars.isEmpty {
                        Nota("Nenhuma agenda carregada ainda.")
                    }
                    ForEach(store.calendars) { calendar in
                        LinhaAjuste(calendar.title) {
                            Toggle("", isOn: Binding(
                                get: { store.isVisible(calendar) },
                                set: { store.setVisible($0, calendar: calendar) }
                            ))
                            .toggleStyle(.chave)
                            .labelsHidden()
                            .tint(Color(hex: calendar.colorHex))
                        }
                    }
                }

                Pasta(icone: "arrow.triangle.2.circlepath", titulo: "Sincronização e atualizações",
                      subtitulo: "Intervalo, versão instalada e novas versões") {
                    LinhaAjuste("Verificar mudanças a cada") {
                        Segmentado(selecao: $prefs.syncInterval, opcoes: [(15.0, "15 s"), (30.0, "30 s"), (60.0, "1 min"), (300.0, "5 min")])
                    }
                    .onChange(of: prefs.syncInterval) { store.scheduleTimer() }
                    HStack {
                        SyncStatusButton()
                        Spacer()
                        Button("Sincronizar agora") { Task { await store.sync(force: true) } }.buttonStyle(.superficie)
                    }
                    UpdateBanner()
                    LinhaAjuste("Versão \(updater.currentVersion)", "Build \(updater.currentBuild) · verifica sozinho a cada 30 min") {
                        HStack(spacing: DS.e2) {
                            switch updater.state {
                            case .checking: ProgressView().controlSize(.small)
                            case .upToDate: Text("Em dia").txt(.xs, .semibold).foregroundStyle(DS.sucesso)
                            case .failed(let message): Text(message).txt(.xs).foregroundStyle(DS.perigoTexto).lineLimit(2)
                            default: EmptyView()
                            }
                            Button("Procurar atualização") { Task { await updater.check(userInitiated: true) } }.buttonStyle(.superficie)
                        }
                    }
                }

                Pasta(icone: "gearshape", titulo: "Geral",
                      subtitulo: "Abrir ao iniciar, atalho e criação rápida") {
                    LinhaAjuste("Abrir ao iniciar o Mac") {
                        Toggle("", isOn: $launchAtLogin).toggleStyle(.chave).labelsHidden()
                            .onChange(of: launchAtLogin) { _, enabled in
                                do {
                                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                                } catch {
                                    store.lastError = "Não consegui mudar o início automático. Tente de novo."
                                    launchAtLogin = SMAppService.mainApp.status == .enabled
                                }
                            }
                    }
                    LinhaAjuste("Adicionar de qualquer lugar") { Tecla("⌥ Espaço") }
                    LinhaAjuste("Criação rápida", "hoje · amanhã · sexta · 30/10 · ~lista · #etiqueta") { EmptyView() }
                }

                Pasta(icone: "person.crop.circle", titulo: "Conta", subtitulo: auth.profile?.email ?? "Google", perigo: true) {
                    HStack(spacing: DS.e3) {
                        Avatar(size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.profile?.name ?? "Conta Google").txt(.sm, .semibold).foregroundStyle(DS.texto)
                            Text(auth.profile?.email ?? "").txt(.xs).foregroundStyle(DS.texto3)
                        }
                        Spacer()
                        Button("Sair da conta") {
                            auth.signOut()
                            store.reset()
                        }
                        .buttonStyle(.perigo)
                    }
                    HStack {
                        Spacer()
                        Button("Encerrar o Tasker") { NSApp.terminate(nil) }.buttonStyle(.superficie)
                    }
                }
            }
        }
    }
}

struct Tecla: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto)
            .txt(.xs, .semibold)
            .foregroundStyle(DS.texto2)
            .padding(.horizontal, DS.e2)
            .padding(.vertical, DS.e1)
            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioP, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.raioP, style: .continuous).strokeBorder(DS.borda))
    }
}
