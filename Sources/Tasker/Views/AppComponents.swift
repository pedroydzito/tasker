import SwiftUI

// Peças do Tasker montadas com o design system.

// MARK: Lista: ladrilho e chip

/// Ladrilho da lista: foto, ícone ou inicial sobre a cor da lista. Nunca fica vazio.
struct ListIconView: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    var size: CGFloat = 20
    var redondo = false

    /// Raio do ladrilho para um tamanho (use para desenhar anéis em volta com o mesmo desenho).
    static func raio(_ size: CGFloat) -> CGFloat { size * 0.3 }

    var body: some View {
        let color = store.color(forList: listID)
        Group {
            if let photo = store.photo(forList: listID) {
                Image(nsImage: photo).resizable().scaledToFill()
            } else {
                ZStack {
                    color.opacity(0.16)
                    if let symbol = store.symbol(forList: listID) {
                        Image(systemName: symbol)
                            .font(.system(size: size * 0.5, weight: .medium))
                            .foregroundStyle(color)
                    } else {
                        Text(String(store.displayName(listID).prefix(1)).uppercased())
                            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: redondo ? size / 2 : Self.raio(size), style: .continuous))
    }
}

/// Ladrilho com anel na cor da lista; o anel segue o mesmo desenho do ladrilho (raio + folga).
struct ListIconComAnel: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    var size: CGFloat = 56
    var folga: CGFloat = 4
    var espessura: CGFloat = 2

    var body: some View {
        ListIconView(listID: listID, size: size)
            .padding(folga)
            .overlay(
                RoundedRectangle(cornerRadius: ListIconView.raio(size) + folga, style: .continuous)
                    .strokeBorder(store.color(forList: listID), lineWidth: espessura)
            )
    }
}

/// Chip da lista: pílula tingida na cor da lista, com a foto/ícone redondo antes do nome.
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

/// Folha "Personalizar lista": nome, ícone (biblioteca, foto ou inicial) e cor. Só salva ao clicar em "Salvar".
struct EditorDeLista: View {
    enum Modo: Hashable { case icone, foto, inicial }

    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    let listID: String

    @State private var nome = ""
    @State private var modo: Modo = .inicial
    @State private var simbolo: String?
    @State private var foto: NSImage?
    @State private var fotoURL: URL?
    @State private var cor = Palette.lists[0]
    @State private var carregado = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e5) {
            HStack(spacing: DS.e4) {
                PreviaDeLista(nome: nome, modo: modo, simbolo: simbolo, foto: foto, cor: Color(hex: cor), tamanho: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nome").rotulo()
                    TextField("Nome da lista", text: $nome).campo()
                }
            }

            VStack(alignment: .leading, spacing: DS.e3) {
                HStack {
                    Text("Ícone").rotulo()
                    Spacer()
                    Segmentado(selecao: $modo, opcoes: [(.icone, "Ícone"), (.foto, "Foto"), (.inicial, "Inicial")])
                }
                switch modo {
                case .icone:
                    SeletorDeIcone(selecionado: $simbolo, cor: Color(hex: cor))
                case .foto:
                    HStack(spacing: DS.e3) {
                        Button { escolherFoto() } label: {
                            Label(foto == nil ? "Escolher foto…" : "Trocar foto…", systemImage: "photo")
                        }
                        .buttonStyle(.superficie)
                        Text("Fica redonda nos chips e quadrada no ícone da lista.").txt(.xs).foregroundStyle(DS.texto3)
                    }
                case .inicial:
                    Text("Mostra a primeira letra do nome sobre a cor da lista.").txt(.xs).foregroundStyle(DS.texto3)
                }
            }

            VStack(alignment: .leading, spacing: DS.e2) {
                Text("Cor").rotulo()
                AmostrasDeCor(selecao: $cor)
            }

            RodapeFolha {
                if listID != store.pinnedListID {
                    Button("Excluir lista") {
                        let nomeAtual = store.displayName(listID)
                        folhas.confirmar("Excluir lista",
                                         mensagem: "“\(nomeAtual)” e as tarefas dela serão excluídas, também no Google Tasks. Dá para desfazer logo depois.") {
                            Task { await store.deleteList(listID) }
                        }
                    }
                    .buttonStyle(Botao(variante: .fantasma))
                }
                Spacer()
                Button("Cancelar") { folhas.fechar() }.buttonStyle(.superficie)
                Button("Salvar", action: salvar).buttonStyle(.primario).keyboardShortcut(.defaultAction)
                    .disabled(modo == .foto && foto == nil)
            }
        }
        .onAppear(perform: carregar)
    }

    private func carregar() {
        guard !carregado else { return }
        carregado = true
        nome = store.list(listID)?.title ?? ""
        simbolo = store.symbol(forList: listID)
        foto = store.photo(forList: listID)
        cor = store.color(forList: listID).hexString
        modo = foto != nil ? .foto : (simbolo != nil ? .icone : .inicial)
    }

    private func salvar() {
        if nome.trimmingCharacters(in: .whitespaces) != (store.list(listID)?.title ?? "") {
            Task { await store.renameList(listID, to: nome) }
        }
        store.setColor(Color(hex: cor), forList: listID)
        switch modo {
        case .icone:
            store.removePhoto(forList: listID)
            store.setSymbol(simbolo, forList: listID)
        case .foto:
            if let fotoURL { store.setPhoto(from: fotoURL, forList: listID) }
            store.setSymbol(nil, forList: listID)
        case .inicial:
            store.removePhoto(forList: listID)
            store.setSymbol(nil, forList: listID)
        }
        withAnimation(DS.curvaSaida) { folhas.fechar() }
    }

    private func escolherFoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Escolha uma foto para \(store.displayName(listID))"
        if panel.runModal() == .OK, let url = panel.url, let imagem = NSImage(contentsOf: url) {
            fotoURL = url
            foto = imagem
        }
    }
}

