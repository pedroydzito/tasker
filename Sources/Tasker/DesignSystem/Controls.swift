import SwiftUI
import AppKit

// Componentes do design system. Antes de escrever estilo numa tela, use um destes.

// MARK: Véu e toque

/// O piso de interação: véu de hover (5,5%) + afundar no clique.
struct Veu: ViewModifier {
    var raio: CGFloat = DS.raioM
    var escala: CGFloat = 0.97
    var pressionado = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: raio, style: .continuous)
                .fill(pressionado ? DS.veuAtivo : (hovering ? DS.veuHover : .clear)))
            .scaleEffect(pressionado ? escala : 1)
            .animation(pressionado ? DS.toque : DS.curvaRapida, value: pressionado)
            .animation(DS.curvaRapida, value: hovering)
            .onHover { hovering = $0 && !RolagemSuave.shared.rolando }
            .pointerStyle(.link)
    }
}

// MARK: Botão

enum VarianteBotao { case primario, superficie, fantasma, perigo, invertido }
enum TamanhoBotao { case p, m, g }

/// Botão: um componente, cinco variantes, três tamanhos. Raio de campo (12).
struct Botao: ButtonStyle {
    var variante: VarianteBotao = .superficie
    var tamanho: TamanhoBotao = .p
    var largo = false

    func makeBody(configuration: Configuration) -> some View {
        BotaoCorpo(configuration: configuration, variante: variante, tamanho: tamanho, largo: largo)
    }

    private struct BotaoCorpo: View {
        let configuration: Configuration
        let variante: VarianteBotao
        let tamanho: TamanhoBotao
        let largo: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .txt(tamanho == .p ? .sm : .sm, .semibold)
                .foregroundStyle(foreground)
                .frame(height: altura)
                .frame(maxWidth: largo ? .infinity : nil)
                .padding(.horizontal, tamanho == .p ? DS.e3 : (tamanho == .m ? DS.e4 : DS.e5))
                .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                    .fill(configuration.isPressed ? DS.veuAtivo : (hovering && isEnabled ? DS.veuHover : .clear)))
                .contentShape(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(configuration.isPressed ? DS.toque : DS.curvaRapida, value: configuration.isPressed)
                .animation(DS.curvaRapida, value: hovering)
                .onHover { hovering = $0 && !RolagemSuave.shared.rolando }
                .pointerStyle(isEnabled ? .link : nil)
        }

        private var altura: CGFloat {
            switch tamanho {
            case .p: 32
            case .m: 40
            case .g: 48
            }
        }

        private var fill: Color {
            switch variante {
            case .primario: DS.acentoSolido
            case .superficie: DS.superficie2
            case .fantasma: .clear
            case .perigo: DS.perigo
            case .invertido: DS.texto
            }
        }

        private var foreground: Color {
            switch variante {
            case .primario, .perigo: DS.acentoSolidoTexto
            case .superficie: DS.texto
            case .fantasma: hovering ? DS.texto : DS.texto2
            case .invertido: DS.fundo
            }
        }
    }
}

extension ButtonStyle where Self == Botao {
    static var primario: Botao { Botao(variante: .primario) }
    static var superficie: Botao { Botao(variante: .superficie) }
    static var fantasma: Botao { Botao(variante: .fantasma) }
    static var perigo: Botao { Botao(variante: .perigo) }
}

/// Gesto do ícone, deduzido do rótulo (como no design system).
enum GestoIcone {
    case nenhum, apagar, fechar, criar, voltar, avancar, expandir, sincronizar

    static func doRotulo(_ rotulo: String) -> GestoIcone {
        let r = rotulo.lowercased()
        if r.hasPrefix("apagar") || r.hasPrefix("excluir") || r.hasPrefix("remover") { return .apagar }
        if r.hasPrefix("fechar") { return .fechar }
        if r.hasPrefix("nova") || r.hasPrefix("novo") || r.hasPrefix("criar") || r.hasPrefix("adicionar") { return .criar }
        if r.hasPrefix("voltar") || r.hasPrefix("anterior") { return .voltar }
        if r.hasPrefix("avançar") || r.hasPrefix("próxim") { return .avancar }
        if r.hasPrefix("abrir") { return .expandir }
        if r.hasPrefix("Sincronizar") { return .sincronizar }
        return .nenhum
    }
}

