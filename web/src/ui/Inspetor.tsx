import { useEffect, useState } from "react";
import { Download, Paperclip, Trash2, X } from "lucide-react";
import { mesmaLista, usar } from "../dados/armazem";
import { alternarEtiqueta, anexar, concluir, criarTarefa, definirTempo, excluirTarefa, moverTarefa, removerAnexo, salvarTarefa } from "../dados/acoes";
import { corDaLista, horarioDe, indice, notasVisiveis, tempoDe } from "../dados/consultas";
import { lerArquivo } from "../dados/espelho";
import { supabase } from "../dados/nuvem";
import { duracaoCurta, hojeISO, lerDuracao, relogio, rotuloComAtraso } from "../dados/util";
import { BotaoTempo, Circulo, LinhaTarefa, SeletorData } from "./comuns";
import { selecionar } from "./rota";

async function abrirAnexo(caminho: string, nome: string) {
  // Primeiro o que está no aparelho (offline); senão uma URL assinada do bucket privado.
  const blob = await lerArquivo(`anexos/${caminho}`);
  let url: string | null = blob ? URL.createObjectURL(blob) : null;
  if (!url) {
    const { data } = await (await supabase()).storage.from("anexos").createSignedUrl(caminho, 60, { download: nome });
    url = data?.signedUrl ?? null;
  }
  if (url) window.open(url, "_blank", "noopener");
}

