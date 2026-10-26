import Observation
import SwiftUI

/// Folha (modal): um componente para todos os diálogos do app.
/// Véu preto a 40%, caixa centrada com raio de cartão, cabeçalho com título display e X,
/// corpo e rodapé opcional. Esc e clique no véu fecham.
@MainActor @Observable
final class Folhas {
    struct Atual: Identifiable {
        let id = UUID()
        let titulo: String
        var descricao: String?
        var largura: CGFloat = 400
        let conteudo: AnyView
    }

    private(set) var atual: Atual?

    func abrir<V: View>(_ titulo: String, descricao: String? = nil, largura: CGFloat = 400, @ViewBuilder _ conteudo: () -> V) {
        atual = Atual(titulo: titulo, descricao: descricao, largura: largura, conteudo: AnyView(conteudo()))
    }

    func fechar() {
        atual = nil
    }

    /// Confirmação padrão para tudo que remove algo.
    func confirmar(_ titulo: String, mensagem: String, botao: String = "Excluir", acao: @escaping () -> Void) {
        abrir(titulo, largura: 360) {
            Confirmacao(mensagem: mensagem, botao: botao, acao: acao)
        }
    }
}

/// Conteúdo da folha de confirmação.
struct Confirmacao: View {
    @Environment(Folhas.self) private var folhas
    let mensagem: String
    let botao: String
    let acao: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e4) {
            Text(mensagem).txt(.sm).foregroundStyle(DS.texto2).fixedSize(horizontal: false, vertical: true)
            RodapeFolha {
                Spacer()
                Button("Cancelar") { folhas.fechar() }.buttonStyle(.superficie).keyboardShortcut(.cancelAction)
                Button(botao) {
                    withAnimation(DS.curvaSaida) { folhas.fechar() }
                    acao()
                }
                .buttonStyle(.perigo)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Aviso "excluído — Desfazer" no rodapé da janela (some em 3 s).
struct ToastDesfazer: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        ZStack {
            if let aviso = store.aviso {
                HStack(spacing: DS.e3) {
                    Image(systemName: "trash").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.texto3)
                    Text(aviso.texto).txt(.sm, .medium).foregroundStyle(DS.texto).lineLimit(1)
                    Button("Desfazer") { withAnimation(DS.curva) { store.desfazerAviso() } }
                        .buttonStyle(Botao(variante: .fantasma))
                        .foregroundStyle(DS.acentoTexto)
                }
                .padding(.leading, DS.e4)
                .padding(.trailing, DS.e1)
                .padding(.vertical, DS.e1)
                .background(DS.superficie, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.borda))
                .sombraAlta()
                .id(aviso.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.curva, value: store.aviso?.id)
    }
}

/// Hospeda as folhas por cima de uma janela inteira.
struct HospedeDeFolhas: ViewModifier {
    @Bindable var folhas: Folhas

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                ZStack {
                    if let atual = folhas.atual {
                        DS.veuModal
                            .ignoresSafeArea()
                            .onTapGesture { withAnimation(DS.curvaSaida) { folhas.fechar() } }
                            .transition(.opacity)

                        CaixaDaFolha(atual: atual, alturaMaxima: geo.size.height - DS.e4 * 2) {
                            withAnimation(DS.curvaSaida) { folhas.fechar() }
                        }
                            .id(atual.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 8)),
                                removal: .opacity.combined(with: .scale(scale: 0.98))
                            ))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(DS.curva, value: folhas.atual?.id)
                }
            }
            .environment(folhas)
    }
}

extension View {
    func hospedaFolhas(_ folhas: Folhas) -> some View { modifier(HospedeDeFolhas(folhas: folhas)) }
}

private struct CaixaDaFolha: View {
    let atual: Folhas.Atual
    /// A folha nunca passa da janela: acima disso, o corpo rola.
    let alturaMaxima: CGFloat
    let fechar: () -> Void
    @State private var alturaCorpo: CGFloat = 200
    @State private var alturaCabecalho: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.e3) {
                VStack(alignment: .leading, spacing: DS.e1) {
                    Text(atual.titulo).display(.lg).foregroundStyle(DS.texto)
                    if let descricao = atual.descricao {
                        Text(descricao).txt(.sm).foregroundStyle(DS.texto3)
                    }
                }
                Spacer()
                BotaoIcone(simbolo: "xmark", rotulo: "Fechar", tamanho: 28, tamanhoIcone: 12, acao: fechar)
                    .padding(.top, -2)
                    .padding(.trailing, -4)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, DS.e5)
            .padding(.vertical, DS.e4)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.borda).frame(height: 1) }
            .background(GeometryReader { g in Color.clear.onAppear { alturaCabecalho = g.size.height } })

            ScrollView {
                atual.conteudo
                    .padding(.horizontal, DS.e5)
                    .padding(.vertical, DS.e4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { alturaCorpo = g.size.height }
                            .onChange(of: g.size.height) { _, h in alturaCorpo = h }
                    })
            }
            .scrollIndicators(.automatic)
            .indicadorDeRolagem(fundo: DS.superficie)
            .frame(height: max(80, min(alturaCorpo, alturaMaxima - alturaCabecalho)))
        }
        .frame(maxWidth: atual.largura)
        .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
        .sombraAlta()
        .padding(DS.e4)
    }
}

/// Rodapé de folha: linha de cima e ações à direita.
struct RodapeFolha<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: DS.e4) {
            Rectangle().fill(DS.borda).frame(height: 1).padding(.horizontal, -DS.e5)
            HStack(spacing: DS.e2) { content }
        }
        .padding(.top, DS.e2)
    }
}