/// Prévia do ladrilho com o que está sendo editado (antes de salvar).
struct PreviaDeLista: View {
    let nome: String
    let modo: EditorDeLista.Modo
    let simbolo: String?
    let foto: NSImage?
    let cor: Color
    var tamanho: CGFloat = 56

    var body: some View {
        Group {
            if modo == .foto, let foto {
                Image(nsImage: foto).resizable().scaledToFill()
            } else {
                ZStack {
                    cor.opacity(0.16)
                    if modo == .icone, let simbolo {
                        Image(systemName: simbolo).font(.system(size: tamanho * 0.48, weight: .medium)).foregroundStyle(cor)
                    } else {
                        let (_, limpo) = TaskStore.splitLeadingSymbols(nome)
                        Text(String((limpo.isEmpty ? nome : limpo).prefix(1)).uppercased())
                            .font(.system(size: tamanho * 0.46, weight: .bold, design: .rounded))
                            .foregroundStyle(cor)
                    }
                }
            }
        }
        .frame(width: tamanho, height: tamanho)
        .clipShape(RoundedRectangle(cornerRadius: ListIconView.raio(tamanho), style: .continuous))
        .padding(4)
        .overlay(RoundedRectangle(cornerRadius: ListIconView.raio(tamanho) + 4, style: .continuous).strokeBorder(cor, lineWidth: 2))
        .animation(DS.curva, value: modo)
    }
}

/// Seletor de ícone: busca em português + grade. O escolhido fica preenchido na cor (nada é cortado).
struct SeletorDeIcone: View {
    @Binding var selecionado: String?
    let cor: Color
    @State private var busca = ""

    private let colunas = Array(repeating: GridItem(.flexible(), spacing: 6), count: 9)

    private var resultados: [String] {
        let termo = busca.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
        guard !termo.isEmpty else { return Palette.simbolos }
        return Palette.icones.filter {
            ($0.busca + " " + $0.nome).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(termo)
        }.map(\.nome)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e2) {
            HStack(spacing: DS.e2) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(DS.texto3)
                TextField("Buscar: casa, trabalho, dinheiro…", text: $busca).textFieldStyle(.plain).txt(.sm)
            }
            .padding(.horizontal, DS.e3)
            .frame(height: 34)
            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))

            ScrollView {
                LazyVGrid(columns: colunas, spacing: 6) {
                    ForEach(resultados, id: \.self) { nome in
                        let ativo = selecionado == nome
                        Button { selecionado = nome } label: {
                            Image(systemName: nome)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(ativo ? Color.white : DS.texto2)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                                    .fill(ativo ? cor : DS.superficie2))
                        }
                        .buttonStyle(Pressionavel(raio: DS.raioM, escala: 0.92))
                        .help(nome)
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.automatic)
            .frame(height: 172)
            .overlay {
                if resultados.isEmpty {
                    Text("Nenhum ícone para “\(busca)”").txt(.xs).foregroundStyle(DS.texto3)
                }
            }
        }
    }
}

/// Folha "Nova lista": nome, ícone e cor. No Google, a lista aparece no Google Tasks também.
struct NovaLista: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    @Environment(Navigation.self) private var nav
    @State private var nome = ""
    @State private var simbolo: String?
    @State private var cor = Palette.lists[5]
    @State private var criando = false
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e5) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nome").rotulo()
                TextField("Ex.: Clientes", text: $nome).campo().focused($foco).onSubmit(criar)
            }
            VStack(alignment: .leading, spacing: DS.e2) {
                Text("Ícone").rotulo()
                SeletorDeIcone(selecionado: $simbolo, cor: Color(hex: cor))
            }
            VStack(alignment: .leading, spacing: DS.e2) {
                Text("Cor").rotulo()
                AmostrasDeCor(selecao: $cor)
            }
            if !store.prefs.localMode {
                Nota("A lista também é criada no Google Tasks. O ícone e a cor ficam só no Tasker.")
            }
            RodapeFolha {
                Spacer()
                Button("Cancelar") { folhas.fechar() }.buttonStyle(.superficie)
                Button(criando ? "Criando…" : "Criar lista", action: criar)
                    .buttonStyle(.primario)
                    .disabled(nome.trimmingCharacters(in: .whitespaces).isEmpty || criando)
            }
        }
        .onAppear { foco = true }
    }

    private func criar() {
        guard !criando, !nome.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        criando = true
        Task {
            if let id = await store.createList(title: nome, symbol: simbolo, colorHex: cor) {
                nav.selection = .list(id)
            }
            withAnimation(DS.curvaSaida) { folhas.fechar() }
        }
    }
}

