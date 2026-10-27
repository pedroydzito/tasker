import AppKit
import SwiftUI

/// `Tasker --capturas <pasta>`: monta dados de exemplo (pasta isolada) e salva PNGs das telas
/// reais, claro e escuro. Usado no CI para conferir o visual sem abrir o app à mão.
@MainActor
enum Capturas {
    static func iniciar(pasta: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DSFonts.register()
        Task { @MainActor in
            let ok = await rodar(pasta: URL(fileURLWithPath: pasta, isDirectory: true))
            exit(ok ? 0 : 1)
        }
        app.run()
    }

    private static func rodar(pasta: URL) async -> Bool {
        guard Pastas.isolado != nil else {
            print("Recusado: rode com TASKER_HOME apontando para uma pasta de teste.")
            return false
        }
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        let (store, caderno) = await Autoteste.montar()
        await semear(store, caderno)
        let auth = store.auth
        let nav = Navigation()
        let updater = Updater()

        func ambiente<V: View>(_ v: V) -> some View {
            v.environment(store).environment(auth).environment(nav).environment(updater).environment(caderno)
        }

        let janela = CGSize(width: 1180, height: 760)
        var cenas: [(String, CGSize, () -> AnyView)] = [
            ("01-hoje", janela, { nav.selection = .today; return AnyView(ambiente(MainWindow())) }),
            ("02-despejo", janela, { nav.selection = .despejo; return AnyView(ambiente(MainWindow())) }),
            ("03-triagem", janela, { AnyView(ambiente(Moldura { DespejoView(abrirTriagem: true) })) }),
            ("04-notas-dia", janela, { nav.selection = .notas; nav.notaAberta = .dia(store.today); return AnyView(ambiente(MainWindow())) }),
            ("06-calendario", janela, { nav.selection = .calendar; return AnyView(ambiente(MainWindow())) }),
            ("07-busca", CGSize(width: 640, height: 560), { AnyView(ambiente(Moldura { BuscaView(consultaInicial: "reuniao") })) }),
            ("08-menu", CGSize(width: MenuBarPopover.largura, height: MenuBarPopover.altura), { AnyView(ambiente(MenuBarPopover())) }),
            ("09-lista-subtarefas", janela, {
                nav.selection = store.defaultList.map { .list($0.id) } ?? .all
                nav.subtarefasAbertas = Set(store.tasks.values.filter { !store.subtarefas(de: $0.id).isEmpty }.map(\.id))
                return AnyView(ambiente(MainWindow()))
            }),
        ]
        if let ideia = caderno.notas.first(where: { $0.dia == nil }) {
            cenas.append(("05-nota-solta", janela, { nav.selection = .notas; nav.notaAberta = .nota(ideia.id); return AnyView(ambiente(MainWindow())) }))
        }

        var ok = true
        for (nome, tamanho, fazer) in cenas {
            for escuro in [false, true] {
                store.prefs.appearance = escuro ? .dark : .light
                let arquivo = pasta.appendingPathComponent("\(nome)-\(escuro ? "escuro" : "claro").png")
                if await capturar(fazer(), tamanho: tamanho, escuro: escuro, em: arquivo) {
                    print("  ✓ \(arquivo.lastPathComponent)")
                } else {
                    print("  ✗ \(arquivo.lastPathComponent)")
                    ok = false
                }
            }
        }
        return ok
    }

    /// Fundo e folhas de uma tela solta (sem a janela inteira).
    private struct Moldura<C: View>: View {
        @State private var folhas = Folhas()
        @ViewBuilder var conteudo: C
        var body: some View {
            conteudo
                .padding(DS.e6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(DS.fundo)
                .hospedaFolhas(folhas)
        }
    }

    private static func capturar(_ view: AnyView, tamanho: CGSize, escuro: Bool, em arquivo: URL) async -> Bool {
        let hosting = NSHostingView(rootView: view)
        let janela = NSWindow(contentRect: NSRect(origin: .zero, size: tamanho), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        janela.appearance = NSAppearance(named: escuro ? .darkAqua : .aqua)
        NSApp.appearance = janela.appearance
        janela.contentView = hosting
        janela.setFrameOrigin(NSPoint(x: 40, y: 40))
        janela.orderFrontRegardless()
        // Deixa o SwiftUI montar, animar a entrada e carregar.
        try? await Task.sleep(for: .milliseconds(1400))
        hosting.layoutSubtreeIfNeeded()
        defer { janela.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: arquivo)) != nil
    }

    /// Dados de exemplo parecidos com o uso real.
    private static func semear(_ store: TaskStore, _ caderno: Caderno) async {
        let hoje = store.today
        let cal = Calendar.current
        let lista = store.defaultList?.id
        store.addTask(title: "Enviar proposta para a Taís", listID: lista, due: hoje, horario: "10:00")
        store.addTask(title: "Comprar presente de aniversário", listID: lista, due: hoje)
        store.addTask(title: "Revisar capítulo 2 do TCC", listID: lista, due: cal.adding(days: 1, to: hoje))
        store.addTask(title: "Pagar boleto da internet", listID: lista, due: cal.adding(days: -2, to: hoje))
        store.addTask(title: "Organizar fotos da viagem", listID: lista, due: nil)
        await store.aguardarOperacoes()
        if let mae = store.tasks.values.first(where: { $0.title == "Revisar capítulo 2 do TCC" }) {
            store.addSubtask(title: "Ler comentários da orientadora", parent: mae)
            store.addSubtask(title: "Ajustar referências", parent: mae)
            store.addSubtask(title: "Reescrever a conclusão", parent: mae)
            await store.aguardarOperacoes()
            if let feita = store.subtarefas(de: mae.id).first { store.setCompleted(feita, true) }
        }
        caderno.capturar("""
        marcar consulta no dentista
        ideia: app de receitas da semana
        ver preço da passagem pra dezembro
        devolver o livro da biblioteca
        mandar mensagem pra vó
        """)
        caderno.escreverNoDia(hoje, texto: """
        Semana puxada, mas dá. Foco no TCC de manhã.

        [ ] marcar médico
        [ ] separar roupas da academia
        → enviar proposta
        """)
        caderno.novaNota(titulo: "Ideias do app", texto: "Reunião com Ana sobre o despejo e as notas.\n\n- triagem um a um\n- busca em tudo")
        await store.aguardarOperacoes()
        // Espera a conclusão da subtarefa ser enviada.
        await store.aguardarOperacoes()
    }
}