/// Botão só de ícone: pílula, rótulo obrigatório (vira tooltip), ícone que reage.
struct BotaoIcone: View {
    let simbolo: String
    let rotulo: String
    var tamanho: CGFloat = 32
    var tamanhoIcone: CGFloat = 14
    var ativo = false
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            IconeQueReage(simbolo: simbolo, gesto: GestoIcone.doRotulo(rotulo), tamanho: tamanhoIcone)
                .foregroundStyle(ativo ? DS.acentoSolidoTexto : DS.texto2)
                .frame(width: tamanho, height: tamanho)
                .background(Circle().fill(ativo ? DS.acentoSolido : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressionavelCirculo())
        .help(rotulo)
        .accessibilityLabel(rotulo)
    }
}

/// O ícone só cresce no hover (12%) — nada de girar ou deslizar.
struct IconeQueReage: View {
    let simbolo: String
    var gesto: GestoIcone = .nenhum
    var tamanho: CGFloat = 14
    @State private var hovering = false

    var body: some View {
        Image(systemName: simbolo)
            .font(.system(size: tamanho, weight: .medium))
            .scaleEffect(hovering ? 1.12 : 1)
            .animation(DS.curvaRapida, value: hovering)
            .onHover { hovering = $0 && !RolagemSuave.shared.rolando }
    }
}

/// Controle pequeno: só afunda (0.94), com véu redondo.
struct PressionavelCirculo: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(Veu(raio: 999, escala: 0.94, pressionado: configuration.isPressed))
    }
}

/// Qualquer clicável com caixa própria (linha, item): véu + 0.97.
struct Pressionavel: ButtonStyle {
    var raio: CGFloat = DS.raioM
    var escala: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(Veu(raio: raio, escala: escala, pressionado: configuration.isPressed))
    }
}

/// Sem véu (o item já responde de outro jeito): cresce um pouco no hover e afunda no clique.
struct SoAfunda: ButtonStyle {
    var escala: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(Escala(escala: escala, pressionado: configuration.isPressed))
    }
}

/// Hover (cresce) + clique (afunda), proporcional ao tamanho do afundar.
struct Escala: ViewModifier {
    var escala: CGFloat = 0.97
    var pressionado = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        // Itens grandes (escala perto de 1) quase não crescem; ícones pequenos crescem mais.
        let hover = 1 + max(0.006, (1 - escala) * 0.6)
        content
            .scaleEffect(pressionado ? escala : (hovering && isEnabled ? hover : 1))
            .brightness(hovering && isEnabled && !pressionado ? -0.03 : 0)
            .animation(pressionado ? DS.toque : DS.curvaRapida, value: pressionado)
            .animation(DS.curvaRapida, value: hovering)
            .onHover { hovering = $0 && !RolagemSuave.shared.rolando }
            .pointerStyle(.link)
    }
}

/// Para Menu (não é Button): véu atrás no hover e mais escuro quando o menu abre.
/// Não muda o tamanho nem a posição (o botão de menu do AppKit não escala bem) e
/// não usa gesto por cima, para não atrapalhar o menu de abrir.
struct EscalaDeMenu: ViewModifier {
    var raio: CGFloat = 999
    @State private var pressionado = false
    @State private var sobre = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: raio, style: .continuous)
                    .fill(pressionado ? DS.veuAtivo : (sobre ? DS.veuHover : .clear))
                    .padding(-4)
                    .allowsHitTesting(false)
            }
            .animation(DS.curvaRapida, value: sobre)
            .animation(pressionado ? DS.toque : DS.curvaRapida, value: pressionado)
            .onHover { sobre = $0 }
            .pointerStyle(.link)
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                guard sobre else { return }
                pressionado = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                pressionado = false
                sobre = false
            }
    }
}

extension View {
    func animacaoDeClique(raio: CGFloat = 999) -> some View { modifier(EscalaDeMenu(raio: raio)) }
}

// MARK: Campo

extension View {
    /// Campo: superfície-2, raio de campo, txt-md.
    func campo() -> some View {
        textFieldStyle(.plain)
            .txt(.md)
            .padding(.horizontal, DS.e4)
            .padding(.vertical, 10)
            .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioM, style: .continuous))
    }
}

// MARK: Chip

/// Chip: pílula, txt-xs semibold. Com cor: fundo tingido + a própria cor como letra.
struct Chip<Leading: View>: View {
    let texto: String
    var cor: Color?
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 6) {
            leading
            Text(texto).lineLimit(1)
        }
        .txt(.xs, .semibold)
        .foregroundStyle(cor ?? DS.texto3)
        .padding(.leading, Leading.self == EmptyView.self ? 10 : 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(cor.map { $0.opacity(DS.chipTinta) } ?? DS.superficie2))
    }
}