/// Amostras de cor + seletor próprio (hex colável, matiz, saturação e brilho).
struct AmostrasDeCor: View {
    @Binding var selecao: String
    @State private var personalizada = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            HStack(spacing: 6) {
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
                Button {
                    withAnimation(DS.curva) { personalizada.toggle() }
                } label: {
                    Image(systemName: personalizada ? "chevron.up" : "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.texto2)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(DS.superficie2))
                }
                .buttonStyle(PressionavelCirculo())
                .help("Outra cor")
            }
            if personalizada {
                SeletorDeCor(hex: $selecao)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }
}

/// Seletor de cor no visual do app: prévia, código hex (pode colar) e três trilhos.
struct SeletorDeCor: View {
    @Binding var hex: String
    @State private var texto = ""
    @State private var h: Double = 0
    @State private var s: Double = 0.7
    @State private var b: Double = 0.9

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e3) {
            HStack(spacing: DS.e3) {
                RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                    .fill(Color(hue: h, saturation: s, brightness: b))
                    .frame(width: 40, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).strokeBorder(DS.borda))
                HStack(spacing: 2) {
                    Text("#").txt(.md, .medium).foregroundStyle(DS.texto3)
                    TextField("0097FF", text: $texto)
                        .textFieldStyle(.plain)
                        .txt(.md, .medium)
                        .monospaced()
                        .onSubmit(aplicarTexto)
                        .onChange(of: texto) { _, novo in
                            let limpo = novo.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                            if limpo.count == 6, limpo.allSatisfy(\.isHexDigit) { aplicarTexto() }
                        }
                }
                .padding(.horizontal, DS.e3)
                .frame(height: 36)
                .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
            }
            trilho("Matiz", valor: $h,
                   cores: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 0.9, brightness: 0.95) })
            trilho("Saturação", valor: $s, cores: [Color(hue: h, saturation: 0, brightness: b), Color(hue: h, saturation: 1, brightness: b)])
            trilho("Brilho", valor: $b, cores: [.black, Color(hue: h, saturation: s, brightness: 1)])
        }
        .onAppear(perform: carregar)
    }

    private func trilho(_ rotulo: String, valor: Binding<Double>, cores: [Color]) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: cores, startPoint: .leading, endPoint: .trailing))
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: max(0, min(geo.size.width - 18, CGFloat(valor.wrappedValue) * (geo.size.width - 18))))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                valor.wrappedValue = max(0, min(1, Double((g.location.x - 9) / max(1, geo.size.width - 18))))
                publicar()
            })
        }
        .frame(height: 18)
        .help(rotulo)
    }

    private func carregar() {
        let ns = NSColor(hex: hex).usingColorSpace(.sRGB) ?? .systemBlue
        h = Double(ns.hueComponent)
        s = Double(ns.saturationComponent)
        b = Double(ns.brightnessComponent)
        texto = hex.replacingOccurrences(of: "#", with: "").uppercased()
    }

    private func publicar() {
        let novo = Color(hue: h, saturation: s, brightness: b).hexString
        hex = novo
        texto = String(novo.dropFirst())
    }

    private func aplicarTexto() {
        let limpo = texto.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        guard limpo.count == 6, limpo.allSatisfy(\.isHexDigit) else { return }
        let novo = "#" + limpo.uppercased()
        guard novo.uppercased() != hex.uppercased() else { return }
        hex = novo
        let ns = NSColor(hex: novo).usingColorSpace(.sRGB) ?? .systemBlue
        h = Double(ns.hueComponent)
        s = Double(ns.saturationComponent)
        b = Double(ns.brightnessComponent)
    }
}

/// Folha "Escolher lista": as listas, com ícones, na mesma ordem da barra lateral.
struct EscolhaDeLista: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    let atual: String?
    let escolher: (String) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(store.lists) { list in
                let ativa = list.id == atual
                Button {
                    escolher(list.id)
                    withAnimation(DS.curvaSaida) { folhas.fechar() }
                } label: {
                    HStack(spacing: DS.e3) {
                        ListIconView(listID: list.id, size: 26)
                        Text(store.displayName(list.id)).txt(.sm, ativa ? .semibold : .medium).foregroundStyle(DS.texto)
                        Spacer()
                        if ativa {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(DS.acento)
                        }
                    }
                    .padding(.horizontal, DS.e2)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                        .fill(ativa ? store.color(forList: list.id).opacity(0.12) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(Pressionavel(raio: DS.raioM))
            }
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
            // Os cantos são os do próprio sistema: o nosso fundo cobre a janela inteira,
            // sem desenhar um segundo arredondamento por cima (era o que criava a borda dupla).
            window.animationBehavior = .none
            guard self.window !== window else { return }
            self.window = window
            if let token { NotificationCenter.default.removeObserver(token) }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onOpen() }
            }
            onOpen()
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
