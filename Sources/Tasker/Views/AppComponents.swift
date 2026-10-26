import SwiftUI

// Peças do Tasker montadas com o design system.

// MARK: Lista: ladrilho e chip

/// Ladrilho da lista: foto, emoji ou inicial sobre a cor da lista. Nunca fica vazio.
struct ListIconView: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    var size: CGFloat = 20
    var redondo = false

    var body: some View {
        let color = store.color(forList: listID)
        Group {
            if let photo = store.photo(forList: listID) {
                Image(nsImage: photo).resizable().scaledToFill()
            } else {
                ZStack {
                    color.opacity(0.16)
                    if let emoji = store.emoji(forList: listID) {
                        Text(emoji).font(.system(size: size * 0.58))
                    } else {
                        Text(String(store.displayName(listID).prefix(1)).uppercased())
                            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: redondo ? size / 2 : size * 0.3, style: .continuous))
    }
}

/// Chip da lista: pílula tingida na cor da lista, com a foto/emoji redondo antes do nome.
struct ListChip: View {
    @Environment(TaskStore.self) private var store
    let listID: String

    var body: some View {
        let color = store.color(forList: listID)
        HStack(spacing: 5) {
            ListIconView(listID: listID, size: 16, redondo: true)
            Text(store.displayName(listID)).lineLimit(1)
        }
        .txt(.xs, .semibold)
        .foregroundStyle(color)
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.13)))
    }
}

/// Foto da conta, sempre redonda. A inicial aparece antes da foto.
struct Avatar: View {
    @Environment(GoogleAuth.self) private var auth
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(DS.superficie2)
            Text(String((auth.profile?.name ?? auth.profile?.email ?? "?").prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(DS.texto2)
            if let image = auth.avatar {
                Image(nsImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(DS.borda))
    }

    /// Imagem já recortada em círculo (rótulos de Menu ignoram .frame/.clipShape).
    @MainActor
    static func menuImage(_ image: NSImage?, side: CGFloat) -> NSImage {
        guard let image else {
            return NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: side - 4, weight: .regular)) ?? NSImage()
        }
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            let s = image.size
            let scale = max(side / max(s.width, 1), side / max(s.height, 1))
            let w = s.width * scale, h = s.height * scale
            image.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
            return true
        }
    }
}

// MARK: Tarefa: círculo, data, etiqueta

struct CheckCircle: View {
    let color: Color
    let checked: Bool
    var size: CGFloat = 20
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(color, lineWidth: 1.75)
                Circle().fill(color).opacity(checked ? 1 : (hovering ? 0.14 : 0))
                if checked || hovering {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.45, weight: .heavy))
                        .foregroundStyle(checked ? Color.white : color)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle().inset(by: -6))
        }
        .buttonStyle(SoAfunda(escala: 0.85))
        .onHover { hovering = $0 }
        .animation(DS.curvaRapida, value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: checked)
        .help(checked ? "Reabrir" : "Concluir")
    }
}

/// Data como metadado: palavra, com ícone; atrasada em acento.
struct DueLabel: View {
    let day: Date
    let today: Date

    var body: some View {
        let overdue = day < today
        HStack(spacing: DS.e1) {
            Image(systemName: overdue ? "exclamationmark.circle" : "calendar")
                .font(.system(size: 10, weight: .semibold))
            Text(DayLabel.short(day, today: today))
        }
        .foregroundStyle(overdue ? DS.perigoTexto : (day == today ? DS.texto2 : DS.texto3))
    }
}

struct TagChip: View {
    let tag: Tag

    var body: some View {
        Text("#\(tag.name)")
            .foregroundStyle(Color(hex: tag.colorHex))
    }
}

// MARK: Seção de tarefas

/// Sobrancelha + contagem + ação, e um cartão branco com as linhas separadas por fio.
struct SecaoTarefas<Content: View>: View {
    let titulo: String
    let contagem: Int
    var tom: Color = DS.texto3
    var acao: (String, () -> Void)?
    var recolhida = false
    @ViewBuilder var content: Content
    @State private var fechada: Bool