extension Chip {
    init(_ texto: String, cor: Color? = nil, @ViewBuilder leading: () -> Leading) {
        self.texto = texto
        self.cor = cor
        self.leading = leading()
    }
}

extension Chip where Leading == EmptyView {
    init(_ texto: String, cor: Color? = nil) {
        self.texto = texto
        self.cor = cor
        self.leading = EmptyView()
    }
}

// MARK: Chave (liga/desliga)

struct Chave: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? DS.acentoSolido : DS.superficie3)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .padding(2)
            }
            .frame(width: 40, height: 24)
            .animation(DS.curva, value: configuration.isOn)
        }
        .buttonStyle(SoAfunda(escala: 0.94))
        .accessibilityAddTraits(.isToggle)
    }
}

extension ToggleStyle where Self == Chave {
    static var chave: Chave { Chave() }
}

// MARK: Segmentado (com trilho que desliza)

struct Segmentado<Value: Hashable>: View {
    @Binding var selecao: Value
    let opcoes: [(Value, String)]
    @Namespace private var trilho

    var body: some View {
        HStack(spacing: 2) {
            ForEach(opcoes.indices, id: \.self) { i in
                let (valor, rotulo) = opcoes[i]
                let ativo = valor == selecao
                Button {
                    withAnimation(DS.curva) { selecao = valor }
                } label: {
                    Text(rotulo)
                        .txt(.sm, .semibold)
                        .foregroundStyle(ativo ? DS.texto : DS.texto3)
                        .padding(.horizontal, DS.e3)
                        .frame(height: 30)
                        .background {
                            if ativo {
                                Capsule().fill(DS.superficie)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "trilho", in: trilho)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SoAfunda())
            }
        }
        .padding(3)
        .background(Capsule().fill(DS.superficie2))
    }
}

// MARK: Nota

enum TomNota { case info, aviso, erro }

struct Nota<Acoes: View>: View {
    var tom: TomNota = .info
    let texto: String
    @ViewBuilder var acoes: Acoes

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e2) {
            HStack(alignment: .top, spacing: DS.e2) {
                Image(systemName: icone).font(.system(size: 13, weight: .semibold)).padding(.top, 1)
                Text(texto).txt(.xs).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(cor)
            acoes
        }
        .padding(.horizontal, 14)
        .padding(.vertical, DS.e3)
        .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous).fill(fundo))
    }

    private var icone: String {
        switch tom {
        case .info: "info.circle"
        case .aviso: "exclamationmark.triangle"
        case .erro: "exclamationmark.circle"
        }
    }

    private var cor: Color {
        switch tom {
        case .info: DS.texto2
        case .aviso: DS.aviso
        case .erro: DS.perigoTexto
        }
    }

    private var fundo: Color {
        switch tom {
        case .info: DS.superficie2
        case .aviso: DS.avisoTenue
        case .erro: DS.perigoTenue
        }
    }
}

extension Nota where Acoes == EmptyView {
    init(tom: TomNota = .info, _ texto: String) {
        self.tom = tom
        self.texto = texto
        self.acoes = EmptyView()
    }
}

// MARK: Estado vazio

struct EstadoVazio: View {
    let icone: String
    let titulo: String
    var descricao: String?

    @State private var flutua = false

    var body: some View {
        VStack(spacing: DS.e2) {
            Image(systemName: icone)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(DS.texto3)
                .offset(y: flutua ? -3 : 0)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: flutua)
                .padding(.bottom, DS.e1)
            Text(titulo).display(.lg).foregroundStyle(DS.texto)
            if let descricao {
                Text(descricao).txt(.sm).foregroundStyle(DS.texto3).multilineTextAlignment(.center).frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onAppear { flutua = true }
    }
}

// MARK: Sanfona (pasta de ajustes)

struct Pasta<Content: View>: View {
    let icone: String
    let titulo: String
    let subtitulo: String
    var perigo = false
    @ViewBuilder var content: Content
    @State private var aberta: Bool
    @State private var hovering = false

    init(icone: String, titulo: String, subtitulo: String, aberta: Bool = false, perigo: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.icone = icone
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.perigo = perigo
        self.content = content()
        _aberta = State(initialValue: aberta)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(DS.curva) { aberta.toggle() }
            } label: {
                HStack(spacing: DS.e3) {
                    Image(systemName: icone)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(perigo ? DS.perigoTexto : DS.texto2)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(titulo).txt(.sm, .semibold).foregroundStyle(DS.texto)
                        Text(subtitulo).txt(.xs).foregroundStyle(DS.texto3).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.texto3)
                        .rotationEffect(.degrees(aberta ? 180 : 0))
                }
                .padding(.horizontal, DS.e5)
                .padding(.vertical, DS.e4)
                .background(hovering ? DS.veuHover : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(SoAfunda(escala: 0.995))
            .onHover { hovering = $0 && !RolagemSuave.shared.rolando }

            if aberta {
                Rectangle().fill(DS.borda).frame(height: 1)
                VStack(alignment: .leading, spacing: DS.e4) { content }
                    .padding(DS.e5)
                    .transition(.opacity)
            }
        }
        .background(DS.superficie)
        .clipShape(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous)
            .strokeBorder(perigo ? DS.perigo.opacity(0.45) : DS.borda))
    }
}

