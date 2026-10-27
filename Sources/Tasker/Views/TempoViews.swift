import SwiftUI

/// Na linha da tarefa: rodando, uma pílula com o tempo correndo (clique pausa);
/// parada, um play que só aparece no hover (`visivel`).
struct ControleDeTempo: View {
    @Environment(TaskStore.self) private var store
    let taskID: String
    var visivel: Bool

    var body: some View {
        if store.cronometroAtivo == taskID {
            Button {
                withAnimation(DS.curvaRapida) { store.alternarCronometro(taskID) }
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { contexto in
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill").font(.system(size: 8, weight: .bold))
                        Text(Duracao.relogio(store.tempo(de: taskID, agora: contexto.date)))
                            .txt(.xs, .semibold)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .foregroundStyle(DS.acentoSolidoTexto)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(DS.acentoSolido))
                .contentShape(Capsule())
                .fixedSize()
            }
            .buttonStyle(SoAfunda(escala: 0.92))
            .layoutPriority(2)
            .help("Pausar o cronômetro")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else if visivel {
            BotaoIcone(simbolo: "play.fill", rotulo: tempoGuardado.map { "Continuar o cronômetro (\($0))" } ?? "Começar a cronometrar",
                       tamanho: 22, tamanhoIcone: 9) {
                withAnimation(DS.curvaRapida) { store.alternarCronometro(taskID) }
            }
            .transition(.opacity)
        }
    }

    private var tempoGuardado: String? {
        let t = store.tempo(de: taskID)
        return t > 0 ? Duracao.curto(t) : nil
    }
}

/// Nos detalhes: play/pausa e o total, que dá para digitar ("20m", "1h20", "1:20").
struct CampoTempo: View {
    @Environment(TaskStore.self) private var store
    let taskID: String

    @State private var editando = false
    @State private var texto = ""
    @State private var erro = false
    @FocusState private var foco: Bool

    var body: some View {
        let rodando = store.cronometroAtivo == taskID
        HStack(spacing: DS.e2) {
            Button {
                withAnimation(DS.curvaRapida) { store.alternarCronometro(taskID) }
            } label: {
                Image(systemName: rodando ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(rodando ? DS.acentoSolidoTexto : DS.texto2)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(rodando ? DS.acentoSolido : DS.superficie2))
                    .contentShape(Circle())
            }
            .buttonStyle(SoAfunda(escala: 0.88))
            .help(rodando ? "Pausar o cronômetro" : "Começar a cronometrar")

            if editando {
                TextField("ex.: 20m, 1h20, 1:20", text: $texto)
                    .textFieldStyle(.plain)
                    .txt(.sm, .medium)
                    .monospacedDigit()
                    .frame(maxWidth: 140)
                    .focused($foco)
                    .onSubmit(salvar)
                    .onExitCommand { editando = false; erro = false }
                    .onChange(of: foco) { _, focado in if !focado { salvar() } }
                    .padding(.horizontal, DS.e2)
                    .frame(height: 26)
                    .background(DS.superficie2, in: RoundedRectangle(cornerRadius: DS.raioP, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.raioP, style: .continuous)
                        .strokeBorder(erro ? DS.perigoTexto : .clear))
                    .help("Digite quanto tempo levou: 20 (minutos), 20m, 1h20, 1:20 ou 1:20:30. Enter salva.")
            } else {
                Button {
                    texto = Duracao.relogio(store.tempo(de: taskID))
                    editando = true
                    DispatchQueue.main.async { foco = true }
                } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { contexto in
                        let t = store.tempo(de: taskID, agora: contexto.date)
                        Text(t > 0 || rodando ? Duracao.relogio(t) : "Sem tempo registrado")
                            .txt(.sm, t > 0 || rodando ? .semibold : .regular)
                            .monospacedDigit()
                            .foregroundStyle(rodando ? DS.acento : (t > 0 ? DS.texto : DS.texto3))
                    }
                    .padding(.horizontal, DS.e2)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Pressionavel(raio: DS.raioP, escala: 0.98))
                .help("Clique para digitar o tempo (ex.: 20m)")
            }
            if erro {
                Text("Não entendi").txt(.xs).foregroundStyle(DS.perigoTexto)
            }
        }
        .animation(DS.curvaRapida, value: editando)
    }

    private func salvar() {
        guard editando else { return }
        if texto.trimmingCharacters(in: .whitespaces).isEmpty {
            store.definirTempo(taskID, segundos: 0)
        } else if let s = Duracao.ler(texto) {
            store.definirTempo(taskID, segundos: s)
        } else {
            erro = true
            return
        }
        erro = false
        editando = false
    }
}
