import { CriadorDeEtiqueta, folhas } from "./folhas";
import { useEffect, useRef, useState } from "react";
import { ArrowUpRight, CornerLeftUp, Download, Hash, Paperclip, Pause, Play, Plus, Trash2, X } from "lucide-react";
import { mesmaLista, usar } from "../dados/armazem";
import { anexar, concluir, criarTarefa, definirEtiquetas, definirTempo, excluirTarefa, alternarCronometro, moverTarefa, removerAnexo, salvarTarefa } from "../dados/acoes";
import { corDaLista, etiquetasOrdenadas, horarioDe, indice, notasVisiveis, tempoDe, tituloDe } from "../dados/consultas";
import { lerArquivo } from "../dados/espelho";
import { supabase } from "../dados/nuvem";
import { hojeISO, lerDuracao, relogio, rotuloComAtraso } from "../dados/util";
import { Chip, ChipLista, Circulo, DropdownListas, SeletorData } from "./comuns";
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

interface Rascunho {
  titulo: string;
  notas: string;
  listaId: string;
  prazo: string | null;
  horario: string | null;
  etiquetas: string[];
}
const igual = (a: Rascunho, b: Rascunho) => JSON.stringify(a) === JSON.stringify(b);

/** Play/pausa e o total, que dá para digitar (CampoTempo). */
function CampoTempo({ id }: { id: string }) {
  const rodando = usar((e) => e.cronometro.tarefaId === id);
  const [, tique] = useState(0);
  const segundos = usar((e) => tempoDe(e, id));
  const [editando, setEditando] = useState(false);
  const [erro, setErro] = useState(false);
  useEffect(() => {
    if (!rodando) return;
    const i = setInterval(() => tique((n) => n + 1), 1000);
    return () => clearInterval(i);
  }, [rodando]);
  const salvar = (texto: string) => {
    if (!texto.trim()) definirTempo(id, 0);
    else {
      const s = lerDuracao(texto);
      if (s == null) return setErro(true);
      definirTempo(id, s);
    }
    setErro(false);
    setEditando(false);
  };
  return (
    <div style={{ display: "flex", alignItems: "center", gap: "var(--e2)" }}>
      <button className="afunda" title={rodando ? "Pausar o cronômetro" : "Começar a cronometrar"} onClick={() => alternarCronometro(id)}
        style={{ width: 26, height: 26, borderRadius: 99, display: "inline-flex", alignItems: "center", justifyContent: "center", background: rodando ? "var(--acento)" : "var(--superficie2)", color: rodando ? "#fff" : "var(--texto2)" }}>
        {rodando ? <Pause size={10} fill="currentColor" /> : <Play size={10} fill="currentColor" />}
      </button>
      {editando ? (
        <input autoFocus className="campo-hora numeros" style={{ width: 140, height: 26, outline: erro ? "1px solid var(--perigo-texto)" : undefined }} placeholder="ex.: 20m, 1h20, 1:20"
          defaultValue={relogio(segundos)} title="Digite quanto tempo levou: 20 (minutos), 20m, 1h20, 1:20 ou 1:20:30. Enter salva."
          onKeyDown={(e) => { if (e.key === "Enter") salvar(e.currentTarget.value); if (e.key === "Escape") { setEditando(false); setErro(false); } }}
          onBlur={(e) => salvar(e.target.value)} />
      ) : (
        <button className="veu numeros" style={{ height: 26, padding: "0 8px", borderRadius: "var(--raio-p)", fontSize: "var(--t-sm)", fontWeight: segundos > 0 || rodando ? 600 : 400, color: rodando ? "var(--acento)" : segundos > 0 ? "var(--texto)" : "var(--texto3)" }}
          title="Clique para digitar o tempo (ex.: 20m)" onClick={() => setEditando(true)}>
          {segundos > 0 || rodando ? relogio(segundos) : "Sem tempo registrado"}
        </button>
      )}
      {erro && <span className="t-xs" style={{ color: "var(--perigo-texto)" }}>Não entendi</span>}
    </div>
  );
}