export function Inspetor({ id }: { id: string }) {
  const t = usar((e) => e.tarefas[id] ?? null);
  const listas = usar((e) => e.listas);
  const cor = usar((e) => (t ? corDaLista(e, t.listaId) : ""));
  const filhas = usar((e) => indice(e).filhas.get(id) ?? [], mesmaLista);
  const anexos = usar((e) => e.anexos.filter((a) => a.tarefaId === id), mesmaLista);
  const etiquetas = usar((e) => e.etiquetas);
  const minhas = usar((e) => e.etiquetasDaTarefa[id] ?? []);
  const ativo = usar((e) => e.cronometro.tarefaId === id);
  const [, tique] = useState(0);
  const segundos = usar((e) => tempoDe(e, id));
  const [data, setData] = useState(false);
  const [sub, setSub] = useState("");

  useEffect(() => {
    if (!ativo) return;
    const i = setInterval(() => tique((n) => n + 1), 1000);
    return () => clearInterval(i);
  }, [ativo]);
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === "Escape" && selecionar(null);
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, []);

  if (!t) return null;
  const horario = horarioDe(t);
  return (
    <aside className="inspetor" aria-label="Detalhes da tarefa" onDragOver={(e) => e.preventDefault()} onDrop={(e) => { e.preventDefault(); for (const f of Array.from(e.dataTransfer.files)) void anexar(id, f); }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "12px 16px", borderBottom: "1px solid var(--borda)" }}>
        <Circulo feito={t.concluida} cor={cor} aoClicar={() => concluir(id, !t.concluida)} />
        <select className="campo t-sm" style={{ flex: 1 }} value={t.listaId} onChange={(e) => moverTarefa(id, e.target.value)}>
          {listas.map((l) => <option key={l.id} value={l.id}>{l.titulo}</option>)}
        </select>
        <button className="icone-botao" aria-label="Excluir" onClick={() => { excluirTarefa(id); selecionar(null); }}><Trash2 size={15} /></button>
        <button className="icone-botao" aria-label="Fechar" onClick={() => selecionar(null)}><X size={16} /></button>
      </div>
      <div style={{ flex: 1, overflow: "auto", padding: 16, display: "flex", flexDirection: "column", gap: 16 }}>
        <textarea key={id + "t"} className="campo-limpo display d-titulo" rows={1} defaultValue={t.titulo} style={{ resize: "none", fieldSizing: "content" } as never}
          onBlur={(e) => salvarTarefa(id, { titulo: e.target.value })} onKeyDown={(e) => e.key === "Enter" && (e.preventDefault(), e.currentTarget.blur())} />
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          <button className="chip" aria-pressed={!!t.prazo} onClick={() => setData(!data)}>{t.prazo ? rotuloComAtraso(t.prazo, hojeISO()) : "Sem data"}</button>
          {t.prazo && (
            <input type="time" className="campo t-sm" style={{ width: 110 }} defaultValue={horario ?? ""} key={id + "h"} onChange={(e) => salvarTarefa(id, { horario: e.target.value || null })} />
          )}
        </div>
        {data && <SeletorData valor={t.prazo} aoEscolher={(d) => { salvarTarefa(id, { prazo: d }); setData(false); }} />}
        <textarea key={id + "n"} className="campo" rows={4} placeholder="Notas" defaultValue={notasVisiveis(t)} style={{ resize: "vertical" }}
          onBlur={(e) => salvarTarefa(id, { notasVisiveis: e.target.value })} />

        <div>
          <div className="rotulo" style={{ marginBottom: 6 }}>Subtarefas</div>
          <div className="cartao-linhas">
            {filhas.map((f) => <LinhaTarefa key={f.id} t={f} mostrarData={false} mostrarLista={false} compacta />)}
            <input className="campo-limpo t-md" style={{ padding: "8px 12px" }} placeholder="+ Subtarefa" value={sub} onChange={(e) => setSub(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && sub.trim()) { criarTarefa({ titulo: sub, listaId: t.listaId, mae: t.mae ?? id, silencioso: true }); setSub(""); } }} />
          </div>
        </div>

        {etiquetas.length > 0 && (
          <div>
            <div className="rotulo" style={{ marginBottom: 6 }}>Etiquetas</div>
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              {etiquetas.map((g) => <button key={g.id} className="chip" aria-pressed={minhas.includes(g.id)} style={{ color: g.cor }} onClick={() => alternarEtiqueta(id, g.id)}>#{g.nome}</button>)}
            </div>
          </div>
        )}

        <div>
          <div className="rotulo" style={{ marginBottom: 6 }}>Tempo</div>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <BotaoTempo id={id} />
            <span className="t-lg numeros p-semi">{ativo ? relogio(segundos) : duracaoCurta(segundos) || "0 min"}</span>
            <button className="botao b-fantasma t-xs" onClick={() => { const v = prompt("Tempo total (ex.: 1h 20min)", duracaoCurta(segundos)); const s = v != null ? lerDuracao(v) : null; if (s != null) definirTempo(id, s); }}>Ajustar</button>
          </div>
        </div>

        <div>
          <div className="rotulo" style={{ marginBottom: 6, display: "flex", justifyContent: "space-between" }}>
            Anexos
            <label className="botao b-fantasma t-xs" style={{ cursor: "pointer" }}><Paperclip size={12} /> Anexar<input type="file" multiple hidden onChange={(e) => { for (const f of Array.from(e.target.files ?? [])) void anexar(id, f); e.target.value = ""; }} /></label>
          </div>
          <div className="cartao-linhas">
            {anexos.map((a) => (
              <div key={a.id} className="linha-tarefa compacta">
                <Paperclip size={13} />
                <span className="t-sm uma-linha" style={{ flex: 1 }}>{a.nome}</span>
                <span className="t-xs c3">{a.pendente ? "subindo…" : `${Math.max(1, Math.round(a.tamanho / 1024))} KB`}</span>
                <button className="icone-botao" aria-label="Abrir" onClick={() => void abrirAnexo(a.caminho, a.nome)}><Download size={13} /></button>
                <button className="icone-botao" aria-label="Remover" onClick={() => removerAnexo(a.id)}><Trash2 size={13} /></button>
              </div>
            ))}
            {!anexos.length && <div className="t-xs c3" style={{ padding: "8px 12px" }}>Arraste arquivos aqui ou use Anexar.</div>}
          </div>
        </div>
      </div>
    </aside>
  );
}