    init(_ titulo: String, contagem: Int, tom: Color = DS.texto3, acao: (String, () -> Void)? = nil,
         recolhida: Bool = false, @ViewBuilder content: () -> Content) {
        self.titulo = titulo
        self.contagem = contagem
        self.tom = tom
        self.acao = acao
        self.content = content()
        _fechada = State(initialValue: recolhida)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e2) {
            HStack(spacing: DS.e2) {
                Button {
                    withAnimation(DS.curva) { fechada.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(titulo) · \(contagem)")
                            .txt(.xs, .semibold)
                            .textCase(.uppercase)
                            .tracking(0.7)
                            .foregroundStyle(tom)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DS.texto3)
                            .rotationEffect(.degrees(fechada ? -90 : 0))
                    }
                    .padding(.vertical, DS.e1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SoAfunda())
                Spacer()
                if let acao {
                    Button(acao.0, action: acao.1).buttonStyle(Botao(variante: .fantasma))
                }
            }
            .padding(.horizontal, DS.e1)

            if !fechada {
                CartaoDeLinhas { content }
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }
}

/// Cartão branco que separa cada linha por um fio cinza-claro (recuado depois do círculo).
struct CartaoDeLinhas<Content: View>: View {
    var recuoDoFio: CGFloat = 46
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { linhas in
                ForEach(Array(linhas.enumerated()), id: \.element.id) { indice, linha in
                    if indice > 0 {
                        Rectangle()
                            .fill(DS.borda)
                            .frame(height: 1)
                            .padding(.leading, recuoDoFio)
                            .padding(.trailing, DS.e3)
                    }
                    linha
                }
            }
        }
        .padding(DS.e1)
        .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
    }
}

// MARK: Avisos

struct ErrorBanner: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        if let error = store.lastError {
            Nota(tom: .erro, texto: error) {
                HStack {
                    Spacer()
                    Button("Dispensar") { store.lastError = nil }.buttonStyle(Botao(variante: .fantasma))
                }
            }
        }
    }
}

struct CalendarIssueBanner: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let issue = store.calendarIssue {
            Nota(tom: .aviso, texto: (issue.errorDescription ?? "Não consegui ler o Google Calendar.")
                + (issue.isServiceDisabled ? " Depois de ativar, leva 1–2 minutos." : "")) {
                HStack(spacing: DS.e2) {
                    if issue.isServiceDisabled, let url = issue.activationURL {
                        Button("Ativar a API") { openURL(url) }.buttonStyle(.primario)
                    } else if issue.isScopeInsufficient {
                        Button("Entrar de novo") {
                            auth.signOut()
                            store.reset()
                        }
                        .buttonStyle(.primario)
                    }
                    Button("Tentar de novo") { Task { await store.syncEvents(force: true) } }.buttonStyle(.superficie)
                }
            }
        }
    }
}

// MARK: Conteúdo das folhas

/// Folha "Personalizar lista": ícone (emoji, foto ou inicial) e cor.
struct EditorDeLista: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    @State private var outro = ""

    private let colunas = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

    var body: some View {
        let atual = store.emoji(forList: listID)
        let temFoto = store.photo(forList: listID) != nil
        let cor = store.color(forList: listID)
        VStack(alignment: .leading, spacing: DS.e5) {
            HStack(spacing: DS.e4) {
                ListIconView(listID: listID, size: 56)
                    .overlay(RoundedRectangle(cornerRadius: 56 * 0.3, style: .continuous)
                        .strokeBorder(cor, lineWidth: 2).padding(-4))
                VStack(alignment: .leading, spacing: DS.e2) {
                    Text(store.displayName(listID)).display(.xl).foregroundStyle(DS.texto)
                    ListChip(listID: listID)
                }
            }
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: DS.e2) {
                Text("Ícone").rotulo()
                LazyVGrid(columns: colunas, spacing: 6) {
                    ForEach(Palette.emojis, id: \.self) { emoji in
                        Button {
                            store.removePhoto(forList: listID)
                            store.setEmoji(emoji, forList: listID)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: DS.raioP, style: .continuous)
                                    .fill(atual == emoji && !temFoto ? cor.opacity(0.18) : DS.superficie2))
                        }
                        .buttonStyle(Pressionavel(raio: DS.raioP, escala: 0.94))
                    }
                }
                HStack(spacing: DS.e2) {
                    TextField("Outro emoji", text: $outro)
                        .campo()
                        .frame(width: 120)
                        .onChange(of: outro) { _, valor in
                            guard let first = valor.first else { return }
                            store.removePhoto(forList: listID)
                            store.setEmoji(String(first), forList: listID)
                            if valor.count > 1 { outro = String(first) }
                        }
                    BotaoIcone(simbolo: "face.smiling", rotulo: "Abrir emojis do macOS") {
                        NSApp.orderFrontCharacterPalette(nil)
                    }
                    Spacer()
                    Button { escolherFoto() } label: { Label("Usar foto", systemImage: "photo") }
                        .buttonStyle(.superficie)
                    Button("Inicial") {
                        store.removePhoto(forList: listID)
                        store.setEmoji(nil, forList: listID)
                    }
                    .buttonStyle(.superficie)
                }
            }

            VStack(alignment: .leading, spacing: DS.e2) {
                Text("Cor").rotulo()
                AmostrasDeCor(selecao: Binding(get: { cor.hexString }, set: { store.setColor(Color(hex: $0), forList: listID) }))
            }
        }
    }

    private func escolherFoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Escolha uma foto para \(store.displayName(listID))"
        if panel.runModal() == .OK, let url = panel.url {
            store.setPhoto(from: url, forList: listID)
        }
    }
}