/** Subtarefas no detalhe: concluir, abrir e adicionar na hora. */
function Subtarefas({ maeId, listaId }: { maeId: string; listaId: string }) {
  const filhas = usar((e) => indice(e).filhas.get(maeId) ?? [], mesmaLista);
  const cor = usar((e) => corDaLista(e, listaId));
  const [nova, setNova] = useState("");
  const [foco, setFoco] = useState(false);
  const feitas = filhas.filter((f) => f.concluida).length;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
      {filhas.length > 0 && (
        <>
          <div style={{ display: "flex", gap: 6 }}><span className="rotulo">Subtarefas</span><span className="t-xs p-semi c3">{feitas}/{filhas.length}</span></div>
          <div style={{ height: 4, borderRadius: 9, background: "var(--superficie3)", overflow: "hidden" }}><div style={{ height: "100%", width: `${(feitas / filhas.length) * 100}%`, background: cor, transition: "width var(--normal) var(--curva)" }} /></div>
        </>
      )}
      <div style={{ display: "flex", flexDirection: "column", gap: 1, borderRadius: "var(--raio-m)", background: filhas.length ? "var(--superficie2)" : undefined }}>
        {filhas.map((f) => (
          <div key={f.id} className="linha-sub">
            <Circulo feito={f.concluida} cor={cor} aoClicar={() => concluir(f.id, !f.concluida)} />
            <button className="t-sm afunda" style={{ flex: 1, textAlign: "left", color: f.concluida ? "var(--texto3)" : "var(--texto)", textDecoration: f.concluida ? "line-through" : undefined }} onClick={() => selecionar(f.id)}>{tituloDe(f)}</button>
            <button className="icone-botao some-sem-hover" aria-label="Excluir subtarefa" onClick={() => folhas.confirmar("Excluir subtarefa", `“${tituloDe(f)}” será excluída. Dá para desfazer logo depois.`, () => excluirTarefa(f.id))}><Trash2 size={13} /></button>
          </div>
        ))}
        <div style={{ display: "flex", alignItems: "center", gap: "var(--e3)", padding: filhas.length ? "9px 12px" : "4px 0" }} title="Enter adiciona e já deixa pronto para a próxima">
          <Plus size={12} strokeWidth={2.6} style={{ width: 18, color: foco ? "var(--acento)" : "var(--texto3)" }} />
          <input className="campo-limpo t-sm" style={{ flex: 1 }} placeholder="Adicionar subtarefa" value={nova} onFocus={() => setFoco(true)} onBlur={() => setFoco(false)}
            onChange={(e) => setNova(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && nova.trim()) { criarTarefa({ titulo: nova, listaId, mae: maeId, silencioso: true }); setNova(""); } }} />
        </div>
      </div>
    </div>
  );
}