// MARK: Calendário do mês (componente)

/// Grade de um mês: semana começando no primeiro dia do calendário do sistema,
/// hoje em acento, dia escolhido preenchido, pontinho nos dias com algo.
struct CalendarioMes: View {
    @Binding var mes: Date
    var selecionado: Date?
    var hoje: Date
    var ocupado: (Date) -> Bool = { _ in false }
    let escolher: (Date) -> Void

    @State private var direcao: CGFloat = 1
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: DS.e3) {
            HStack {
                Text(mes.formatted(.dateTime.month(.wide).year()).primeiraMaiuscula)
                    .display(.lg)
                    .foregroundStyle(DS.texto)
                    .id(mes)
                    .transition(.asymmetric(insertion: .offset(x: 28 * direcao).combined(with: .opacity),
                                            removal: .opacity))
                Spacer()
                BotaoIcone(simbolo: "chevron.left", rotulo: "Voltar um mês", tamanho: 28, tamanhoIcone: 12) { mudar(-1) }
                BotaoIcone(simbolo: "chevron.right", rotulo: "Avançar um mês", tamanho: 28, tamanhoIcone: 12) { mudar(1) }
            }

            HStack(spacing: 0) {
                ForEach(simbolosSemana, id: \.self) { s in
                    Text(s).rotulo().frame(maxWidth: .infinity)
                }
            }

            let dias = gradeDias
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { semana in
                    HStack(spacing: 2) {
                        ForEach(dias[(semana * 7)..<(semana * 7 + 7)], id: \.self) { dia in
                            celula(dia)
                        }
                    }
                }
            }
            .id(mes)
            .transition(.asymmetric(insertion: .offset(x: 28 * direcao).combined(with: .opacity), removal: .opacity))
        }
        .animation(DS.curva, value: mes)
    }

    private func celula(_ dia: Date) -> some View {
        let noMes = cal.isDate(dia, equalTo: mes, toGranularity: .month)
        let escolhido = selecionado.map { cal.isDate($0, inSameDayAs: dia) } ?? false
        let ehHoje = dia == hoje
        return Button { escolher(dia) } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: dia))")
                    .txt(.sm, escolhido || ehHoje ? .semibold : .regular)
                    .foregroundStyle(escolhido ? DS.acentoSolidoTexto : (ehHoje ? DS.acentoTexto : (noMes ? DS.texto : DS.texto3.opacity(0.6))))
                Circle()
                    .fill(escolhido ? DS.acentoSolidoTexto : DS.acentoTexto)
                    .frame(width: 4, height: 4)
                    .opacity(ocupado(dia) ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                .fill(escolhido ? DS.acentoSolido : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(Pressionavel(raio: DS.raioM, escala: 0.94))
    }

    private func mudar(_ valor: Int) {
        direcao = CGFloat(valor)
        mes = cal.date(byAdding: .month, value: valor, to: mes) ?? mes
    }

    private var simbolosSemana: [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        let i = cal.firstWeekday - 1
        return Array(s[i...] + s[..<i])
    }

    private var gradeDias: [Date] {
        let inicioMes = cal.dateInterval(of: .month, for: mes)?.start ?? mes
        let weekday = cal.component(.weekday, from: inicioMes)
        let antes = (weekday - cal.firstWeekday + 7) % 7
        let inicio = cal.adding(days: -antes, to: inicioMes)
        return (0..<42).map { cal.adding(days: $0, to: inicio) }
    }
}

/// Seletor de data (folha): atalhos + calendário do mês.
struct SeletorDeData: View {
    @Environment(TaskStore.self) private var store
    @Environment(Folhas.self) private var folhas
    let inicial: Date?
    let escolher: (Date?) -> Void
    @State private var mes: Date

    init(inicial: Date?, escolher: @escaping (Date?) -> Void) {
        self.inicial = inicial
        self.escolher = escolher
        let base = inicial ?? Calendar.current.startOfDay(for: .now)
        _mes = State(initialValue: Calendar.current.dateInterval(of: .month, for: base)?.start ?? base)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.e4) {
            HStack(spacing: DS.e2) {
                atalho("Hoje", 0, "sun.max")
                atalho("Amanhã", 1, "sunrise")
            }
            CalendarioMes(mes: $mes, selecionado: inicial, hoje: store.today,
                          ocupado: { !store.tasks(on: $0).isEmpty }) { dia in
                concluir(dia)
            }
            RodapeFolha {
                Button("Sem data") { concluir(nil) }.buttonStyle(.fantasma)
                Spacer()
                Button("Cancelar") { folhas.fechar() }.buttonStyle(.superficie)
            }
        }
    }

    private func atalho(_ rotulo: String, _ dias: Int, _ icone: String) -> some View {
        let dia = Calendar.current.adding(days: dias, to: store.today)
        let ativo = inicial == dia
        return Button { concluir(dia) } label: {
            VStack(spacing: DS.e1) {
                Image(systemName: icone).font(.system(size: 14, weight: .medium))
                Text(rotulo).txt(.xs, .semibold)
            }
            .foregroundStyle(ativo ? DS.acentoSolidoTexto : DS.texto)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: DS.raioM, style: .continuous)
                .fill(ativo ? DS.acentoSolido : DS.superficie2))
        }
        .buttonStyle(Pressionavel(raio: DS.raioM))
    }

    private func concluir(_ dia: Date?) {
        escolher(dia)
        withAnimation(DS.curvaSaida) { folhas.fechar() }
    }
}