struct AmostrasDeCor: View {
    @Binding var selecao: String

    var body: some View {
        HStack(spacing: DS.e2) {
            ForEach(Palette.lists, id: \.self) { hex in
                let ativa = hex.uppercased() == selecao.uppercased()
                Button { selecao = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color(hex: hex), lineWidth: 2).padding(-4).opacity(ativa ? 1 : 0))
                        .padding(4)
                }
                .buttonStyle(SoAfunda(escala: 0.9))
            }
            ColorPicker("", selection: Binding(get: { Color(hex: selecao) }, set: { selecao = $0.hexString }),
                        supportsOpacity: false)
                .labelsHidden()
                .help("Outra cor")
        }
    }
}

/// Folha "Nova etiqueta".
struct CriadorDeEtiqueta: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    var aoCriar: (Tag) -> Void = { _ in }
    @State private var nome = ""
    @State private var cor = Palette.lists[5]
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e4) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nome").rotulo()
                TextField("Ex.: urgente", text: $nome).campo().focused($foco).onSubmit(criar)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Cor").rotulo()
                AmostrasDeCor(selecao: $cor)
            }
            Nota("Etiquetas ficam só no Tasker — não vão para o Google Tasks.")
            RodapeFolha {
                Spacer()
                Button("Cancelar") { folhas.fechar() }.buttonStyle(.superficie)
                Button("Criar etiqueta", action: criar)
                    .buttonStyle(.primario)
                    .disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { foco = true }
    }

    private func criar() {
        let limpo = nome.trimmingCharacters(in: .whitespaces)
        guard !limpo.isEmpty else { return }
        let tag = store.createTag(name: limpo, colorHex: cor)
        aoCriar(tag)
        withAnimation(DS.curvaSaida) { folhas.fechar() }
    }
}

// MARK: Janela do popover

/// Janela do popover da barra de menu: tema escolhido (não o da barra), cantos
/// arredondados, abre instantâneo e avisa quando abre.
struct PopoverWindowConfigurator: NSViewRepresentable {
    let appearance: NSAppearance?
    var cornerRadius: CGFloat = 16
    var onOpen: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view, context.coordinator) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onOpen = onOpen
        DispatchQueue.main.async { configure(view, context.coordinator) }
    }

    private func configure(_ view: NSView, _ coordinator: Coordinator) {
        guard let window = view.window else { return }
        window.appearance = appearance
        coordinator.onOpen = onOpen
        coordinator.attach(window, from: view, cornerRadius: cornerRadius)
    }

    @MainActor
    final class Coordinator {
        var onOpen: () -> Void = {}
        private weak var window: NSWindow?
        private var token: NSObjectProtocol?

        func attach(_ window: NSWindow, from view: NSView, cornerRadius: CGFloat) {
            // Reaplica sempre: o sistema pode recriar o fundo ao reabrir o menu.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.animationBehavior = .none
            if let frame = window.contentView?.superview {
                Self.limparFundo(frame, nossaView: view, raio: cornerRadius)
            }
            if let content = window.contentView {
                content.wantsLayer = true
                content.layer?.cornerRadius = cornerRadius
                content.layer?.cornerCurve = .continuous
                content.layer?.masksToBounds = true
                content.layer?.backgroundColor = .clear
            }
            window.invalidateShadow()

            guard self.window !== window else { return }
            self.window = window
            if let token { NotificationCenter.default.removeObserver(token) }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self, weak window, weak view] _ in
                MainActor.assumeIsolated {
                    if let window, let view { self?.attach(window, from: view, cornerRadius: cornerRadius) }
                    self?.onOpen()
                }
            }
            onOpen()
        }

        /// Esconde o vidro/fundo do sistema (que tem cantos mais quadrados) e arredonda
        /// as camadas que contêm o nosso conteúdo, para só sobrar o nosso desenho.
        private static func limparFundo(_ view: NSView, nossaView: NSView, raio: CGFloat, depth: Int = 0) {
            let contemNossaView = nossaView.isDescendant(of: view)
            if let effect = view as? NSVisualEffectView {
                if contemNossaView {
                    effect.maskImage = .roundedMask(radius: raio)
                    effect.material = .windowBackground
                    effect.state = .inactive
                    effect.alphaValue = 1
                } else {
                    effect.isHidden = true
                }
            }
            if contemNossaView {
                view.wantsLayer = true
                view.layer?.cornerRadius = raio
                view.layer?.cornerCurve = .continuous
                view.layer?.masksToBounds = true
            }
            guard depth < 6 else { return }
            for sub in view.subviews { limparFundo(sub, nossaView: nossaView, raio: raio, depth: depth + 1) }
        }
    }
}

extension NSImage {
    /// Máscara esticável com cantos arredondados (para NSVisualEffectView).
    static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

}