function Anexos({ id }: { id: string }) {
  const anexos = usar((e) => e.anexos.filter((a) => a.tarefaId === id), mesmaLista);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
      <div style={{ display: "flex", alignItems: "center" }}>
        <span className="rotulo" style={{ flex: 1 }}>Anexos</span>
        <label className="botao b-fantasma" style={{ cursor: "pointer" }} title="Anexar arquivos (ou arraste para cá)"><Paperclip size={13} />Anexar
          <input type="file" multiple hidden onChange={(e) => { for (const f of Array.from(e.target.files ?? [])) void anexar(id, f); e.target.value = ""; }} />
        </label>
      </div>
      {anexos.length > 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: 1, borderRadius: "var(--raio-m)", background: "var(--superficie2)" }}>
          {anexos.map((a) => (
            <div key={a.id} className="linha-sub">
              <Paperclip size={13} className="c3" style={{ width: 18 }} />
              <button className="t-sm uma-linha afunda" style={{ flex: 1, textAlign: "left" }} title="Abrir" onClick={() => void abrirAnexo(a.caminho, a.nome)}>{a.nome}</button>
              <span className="t-xs c3 numeros">{a.pendente ? "subindo…" : `${Math.max(1, Math.round(a.tamanho / 1024))} KB`}</span>
              <button className="icone-botao" style={{ width: 26, height: 26 }} aria-label="Baixar" onClick={() => void abrirAnexo(a.caminho, a.nome)}><Download size={12} /></button>
              <button className="icone-botao" style={{ width: 26, height: 26 }} aria-label="Remover anexo" onClick={() => removerAnexo(a.id)}><Trash2 size={12} /></button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export function Inspetor({ id }: { id: string }) {
  const t = usar((e) => e.tarefas[id] ?? null);
  const mae = usar((e) => (t?.mae ? e.tarefas[t.mae] ?? null : null));
  const minhas = usar((e) => e.etiquetasDaTarefa[id] ?? [], mesmaLista);
  const todas = usar((e) => etiquetasOrdenadas(e), mesmaLista);
  const cor = usar((e) => (t ? corDaLista(e, t.listaId) : "var(--texto3)"));
  const inicial = useRef<Rascunho | null>(null);
  if (t && !inicial.current) inicial.current = { titulo: t.titulo, notas: notasVisiveis(t), listaId: t.listaId, prazo: t.prazo, horario: horarioDe(t), etiquetas: minhas };
  const [original, setOriginal] = useState<Rascunho | null>(inicial.current);
  const [r, setR] = useState<Rascunho | null>(inicial.current);
  const [listasAbertas, setListasAbertas] = useState(false);
  const [dataAberta, setDataAberta] = useState(false);
  const [etiquetasAbertas, setEtiquetasAbertas] = useState(false);
  const [arrastando, setArrastando] = useState(false);
  const alterado = !!r && !!original && !igual(r, original);

  const salvar = () => {
    if (!r || !t) return;
    if (r.listaId !== t.listaId) moverTarefa(id, r.listaId);
    salvarTarefa(id, { titulo: r.titulo, notasVisiveis: r.notas, prazo: r.prazo, horario: r.prazo ? r.horario : null });
    if (r.etiquetas.join() !== minhas.join()) definirEtiquetas(id, r.etiquetas);
    setOriginal(r);
  };
  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !(e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement)) selecionar(null);
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "s") { e.preventDefault(); salvar(); }
    };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  });
  if (!t || !r) return null;
  const mudar = (p: Partial<Rascunho>) => setR({ ...r, ...p });
  const hoje = hojeISO();
  const atrasada = !!r.prazo && r.prazo < hoje;

  return (
    <aside className={"inspetor" + (arrastando ? " arrastando" : "")} aria-label="Detalhes da tarefa"
      onDragOver={(e) => { e.preventDefault(); setArrastando(true); }} onDragLeave={() => setArrastando(false)}
      onDrop={(e) => { e.preventDefault(); setArrastando(false); for (const f of Array.from(e.dataTransfer.files)) void anexar(id, f); }}>
      <div style={{ display: "flex", justifyContent: "flex-end", gap: "var(--e1)", padding: "16px 20px 12px" }}>
        {t.link && <a className="icone-botao" href={t.link} target="_blank" rel="noreferrer" title="Abrir no Google" aria-label="Abrir no Google"><ArrowUpRight size={14} /></a>}
        <button className="icone-botao" title="Excluir tarefa" aria-label="Excluir tarefa" onClick={() => folhas.confirmar("Excluir tarefa", `“${tituloDe(t)}” será excluída. Dá para desfazer logo depois.`, () => { excluirTarefa(id); selecionar(null); })}><Trash2 size={14} /></button>
        <button className="icone-botao" title="Fechar painel" aria-label="Fechar painel" onClick={() => selecionar(null)}><X size={14} /></button>
      </div>
      <div style={{ flex: 1, overflow: "auto", padding: "12px 24px", display: "flex", flexDirection: "column", gap: "var(--e6)", scrollbarWidth: "none" }}>
        <div style={{ display: "flex", flexDirection: "column", gap: "var(--e3)" }}>
          {mae && (
            <button className="afunda t-xs p-medio c3" style={{ display: "inline-flex", alignItems: "center", gap: 4, alignSelf: "flex-start" }} title="Abrir a tarefa-mãe" onClick={() => selecionar(mae.id)}>
              <CornerLeftUp size={10} strokeWidth={2.6} />Subtarefa de {tituloDe(mae)}
            </button>
          )}
          <div style={{ display: "flex", alignItems: "flex-start", gap: "var(--e3)" }}>
            <span style={{ marginTop: 3 }}><Circulo feito={t.concluida} cor={cor} tamanho={22} aoClicar={() => concluir(id, !t.concluida)} /></span>
            <textarea className="campo-limpo display d-titulo" rows={1} value={r.titulo} placeholder="Título" onChange={(e) => mudar({ titulo: e.target.value })}
              style={{ flex: 1, resize: "none", fieldSizing: "content", color: t.concluida ? "var(--texto3)" : undefined, textDecoration: t.concluida ? "line-through" : undefined } as React.CSSProperties} />
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
            <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--e2)", alignItems: "center" }}>
              <button className="afunda" title="Trocar a lista" onClick={() => { setListasAbertas(!listasAbertas); setDataAberta(false); }}><ChipLista listaId={r.listaId} comSeta aberta={listasAbertas} /></button>
              <button className="afunda" onClick={() => { setDataAberta(!dataAberta); setListasAbertas(false); }}>
                <Chip texto={r.prazo ? rotuloComAtraso(r.prazo, hoje) + (r.horario ? ` · ${r.horario}` : "") : "Sem data"} cor={r.prazo ? (atrasada ? "var(--perigo-texto)" : "var(--texto2)") : undefined}>
                  <CalendarIcone />
                </Chip>
              </button>
              {todas.filter((g) => r.etiquetas.includes(g.id)).map((g) => (
                <button key={g.id} className="afunda" title="Tirar a etiqueta" onClick={() => mudar({ etiquetas: r.etiquetas.filter((x) => x !== g.id) })}><Chip texto={"#" + g.nome} cor={g.cor} /></button>
              ))}
              <span style={{ position: "relative" }}>
                <button className="icone-botao" style={{ width: 26, height: 26 }} title="Etiquetas (só no Tasker)" aria-label="Etiquetas" onClick={() => setEtiquetasAbertas(!etiquetasAbertas)}><Hash size={11} strokeWidth={2.8} /></button>
                {etiquetasAbertas && (
                  <div className="dropdown-listas" style={{ position: "absolute", top: 30, left: 0, zIndex: 5, minWidth: 180 }}>
                    {todas.map((g) => (
                      <button key={g.id} className="opcao-lista" onClick={() => mudar({ etiquetas: r.etiquetas.includes(g.id) ? r.etiquetas.filter((x) => x !== g.id) : [...r.etiquetas, g.id] })}>
                        <span className="t-sm" style={{ flex: 1, color: g.cor }}>#{g.nome}</span>{r.etiquetas.includes(g.id) && <span className="t-xs">✓</span>}
                      </button>
                    ))}
                    {todas.length > 0 && <div style={{ height: 1, background: "var(--borda)", margin: "3px 0" }} />}
                    <button className="opcao-lista t-sm" onClick={() => { setEtiquetasAbertas(false); folhas.abrir("Nova etiqueta", <CriadorDeEtiqueta aoCriar={(g) => setR((x) => x && { ...x, etiquetas: [...x.etiquetas, g] })} />); }}>Nova etiqueta…</button>
                  </div>
                )}
              </span>
            </div>
            {listasAbertas && <DropdownListas atual={r.listaId} aoEscolher={(l) => { mudar({ listaId: l }); setListasAbertas(false); }} />}
            {dataAberta && (
              <div className="entrar">
                <SeletorData valor={r.prazo} horario={r.horario} aoEscolher={(d) => setR((x) => x && { ...x, prazo: d, horario: d ? x.horario : null })}
                  aoMudarHorario={(h) => setR((x) => x && { ...x, horario: h })} fechar={() => setDataAberta(false)} />
              </div>
            )}
          </div>
          <CampoTempo id={id} />
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
          <span className="rotulo">Descrição</span>
          <textarea className="campo-limpo t-md descricao" value={r.notas} placeholder="Adicione detalhes, links ou anotações…" onChange={(e) => mudar({ notas: e.target.value })} />
        </div>

        {/* O Google Tasks só tem um nível de subtarefas. */}
        {!t.mae && <Subtarefas maeId={id} listaId={t.listaId} />}
        <Anexos id={id} />
      </div>
      {alterado && (
        <div className="entrar" style={{ display: "flex", alignItems: "center", gap: "var(--e2)", padding: "12px 20px", borderTop: "1px solid var(--borda)" }}>
          <span className="t-xs c3" style={{ flex: 1 }}>Alterações não salvas</span>
          <button className="botao b-superficie" onClick={() => setR(original)}>Descartar</button>
          <button className="botao b-primario" onClick={salvar}>Salvar</button>
        </div>
      )}
    </aside>
  );
}

function CalendarIcone() {
  return (
    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <rect x="3" y="4" width="18" height="18" rx="2" /><path d="M16 2v4M8 2v4M3 10h18" />
    </svg>
  );
}

