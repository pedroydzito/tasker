import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Ajustes como lista de assuntos (pastas), na ordem em que se procura:
/// conta → aparência → menu → tarefas → agenda → sincronização → dados → geral → atualizações.
struct SettingsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(Updater.self) private var updater
    @Environment(Folhas.self) private var folhas
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var mensagemDados: (String, TomNota)?
    @State private var importando = false

    var body: some View {
        @Bindable var prefs = store.prefs
        PageScaffold(rotulo: "Tasker \(updater.currentVersion)", title: "Ajustes") {
            VStack(alignment: .leading, spacing: DS.e3) {
                Pasta(icone: "person.crop.circle", titulo: "Conta",
                      subtitulo: store.prefs.localMode ? "Usando só neste Mac" : (auth.profile?.email ?? "Google"),
                      aberta: true) {
                    if store.prefs.localMode {
                        Nota("Suas tarefas estão guardadas só neste Mac. Conecte o Google para sincronizar com o celular — depois use Dados → Importar para levar as tarefas de agora.")
                        ConectarGoogle()
                    } else {
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
                            .buttonStyle(.superficie)
                        }
                        LinhaAjuste("Usar sem conta", "Troca para tarefas guardadas só neste Mac") {
                            Button("Trocar") {
                                auth.signOut()
                                store.useLocalMode()
                            }
                            .buttonStyle(.superficie)
                        }
                    }
                }

                Pasta(icone: "paintbrush", titulo: "Aparência", subtitulo: "Tema claro, escuro ou do sistema") {
                    LinhaAjuste("Tema", "Vale para a janela e para o menu da barra") {
                        Segmentado(selecao: $prefs.appearance, opcoes: AppAppearance.allCases.map { ($0, $0.title) })
                    }
                }

                Pasta(icone: "menubar.rectangle", titulo: "Barra de menu",
                      subtitulo: "Contador, ícone e o que aparece no menu") {
                    LinhaAjuste("Mostrar contador", "Número de tarefas de hoje no ícone") {
                        Toggle("", isOn: $prefs.showCountInMenuBar).toggleStyle(.chave).labelsHidden()
                    }
                    LinhaAjuste("Estilo do ícone") {
                        Segmentado(selecao: $prefs.menuBarStyle, opcoes: [(.badge, "Selo"), (.iconAndNumber, "Número ao lado")])
                    }
                    LinhaAjuste("Contar atrasadas", "Agora: \(store.badgeCount) tarefa\(store.badgeCount == 1 ? "" : "s")") {
                        Toggle("", isOn: $prefs.includeOverdueInCount).toggleStyle(.chave).labelsHidden()
                    }
                    LinhaAjuste("Eventos no menu", "Mostrar a agenda do dia acima das tarefas") {
                        Toggle("", isOn: $prefs.showEventsInMenu).toggleStyle(.chave).labelsHidden()
                    }
                    LinhaAjuste("Atrasadas no menu", "Mostrar a seção “Em atraso”") {
                        Toggle("", isOn: $prefs.showOverdueInMenu).toggleStyle(.chave).labelsHidden()
                    }
                }

                Pasta(icone: "checklist", titulo: "Tarefas e listas",
                      subtitulo: "Lista padrão, som e aparência de cada lista") {
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
                    LinhaAjuste("Som ao concluir") {
                        Toggle("", isOn: $prefs.completionSound).toggleStyle(.chave).labelsHidden()
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
                    HStack {
                        Button {
                            folhas.abrir("Nova lista", largura: 420) { NovaLista() }
                        } label: { Label("Nova lista", systemImage: "plus") }
                        .buttonStyle(.superficie)
                        Spacer()
                    }
                    Nota("Segure e arraste as listas na barra lateral para mudar a ordem.")
                }

                if store.usesGoogle {
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
                            }
                        }
                    }

                    Pasta(icone: "arrow.triangle.2.circlepath", titulo: "Sincronização",
                          subtitulo: "De quanto em quanto tempo buscar mudanças") {
                        LinhaAjuste("Verificar mudanças a cada") {
                            Segmentado(selecao: $prefs.syncInterval,
                                       opcoes: [(15.0, "15 s"), (30.0, "30 s"), (60.0, "1 min"), (300.0, "5 min")])
                        }
                        .onChange(of: prefs.syncInterval) { store.scheduleTimer() }
                        HStack {
                            SyncStatusButton()
                            Spacer()
                            Button("Sincronizar agora") { Task { await store.sync(force: true) } }.buttonStyle(.superficie)
                        }
                    }
                }

                Pasta(icone: "externaldrive", titulo: "Dados",
                      subtitulo: "Exportar e importar listas, tarefas e etiquetas") {
                    LinhaAjuste("Exportar tudo", "Um arquivo .json para guardar ou levar a outro Mac") {
                        Button("Exportar…", action: exportar).buttonStyle(.superficie)
                    }
                    LinhaAjuste("Importar", "Junta um arquivo exportado às suas listas") {
                        Button(importando ? "Importando…" : "Importar…", action: importar)
                            .buttonStyle(.superficie)
                            .disabled(importando)
                    }
                    if let mensagemDados {
                        Nota(tom: mensagemDados.1, mensagemDados.0)
                    }
                }

                Pasta(icone: "gearshape", titulo: "Geral", subtitulo: "Abrir ao iniciar, atalho e criação rápida") {
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

                Pasta(icone: "arrow.down.circle", titulo: "Atualizações",
                      subtitulo: "Versão \(updater.currentVersion) · procura sozinho a cada 30 min") {
                    UpdateBanner()
                    LinhaAjuste("Versão \(updater.currentVersion)", "Build \(updater.currentBuild)") {
                        HStack(spacing: DS.e2) {
                            switch updater.state {
                            case .checking: ProgressView().controlSize(.small)
                            case .upToDate: Text("Em dia").txt(.xs, .semibold).foregroundStyle(DS.sucesso)
                            case .failed(let message): Text(message).txt(.xs).foregroundStyle(DS.perigoTexto).lineLimit(2)
                            default: EmptyView()
                            }
                            Button("Procurar atualização") { Task { await updater.check(userInitiated: true) } }
                                .buttonStyle(.superficie)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Encerrar o Tasker") { NSApp.terminate(nil) }.buttonStyle(Botao(variante: .fantasma))
                }
                .padding(.top, DS.e2)
            }
        }
    }

    private func exportar() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Tasker \(Date().formatted(.dateTime.day().month(.twoDigits).year())).json"
            .replacingOccurrences(of: "/", with: "-")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportar(para: url)
            mensagemDados = ("Exportado: \(url.lastPathComponent)", .info)
        } catch {
            mensagemDados = ("Não consegui exportar. Tente de novo.", .erro)
        }
    }

    private func importar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Escolha um arquivo exportado pelo Tasker"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importando = true
        Task {
            do {
                let total = try await store.importar(de: url)
                mensagemDados = ("\(total) tarefa\(total == 1 ? "" : "s") importada\(total == 1 ? "" : "s").", .info)
            } catch {
                mensagemDados = ("Esse arquivo não pôde ser importado. Use um arquivo exportado pelo Tasker.", .erro)
            }
            importando = false
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
