import SwiftUI

/// Botão discreto para trocar a energia (no canto do título do Hoje).
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