/// Linha de ajuste: frase (sm medium) + descrição (xs t3) + controle.
struct LinhaAjuste<Control: View>: View {
    let titulo: String
    var descricao: String?
    @ViewBuilder var control: Control

    init(_ titulo: String, _ descricao: String? = nil, @ViewBuilder control: () -> Control) {
        self.titulo = titulo
        self.descricao = descricao
        self.control = control()
    }

    var body: some View {
        HStack(spacing: DS.e3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).txt(.sm, .medium).foregroundStyle(DS.texto)
                if let descricao { Text(descricao).txt(.xs).foregroundStyle(DS.texto3) }
            }
            Spacer(minLength: DS.e2)
            control
        }
    }
}

// MARK: Cabeçalho de tela

/// Sobrancelha (contexto) + título display em caixa baixa.
struct CabecalhoTela<Leading: View, Trailing: View>: View {
    let rotulo: String?
    let titulo: String
    var tamanho: Txt = .display
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: DS.e4) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).display(tamanho).foregroundStyle(DS.texto).lineLimit(2)
                if let rotulo { Text(rotulo).txt(.sm).foregroundStyle(DS.texto3) }
            }
            Spacer(minLength: DS.e4)
            trailing
        }
    }
}

extension CabecalhoTela where Leading == EmptyView, Trailing == EmptyView {
    init(rotulo: String?, titulo: String, tamanho: Txt = .display) {
        self.rotulo = rotulo
        self.titulo = titulo
        self.tamanho = tamanho
        self.leading = EmptyView()
        self.trailing = EmptyView()
    }
}

extension CabecalhoTela where Trailing == EmptyView {
    init(rotulo: String?, titulo: String, tamanho: Txt = .display, @ViewBuilder leading: () -> Leading) {
        self.rotulo = rotulo
        self.titulo = titulo
        self.tamanho = tamanho
        self.leading = leading()
        self.trailing = EmptyView()
    }
}

/// Entrada encadeada: cada bloco sobe 10px com 48ms × i de atraso.
struct Encadeado: ViewModifier {
    let indice: Int
    @State private var visivel = false

    func body(content: Content) -> some View {
        content
            .opacity(visivel ? 1 : 0)
            .offset(y: visivel ? 0 : 10)
            .onAppear {
                withAnimation(DS.curva.delay(Double(indice) * 0.048)) { visivel = true }
            }
    }
}

extension View {
    func encadeado(_ indice: Int) -> some View { modifier(Encadeado(indice: indice)) }
}

// MARK: Indicativo de rolagem

/// Mostra que há mais conteúdo: esmaecido na borda e uma setinha embaixo enquanto der para rolar.
struct IndicadorDeRolagem: ViewModifier {
    var fundo: Color
    @State private var temAcima = false
    @State private var temAbaixo = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: [Bool].self) { g in
                // visibleRect já conta as margens internas (contentInsets) do ScrollView.
                [g.visibleRect.minY > -g.contentInsets.top + 2,
                 g.visibleRect.maxY < g.contentSize.height + g.contentInsets.bottom - 2]
            } action: { _, valor in
                temAcima = valor[0]
                temAbaixo = valor[1]
            }
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    LinearGradient(colors: [fundo, fundo.opacity(0)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.texto3)
                        .padding(.top, 2)
                }
                .frame(height: 26)
                .opacity(temAcima ? 1 : 0)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    LinearGradient(colors: [fundo.opacity(0), fundo], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.texto3)
                        .padding(.bottom, 2)
                }
                .frame(height: 26)
                .opacity(temAbaixo ? 1 : 0)
                .allowsHitTesting(false)
            }
            .animation(DS.curvaRapida, value: temAcima)
            .animation(DS.curvaRapida, value: temAbaixo)
    }
}

extension View {
    func indicadorDeRolagem(fundo: Color = DS.fundo) -> some View { modifier(IndicadorDeRolagem(fundo: fundo)) }
}
