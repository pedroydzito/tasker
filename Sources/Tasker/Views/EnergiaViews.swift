import SwiftUI

/// "Como está sua energia?" — com pouca, o Hoje mostra uma coisa por vez, sem atrasadas e sem contagem.
struct SeletorDeEnergia: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        @Bindable var prefs = store.prefs
        HStack(spacing: DS.e4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Como está sua energia?").txt(.sm, .semibold).foregroundStyle(DS.texto)
                Text(prefs.energiaBaixa ? "Uma coisa de cada vez, no seu ritmo." : "Com pouca energia, o Hoje mostra uma coisa por vez.")
                    .txt(.xs).foregroundStyle(DS.texto3)
            }
            Spacer(minLength: DS.e2)
            Segmentado(selecao: $prefs.energiaBaixa, opcoes: [(false, "Tenho energia"), (true, "Tô sem energia")])
        }
        .padding(DS.e4)
        .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
        .animation(DS.curva, value: prefs.energiaBaixa)
    }
}

/// Botão do menu da barra para trocar a energia (o seletor inteiro não cabe no menu).
struct BotaoEnergia: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        let baixa = store.prefs.energiaBaixa
        BotaoIcone(simbolo: baixa ? "battery.25percent" : "battery.100percent",
                   rotulo: baixa ? "Tô sem energia — clique para ver tudo" : "Tenho energia — clique se estiver sem energia",
                   ativo: baixa) {
            withAnimation(DS.curva) { store.prefs.energiaBaixa.toggle() }
        }
    }
}

/// Com pouca energia: só a próxima tarefa, grande, com "Feito" e "Outra". Sem atraso em vermelho e sem números.
struct UmaCoisaPorVez: View {
    @Environment(TaskStore.self) private var store
    var compacto = false
    @State private var pulados: [String] = []

    var body: some View {
        // Hoje primeiro; atrasadas depois (sem destacar que estão atrasadas).
        let candidatas = (store.todayTasks + store.overdueTasks).filter { !$0.isLocal }
        let fila = candidatas.filter { !pulados.contains($0.id) } + candidatas.filter { pulados.contains($0.id) }
        VStack(alignment: .leading, spacing: compacto ? DS.e3 : DS.e4) {
            if let tarefa = fila.first {
                Text("Agora, só isto:").rotulo()
                VStack(alignment: .leading, spacing: DS.e3) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.e3) {
                        CheckCircle(color: store.color(forList: tarefa.listID), checked: false, size: compacto ? 20 : 24) {
                            concluir(tarefa)
                        }
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                        Text(tarefa.displayTitle)
                            .display(compacto ? .lg : .titulo)
                            .foregroundStyle(DS.texto)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let notas = tarefa.notasVisiveis.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notas.isEmpty {
                        Text(notas).txt(.sm).foregroundStyle(DS.texto2).lineLimit(compacto ? 3 : 6)
                    }
                    HStack(spacing: DS.e2) {
                        ListChip(listID: tarefa.listID)
                        if let hora = tarefa.horario { Chip(hora) { Image(systemName: "clock").font(.system(size: 10, weight: .semibold)) } }
                        Spacer()
                        ControleDeTempo(taskID: tarefa.id, visivel: true)
                    }
                    HStack(spacing: DS.e2) {
                        Button { concluir(tarefa) } label: {
                            Label("Feito", systemImage: "checkmark")
                        }
                        .buttonStyle(Botao(variante: .primario, tamanho: .m))
                        .help("Concluir e mostrar a próxima")
                        if fila.count > 1 {
                            Button {
                                withAnimation(DS.curva) { pulados.removeAll { $0 == tarefa.id }; pulados.append(tarefa.id) }
                            } label: {
                                Label("Outra", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(Botao(variante: .superficie, tamanho: .m))
                            .help("Mostrar outra coisa (esta volta depois)")
                        }
                    }
                }
                .padding(compacto ? DS.e4 : DS.e5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.superficie, in: RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.raioCartao, style: .continuous).strokeBorder(DS.borda))
                .id(tarefa.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
            } else {
                EstadoVazio(icone: "leaf", titulo: "Nada para agora",
                            descricao: "Pode descansar. Quando tiver energia, o resto continua aqui.")
                    .padding(.top, DS.e4)
            }
        }
        .animation(DS.curva, value: fila.first?.id)
    }

    private func concluir(_ tarefa: TaskItem) {
        withAnimation(DS.curva) {
            pulados.removeAll { $0 == tarefa.id }
            store.setCompleted(tarefa, true)
        }
    }
}
