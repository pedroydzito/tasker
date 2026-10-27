import Charts
import SwiftUI

/// Resumo do período no topo de Concluídas: tarefas concluídas por dia (na cor de cada lista),
/// tempo por lista e as tarefas onde o tempo foi.
struct ResumoConcluidas: View {
    @Environment(TaskStore.self) private var store
    @AppStorage("concluidas.periodo") private var periodo = Periodo.semana

    enum Periodo: String, Hashable {
        case semana, mes, ano
        var titulo: String {
            switch self {
            case .semana: "7 dias"
            case .mes: "30 dias"
            case .ano: "12 meses"
            }
        }
    }

    private struct Barra: Identifiable {
        let inicio: Date
        let lista: String
        let quantidade: Int
        var id: String { "\(inicio.timeIntervalSince1970)-\(lista)" }
    }

    private struct TempoLista: Identifiable {
        let listID: String
        let nome: String
        let segundos: TimeInterval
        var id: String { listID }
    }

    var body: some View {
        let cal = Calendar.current
        let (inicio, unidade) = intervalo(cal)
        let feitas = store.completedTasks.filter { ($0.completedDate ?? .distantPast) >= inicio }
        let barras = agrupar(feitas, unidade: unidade, cal: cal)
        let nomes = store.lists.map { store.displayName($0.id) }
        let cores = store.lists.map { store.color(forList: $0.id) }

        // Tempo: tarefas concluídas no período + as que ainda estão abertas (o tempo delas já foi gasto).
        let abertas = store.tasks.values.filter { !$0.isCompleted }
        let comTempo = (feitas + abertas).map { ($0, store.tempo(de: $0.id)) }.filter { $0.1 > 0 }
        let porLista = Dictionary(grouping: comTempo, by: { $0.0.listID })
            .map { TempoLista(listID: $0.key, nome: store.displayName($0.key), segundos: $0.value.reduce(0) { $0 + $1.1 }) }
            .sorted { $0.segundos > $1.segundos }
        let total = porLista.reduce(0) { $0 + $1.segundos }
        let topo = comTempo.sorted { $0.1 > $1.1 }.prefix(6)

        VStack(alignment: .leading, spacing: DS.e5) {
            HStack(alignment: .firstTextBaseline) {
                numero("\(feitas.count)", feitas.count == 1 ? "concluída" : "concluídas")
                numero(total > 0 ? Duracao.curto(total) : "—", "de tempo registrado")
                Spacer()
                Segmentado(selecao: $periodo, opcoes: [(.semana, "7 dias"), (.mes, "30 dias"), (.ano, "12 meses")])
            }

            if barras.isEmpty {
                Text("Nenhuma tarefa concluída nos últimos \(periodo.titulo).")
                    .txt(.sm).foregroundStyle(DS.texto3)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(barras) { b in
                    BarMark(x: .value("Quando", b.inicio, unit: unidade),
                            y: .value("Tarefas", b.quantidade))
                        .foregroundStyle(by: .value("Lista", b.lista))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(domain: nomes, range: cores)
                .chartXScale(domain: inicio...cal.date(byAdding: unidade, value: 1, to: store.today)!)
                .chartXAxis {
                    AxisMarks(values: .stride(by: unidade, count: periodo == .mes ? 5 : 1)) { valor in
                        AxisGridLine().foregroundStyle(DS.borda)
                        AxisValueLabel(format: periodo == .ano ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(DS.borda)
                        AxisValueLabel()
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: DS.e3)
                .frame(height: 190)
                .animation(DS.curva, value: periodo)
            }

            if !porLista.isEmpty {
                Rectangle().fill(DS.borda).frame(height: 1)
                HStack(alignment: .top, spacing: DS.e6) {
                    VStack(alignment: .leading, spacing: DS.e3) {
                        Text("Tempo por lista").rotulo()
                        Chart(porLista) { l in
                            BarMark(x: .value("Horas", l.segundos / 3600), y: .value("Lista", l.nome))
                                .foregroundStyle(store.color(forList: l.listID))
                                .cornerRadius(3)
                                .annotation(position: .trailing) {
                                    Text(Duracao.curto(l.segundos)).txt(.xs, .semibold).foregroundStyle(DS.texto2)
                                }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks { _ in AxisValueLabel().font(.caption) }
                        }
                        .frame(height: CGFloat(max(1, porLista.count)) * 30)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: DS.e2) {
                        Text("Onde foi o tempo").rotulo()
                        ForEach(Array(topo), id: \.0.id) { tarefa, segundos in
                            HStack(spacing: DS.e2) {
                                Circle().fill(store.color(forList: tarefa.listID)).frame(width: 7, height: 7)
                                Text(tarefa.displayTitle).txt(.sm).foregroundStyle(DS.texto).lineLimit(1)
                                    .strikethrough(tarefa.isCompleted, color: DS.texto3)
                                Spacer(minLength: DS.e2)
                                Text(Duracao.curto(segundos)).txt(.sm, .semibold).monospacedDigit().foregroundStyle(DS.texto2)
                            }
                            .help(tarefa.isCompleted ? "Concluída" : "Em aberto")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Text("Tempo das tarefas concluídas nos últimos \(periodo.titulo) e das que ainda estão abertas.")
                    .txt(.xs).foregroundStyle(DS.texto3)
            }
        }
        .padding(DS.e5)
        .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
    }

    private func numero(_ valor: String, _ rotulo: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor).display(.display2).foregroundStyle(DS.texto).monospacedDigit()
            Text(rotulo).txt(.xs).foregroundStyle(DS.texto3)
        }
        .padding(.trailing, DS.e6)
    }

    private func intervalo(_ cal: Calendar) -> (Date, Calendar.Component) {
        switch periodo {
        case .semana: (cal.adding(days: -6, to: store.today), .day)
        case .mes: (cal.adding(days: -29, to: store.today), .day)
        case .ano:
            (cal.date(byAdding: .month, value: -11, to: cal.dateInterval(of: .month, for: store.today)?.start ?? store.today)
                ?? store.today, .month)
        }
    }

    private func agrupar(_ tarefas: [TaskItem], unidade: Calendar.Component, cal: Calendar) -> [Barra] {
        var contagem: [Date: [String: Int]] = [:]
        for t in tarefas {
            guard let data = t.completedDate, let inicio = cal.dateInterval(of: unidade, for: data)?.start else { continue }
            contagem[inicio, default: [:]][store.displayName(t.listID), default: 0] += 1
        }
        return contagem.flatMap { dia, listas in
            listas.map { Barra(inicio: dia, lista: $0.key, quantidade: $0.value) }
        }
        .sorted { $0.inicio < $1.inicio }
    }
}
