import { useMemo, useState } from "react";
import { ArrowUpRight, BatteryFull, BatteryLow, Calendar, Camera, ChevronDown, ChevronUp, Hash, ListChecks, Pencil, Plus, Sun, Sunrise, Trash2 } from "lucide-react";
import { mesmaLista, usar } from "../dados/armazem";
import {
  adiarAtrasadas, apagarDespejo, despejar, despejoParaNota, despejoParaTarefa, esvaziarNao, excluirNota, fazerAgora, guardarFoto,
  moverDespejo, mudarPrefs, editarEtiqueta, novaNota, atualizarNota, escreverNoDia, revisaoDaSemana, tarefaDaLinha, criarLista, excluirLista, renomearLista,
} from "../dados/acoes";
import { corDaLista, etiquetasOrdenadas, eventosDoDia, indice, nomeDaLista, pendentesDaNota } from "../dados/consultas";
import { entrarComGoogle, reconectarGoogle, sair, usarSemConta } from "../dados/sync";
import type { EstadoDespejo, Tarefa, Tema } from "../dados/tipos";
import { deISO, diaISO, hojeISO, primeiraMaiuscula, rotuloCurto, rotuloLongo, somarDias } from "../dados/util";
import { Cabecalho, CartaoLinhas, EstadoVazio, LadrilhoLista, LinhaTarefa, Secao, Vazio } from "./comuns";
import { irPara } from "./rota";

const raiz = (ts: Tarefa[]) => ts.filter((t) => !t.mae);
const linhas = (ts: Tarefa[], opc: { data?: boolean; lista?: boolean } = {}) =>
  ts.map((t) => <LinhaTarefa key={t.id} t={t} mostrarData={opc.data ?? true} mostrarLista={opc.lista ?? true} />);
export const textoContagem = (n: number) => (n === 0 ? "Nada pendente" : `${n} tarefa${n === 1 ? "" : "s"} para concluir`);
const hora = (iso: string) => new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });

let eventosRecolhidos = (() => { try { return localStorage.getItem("eventsCollapsed") === "1"; } catch { return false; } })();

/** Eventos do Google Calendar (EventsCard): sem fundo, barra de cor, horário e título; seta recolhe. */
export function Eventos({ dia, compacto = false, recolhivel = true }: { dia: string; compacto?: boolean; recolhivel?: boolean }) {
  const evs = usar((e) => eventosDoDia(e, dia), mesmaLista);
  const [fechado, setFechado] = useState(eventosRecolhidos);
  if (!evs.length) return null;
  const mostrar = recolhivel && fechado ? evs.slice(0, 1) : evs;
  const agora = Date.now();
  return (
    <div style={{ display: "flex", alignItems: "flex-start" }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        {mostrar.map((ev) => (
          <a key={ev.id} className="evento afunda" href={ev.link ?? undefined} target="_blank" rel="noreferrer" title="Abrir no Google Calendar"
            style={{ ["--cor" as string]: ev.cor, padding: compacto ? "6px 0" : "7px 0", opacity: new Date(ev.fim).getTime() < agora ? 0.45 : 1 }}>
            <span className="evento-barra" />
            <span className="t-xs p-medio c3 numeros" style={{ minWidth: 74 }}>{ev.diaTodo ? "Dia todo" : `${hora(ev.inicio)}–${hora(ev.fim)}`}</span>
            <span className="t-sm p-medio uma-linha">{ev.titulo}</span>
            <ArrowUpRight size={10} strokeWidth={3} className="evento-seta" />
          </a>
        ))}
      </div>
      {recolhivel && evs.length > 1 && (
        <button className="icone-botao" style={{ width: 26, height: 26, marginTop: compacto ? 1 : 3 }} aria-label={fechado ? "Mostrar todos os eventos" : "Mostrar menos"}
          onClick={() => { eventosRecolhidos = !fechado; setFechado(!fechado); try { localStorage.setItem("eventsCollapsed", fechado ? "0" : "1"); } catch { /* nada */ } }}>
          {fechado ? <ChevronDown size={11} /> : <ChevronUp size={11} />}
        </button>
      )}
    </div>
  );
}

function BotaoEnergia() {
  const baixa = usar((e) => e.prefs.energiaBaixa);
  return (
    <button className={"icone-botao" + (baixa ? " ativo" : "")} aria-label="Energia"
      title={baixa ? "Tô sem energia — clique para ver tudo" : "Tenho energia — clique se estiver sem energia"}
      onClick={() => mudarPrefs((p) => ({ energiaBaixa: !p.energiaBaixa }))}>
      {baixa ? <BatteryLow size={16} /> : <BatteryFull size={16} />}
    </button>
  );
}

export function TelaHoje() {
  const hoje = hojeISO();
  const baixa = usar((e) => e.prefs.energiaBaixa);
  const atrasadas = usar((e) => (e.prefs.energiaBaixa ? [] : raiz(indice(e).atrasadas)), mesmaLista);
  const tarefas = usar((e) => raiz(indice(e).hoje), mesmaLista);
  const feitas = usar((e) => indice(e).concluidasHoje, mesmaLista);
  const vazio = !tarefas.length && !atrasadas.length;
  const concluidas = feitas.length > 0 && (
    <Secao titulo="Concluídas" contagem={feitas.length} recolhida>{linhas(feitas, { data: false })}</Secao>
  );
  return (
    <>
      <Cabecalho titulo="Hoje" sub={baixa ? rotuloLongo(hoje) : `${rotuloLongo(hoje)} · ${textoContagem(atrasadas.length + tarefas.length)}`} direita={<BotaoEnergia />} />
      <div className="entrar-2" style={{ display: "flex", flexDirection: "column", gap: "var(--e5)" }}>
        <Eventos dia={hoje} />
        {atrasadas.length > 0 && (
          <Secao titulo="Em atraso" contagem={atrasadas.length} tom="var(--perigo-texto)" acao={<button className="botao b-fantasma" onClick={adiarAtrasadas}>Mover para hoje</button>}>
            {linhas(atrasadas)}
          </Secao>
        )}
        {vazio && concluidas}
        {!tarefas.length ? (
          !atrasadas.length && <EstadoVazio Icone={Sun} titulo="Nada pendente" descricao="As tarefas com data de hoje aparecem aqui." />
        ) : !atrasadas.length ? (
          <CartaoLinhas>{linhas(tarefas, { data: false })}</CartaoLinhas>
        ) : (
          <Secao titulo="Hoje" contagem={tarefas.length}>{linhas(tarefas, { data: false })}</Secao>
        )}
        {!vazio && concluidas}
      </div>
    </>
  );
}

function Dia({ titulo, dia }: { titulo: string; dia: string }) {
  const ts = usar((e) => raiz(indice(e).porDia.get(dia) ?? []), mesmaLista);
  const temEventos = usar((e) => eventosDoDia(e, dia).length > 0);
  return (
    <>
      <Cabecalho titulo={titulo} sub={`${rotuloLongo(dia)} · ${textoContagem(ts.length)}`} />
      <div className="entrar-2" style={{ display: "flex", flexDirection: "column", gap: "var(--e4)" }}>
        {!ts.length && !temEventos ? (
          <EstadoVazio Icone={Sunrise} titulo="Dia livre" descricao={`Nada marcado para ${titulo.toLowerCase()}.`} />
        ) : (
          <>
            <Eventos dia={dia} />
            {ts.length > 0 && <CartaoLinhas>{linhas(ts, { data: false })}</CartaoLinhas>}
          </>
        )}
      </div>
    </>
  );
}

export function TelaAmanha() {
  return <Dia titulo="Amanhã" dia={somarDias(hojeISO(), 1)} />;
}

function DiaComItens({ dia }: { dia: string }) {
  const ts = usar((e) => raiz(indice(e).porDia.get(dia) ?? []), mesmaLista);
  const nEventos = usar((e) => eventosDoDia(e, dia).length);
  const [recolhido, setRecolhido] = useState(false);
  const resumo = [nEventos ? `${nEventos} evento${nEventos === 1 ? "" : "s"}` : "", ts.length ? `${ts.length} tarefa${ts.length === 1 ? "" : "s"}` : ""].filter(Boolean).join(" · ");
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
      <button className="afunda" style={{ display: "flex", alignItems: "baseline", gap: 6, width: "100%" }} onClick={() => setRecolhido(!recolhido)}>
        <span className="t-lg p-semi">{rotuloCurto(dia, hojeISO())}</span>
        <span className="t-sm c3">{deISO(dia).toLocaleDateString("pt-BR", { day: "numeric", month: "short" })}</span>
        <span style={{ flex: 1 }} />
        {recolhido && <span className="t-xs c3">{resumo}</span>}
        <ChevronDown size={11} strokeWidth={3} className="c3" style={{ transform: recolhido ? "rotate(-90deg)" : undefined, transition: "transform var(--normal) var(--curva)" }} />
      </button>
      {!recolhido && (
        <div className="entrar" style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
          <Eventos dia={dia} recolhivel={false} />
          {ts.length > 0 && <CartaoLinhas>{linhas(ts, { data: false })}</CartaoLinhas>}
        </div>
      )}
    </div>
  );
}

export function TelaProximas() {
  const hoje = hojeISO();
  const porDia = usar((e) => indice(e).porDia);
  const comEventos = usar((e) => new Set(e.eventos.map((ev) => ev.inicio.slice(0, 10))), (a, b) => a.size === b.size && [...a].every((x) => b.has(x)));
  const dias = Array.from({ length: 14 }, (_, i) => somarDias(hoje, i + 1)).filter((d) => (porDia.get(d) ?? []).some((t) => !t.mae) || comEventos.has(d));
  return (
    <>
      <Cabecalho titulo="Próximas" sub="Os próximos 14 dias" />
      <div className="entrar-2" style={{ display: "flex", flexDirection: "column", gap: "var(--e6)" }}>
        {!dias.length && <EstadoVazio Icone={Calendar} titulo="Duas semanas livres" descricao="Tarefas e eventos dos próximos dias aparecem aqui." />}
        {dias.map((d) => <DiaComItens key={d} dia={d} />)}
      </div>
    </>
  );
}
export function TelaCalendario() {
  const hoje = hojeISO();
  const [mes, setMes] = useState(hoje.slice(0, 7));
  const [dia, setDia] = useState(somarDias(hoje, 1));
  const porDia = usar((e) => indice(e).porDia);
  const eventos = usar((e) => e.eventos);
  const primeiro = deISO(mes + "-01");
  const inicio = somarDias(mes + "-01", -((primeiro.getDay() + 6) % 7));
  const dias = Array.from({ length: 42 }, (_, i) => somarDias(inicio, i));
  const ts = raiz(porDia.get(dia) ?? []);
  const mudar = (n: number) => setMes(diaISO(new Date(primeiro.getFullYear(), primeiro.getMonth() + n, 1)).slice(0, 7));
  const temEvento = useMemo(() => new Set(eventos.map((e) => e.inicio.slice(0, 10))), [eventos]);
  return (
    <>
      <Cabecalho
        titulo={primeiraMaiuscula(primeiro.toLocaleDateString("pt-BR", { month: "long", year: "numeric" }))}
        direita={<span><button className="botao b-superficie" onClick={() => mudar(-1)}>‹</button> <button className="botao b-superficie" onClick={() => { setMes(hoje.slice(0, 7)); setDia(hoje); }}>Hoje</button> <button className="botao b-superficie" onClick={() => mudar(1)}>›</button></span>}
      />
      <div className="cartao" style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 1, padding: 6 }}>
        {["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"].map((d) => <span key={d} className="rotulo" style={{ textAlign: "center", padding: 6 }}>{d}</span>)}
        {dias.map((d) => {
          const n = (porDia.get(d) ?? []).length;
          return (
            <button key={d} className="veu" onClick={() => setDia(d)} style={{ minHeight: "clamp(44px, 9vh, 92px)", padding: 6, textAlign: "left", display: "flex", flexDirection: "column", gap: 4, opacity: d.slice(0, 7) === mes ? 1 : 0.4, background: d === dia ? "var(--superficie2)" : undefined }}>
              <span className="t-sm" style={{ fontWeight: d === hoje ? 700 : 500, color: d === hoje ? "var(--acento)" : undefined }}>{Number(d.slice(8))}</span>
              <span style={{ display: "flex", gap: 3 }}>
                {n > 0 && <span className="t-xs c3">{n}</span>}
                {temEvento.has(d) && <span style={{ width: 5, height: 5, borderRadius: 9, background: "var(--acento)", alignSelf: "center" }} />}
              </span>
            </button>
          );
        })}
      </div>
      <Eventos dia={dia} />
      <Secao titulo={rotuloLongo(dia)}>{ts.length ? linhas(ts, { data: false }) : <Vazio texto="Nada neste dia." />}</Secao>
    </>
  );
}

export function TelaTodas() {
  const [porLista, setPorLista] = useState(() => { try { return localStorage.getItem("allGroupByList") === "1"; } catch { return false; } });
  const e = usar((x) => x);
  const i = indice(e);
  const mudar = (v: boolean) => { setPorLista(v); try { localStorage.setItem("allGroupByList", v ? "1" : "0"); } catch { /* nada */ } };
  const grupo = (titulo: string, ts: Tarefa[], tom?: string) => (ts.length ? <Secao key={titulo} titulo={titulo} contagem={raiz(ts).length} tom={tom}>{linhas(raiz(ts))}</Secao> : null);
  return (
    <>
      <Cabecalho titulo="Todas" sub={textoContagem(raiz(i.abertas).length)} />
      <div className="entrar-2" style={{ display: "flex", flexDirection: "column", gap: "var(--e6)", alignItems: "stretch" }}>
        <div className="segmentado" style={{ alignSelf: "flex-start" }}>
          <button aria-pressed={!porLista} onClick={() => mudar(false)}>Por data</button>
          <button aria-pressed={porLista} onClick={() => mudar(true)}>Por lista</button>
        </div>
        {porLista
          ? e.listas.map((l) => {
              const ts = raiz(i.porLista.get(l.id) ?? []);
              return ts.length ? <Secao key={l.id} titulo={nomeDaLista(e, l.id)} contagem={ts.length} tom={corDaLista(e, l.id)}>{linhas(ts, { lista: false })}</Secao> : null;
            })
          : [grupo("Em atraso", i.atrasadas, "var(--perigo-texto)"), grupo("Hoje", i.hoje), grupo("Em breve", i.depois), grupo("Sem data", i.semData)]}
      </div>
    </>
  );
}

export function TelaConcluidas() {
  const feitas = usar((e) => indice(e).concluidas);
  const [limite, setLimite] = useState(40);
  const hoje = hojeISO();
  const grupos = new Map<string, Tarefa[]>();
  for (const t of feitas.slice(0, limite)) {
    const d = t.concluidaEm ? diaISO(new Date(t.concluidaEm)) : "";
    grupos.set(d, [...(grupos.get(d) ?? []), t]);
  }
  return (
    <>
      <Cabecalho titulo="Concluídas" sub={`${feitas.length} tarefas até aqui`} />
      <div className="entrar-2" style={{ display: "flex", flexDirection: "column", gap: "var(--e6)" }}>
        <ResumoConcluidas />
        {[...grupos.keys()].sort().reverse().map((d) => (
          <Secao key={d} titulo={d ? rotuloCurto(d, hoje) : "Sem data"} contagem={grupos.get(d)!.length}>{linhas(grupos.get(d)!, { data: false })}</Secao>
        ))}
        {feitas.length > limite && <button className="botao b-fantasma" onClick={() => setLimite(limite + 40)}>Mostrar mais</button>}
      </div>
    </>
  );
}

/** Resumo do gráfico de concluídas (ResumoConcluidas.swift). */
function ResumoConcluidas() {
  const feitas = usar((e) => indice(e).concluidas);
  const hoje = hojeISO();
  const [dica, setDica] = useState<number | null>(null);
  const dias = Array.from({ length: 30 }, (_, i) => somarDias(hoje, i - 29));
  const contagem = useMemo(() => {
    const m = new Map<string, number>();
    for (const t of feitas) if (t.concluidaEm) {
      const d = diaISO(new Date(t.concluidaEm));
      m.set(d, (m.get(d) ?? 0) + 1);
    }
    return m;
  }, [feitas]);
  const max = Math.max(1, ...dias.map((d) => contagem.get(d) ?? 0));
  return (
    <div className="cartao" style={{ padding: "var(--e5)", position: "relative" }} onMouseLeave={() => setDica(null)}>
      <div style={{ display: "flex", alignItems: "flex-end", gap: 3, height: 120 }}>
        {dias.map((d, i) => {
          const n = contagem.get(d) ?? 0;
          return (
            <div key={d} onMouseEnter={() => setDica(i)} style={{ flex: 1, height: "100%", display: "flex", alignItems: "flex-end" }}>
              <div style={{ width: "100%", height: `${Math.max(3, (n / max) * 100)}%`, borderRadius: 4, background: n ? "var(--acento)" : "var(--superficie3)", opacity: dica === null || dica === i ? 1 : 0.5, transition: "opacity var(--rapido)" }} />
            </div>
          );
        })}
      </div>
      {dica !== null && (
        <div className="t-xs" style={{ position: "absolute", top: 8, left: `${((dica + 0.5) / 30) * 100}%`, transform: "translateX(-50%)", background: "var(--superficie)", border: "1px solid var(--borda)", borderRadius: 8, padding: "4px 8px", boxShadow: "var(--sombra-alta)", whiteSpace: "nowrap", pointerEvents: "none" }}>
          {rotuloLongo(dias[dica])}: {contagem.get(dias[dica]) ?? 0}
        </div>
      )}
    </div>
  );
}

export function TelaLista({ id }: { id: string }) {
  const existe = usar((e) => e.listas.some((x) => x.id === id));
  const nome = usar((e) => nomeDaLista(e, id));
  const cor = usar((e) => corDaLista(e, id));
  const fixa = usar((e) => e.listaFixa === id);
  const ts = usar((e) => raiz(indice(e).porLista.get(id) ?? []).sort((a, b) => (a.posicao < b.posicao ? -1 : 1)), mesmaLista);
  const feitas = usar((e) => indice(e).concluidasPorLista.get(id) ?? [], mesmaLista);
  if (!existe) return <EstadoVazio Icone={ListChecks} titulo="Lista não encontrada" />;
  const editar = () => {
    const n = prompt("Nome da lista", nome);
    if (n?.trim() && n.trim() !== nome) renomearLista(id, n.trim());
    else if (n === "" && !fixa && confirm(`“${nome}” e as tarefas dela serão excluídas, também no Google Tasks. Dá para desfazer logo depois.`)) { excluirLista(id); irPara({ tela: "hoje" }); }
  };
  return (
    <>
      <Cabecalho titulo={nome} sub={textoContagem(ts.length)} esquerda={
        <button className="afunda" title="Personalizar ícone e cor" onClick={editar} style={{ position: "relative", padding: 4, borderRadius: 52 * 0.3 + 4, border: `2.5px solid ${cor}`, display: "inline-flex" }}>
          <LadrilhoLista listaId={id} tamanho={52} />
          <span style={{ position: "absolute", right: -4, bottom: -4, width: 20, height: 20, borderRadius: 99, background: cor, color: "#fff", border: "2px solid var(--fundo)", display: "inline-flex", alignItems: "center", justifyContent: "center" }}><Pencil size={9} strokeWidth={3} /></span>
        </button>
      } />
      <div className="entrar-2" style={{ display: "flex", flexDirection: "column", gap: "var(--e6)" }}>
        <Secao titulo="Tarefas" contagem={ts.length} tom={cor}>
          {ts.length ? linhas(ts, { lista: false }) : <EstadoVazio Icone={ListChecks} titulo="Lista vazia" descricao="Use a barra abaixo para criar a primeira tarefa." />}
        </Secao>
        {feitas.length > 0 && <Secao titulo="Concluídas" contagem={feitas.length} recolhida>{linhas(feitas.slice(0, 30), { lista: false })}</Secao>}
      </div>
    </>
  );
}

export function TelaEtiqueta({ id }: { id: string }) {
  const g = usar((e) => e.etiquetas.find((x) => x.id === id) ?? null);
  const ts = usar((e) => indice(e).abertas.filter((t) => e.etiquetasDaTarefa[t.id]?.includes(id)), mesmaLista);
  if (!g) return <EstadoVazio Icone={Hash} titulo="Etiqueta não encontrada" />;
  return (
    <>
      <Cabecalho titulo={"#" + g.nome} sub="Etiqueta · só no Tasker" />
      <div className="entrar-2" style={{ display: "flex", flexDirection: "column", gap: "var(--e6)" }}>
        <div><button className="botao b-superficie" onClick={() => { const n = prompt("Nome da etiqueta", g.nome); if (n?.trim()) editarEtiqueta(id, { nome: n.trim() }); }}><Pencil size={13} /> Editar etiqueta</button></div>
        <Secao titulo="Tarefas" contagem={ts.length}>
          {ts.length ? linhas(ts) : <EstadoVazio Icone={Hash} titulo="Nenhuma tarefa aqui" descricao="Clique com o botão direito numa tarefa → Etiquetas." />}
        </Secao>
      </div>
    </>
  );
}

// MARK: Despejo

export function TelaDespejo() {
  const itens = usar((e) => e.despejo);
  const [aba, setAba] = useState<EstadoDespejo>("caixa");
  const [texto, setTexto] = useState("");
  const [organizar, setOrganizar] = useState(false);
  const daAba = itens.filter((i) => i.estado === aba);
  const fila = itens.filter((i) => i.estado === "caixa").slice(0, 3);
  const fotos = async (f: FileList | null) => {
    for (const a of Array.from(f ?? [])) despejar("", await guardarFoto(a));
  };
  return (
    <>
      <Cabecalho titulo="Despejo" sub="Tire da cabeça. Decida depois." />
      <div className="cartao" style={{ padding: 8, display: "flex", gap: 8, alignItems: "flex-start" }}>
        <textarea className="campo campo-limpo" rows={2} placeholder="O que está na sua cabeça? (uma coisa por linha)" value={texto} onChange={(e) => setTexto(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); if (texto.trim()) { despejar(texto); setTexto(""); } } }} style={{ flex: 1, resize: "none" }} />
        <label className="icone-botao" aria-label="Foto"><Camera size={16} /><input type="file" accept="image/*" multiple hidden onChange={(e) => void fotos(e.target.files)} /></label>
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
        <div className="segmentado">
          {(["caixa", "depois", "nao"] as const).map((a) => (
            <button key={a} aria-pressed={aba === a} onClick={() => setAba(a)}>{{ caixa: "Caixa", depois: "Depois", nao: "Não" }[a]} {itens.filter((i) => i.estado === a).length || ""}</button>
          ))}
        </div>
        {aba === "caixa" && fila.length > 0 && <button className="botao b-primario" onClick={() => setOrganizar(!organizar)}>{organizar ? "Ver tudo" : "Organizar 3"}</button>}
        {aba === "nao" && daAba.length > 0 && <button className="botao b-fantasma" onClick={esvaziarNao}>Esvaziar</button>}
      </div>
      <div className="cartao-linhas">
        {(organizar && aba === "caixa" ? fila : daAba).map((i) => (
          <div key={i.id} className="linha-tarefa" style={{ cursor: "default", flexWrap: "wrap" }}>
            <span className="t-md" style={{ flex: 1, minWidth: 160 }}>{i.texto || (i.foto ? "📷 Foto" : "")}</span>
            <span style={{ display: "flex", gap: 4, flexWrap: "wrap" }}>
              <button className="chip" onClick={() => fazerAgora(i.id)}>Hoje</button>
              <button className="chip" onClick={() => despejoParaTarefa(i.id, { titulo: i.texto || "Foto" })}>Tarefa</button>
              <button className="chip" onClick={() => { const n = despejoParaNota(i.id); if (n) irPara({ tela: "nota", id: n }); }}>Nota</button>
              {i.estado !== "depois" && <button className="chip" onClick={() => moverDespejo(i.id, "depois")}>Depois</button>}
              {i.estado !== "nao" && <button className="chip" onClick={() => moverDespejo(i.id, "nao")}>Não</button>}
              {i.estado !== "caixa" && <button className="chip" onClick={() => moverDespejo(i.id, "caixa")}>Caixa</button>}
              <button className="icone-botao" aria-label="Apagar" onClick={() => apagarDespejo(i.id)}><Trash2 size={14} /></button>
            </span>
          </div>
        ))}
        {!daAba.length && <Vazio texto="Vazio." />}
      </div>
    </>
  );
}

// MARK: Notas

export function TelaNotas() {
  const notas = usar((e) => e.notas);
  const hoje = hojeISO();
  const ordenadas = [...notas].sort((a, b) => (a.editadaEm < b.editadaEm ? 1 : -1));
  const doDia = notas.find((n) => n.dia === hoje);
  return (
    <>
      <Cabecalho
        titulo="Notas"
        direita={
          <span style={{ display: "flex", gap: 6 }}>
            <button className="botao b-superficie" onClick={() => irPara({ tela: "nota", id: revisaoDaSemana() })}>Revisão da semana</button>
            <button className="botao b-primario" onClick={() => irPara({ tela: "nota", id: novaNota() })}><Plus size={14} /> Nova</button>
          </span>
        }
      />
      <div className="cartao" style={{ padding: 16 }}>
        <div className="rotulo">Nota do dia</div>
        <textarea className="campo-limpo t-md" rows={3} style={{ width: "100%", resize: "vertical", marginTop: 6 }} placeholder="Como foi hoje?" defaultValue={doDia?.texto ?? ""} onChange={(e) => escreverNoDia(hoje, e.target.value)} />
      </div>
      <div className="cartao-linhas">
        {ordenadas.filter((n) => n !== doDia).map((n) => (
          <button key={n.id} className="linha-tarefa" style={{ width: "100%", textAlign: "left" }} onClick={() => irPara({ tela: "nota", id: n.id })}>
            <span style={{ flex: 1, minWidth: 0 }}>
              <span className="t-md p-semi uma-linha" style={{ display: "block" }}>{n.titulo || (n.dia ? rotuloLongo(n.dia) : n.texto.split("\n")[0] || "Sem título")}</span>
              <span className="t-xs c3">{new Date(n.editadaEm).toLocaleDateString("pt-BR")}</span>
            </span>
          </button>
        ))}
      </div>
    </>
  );
}

export function TelaNota({ id }: { id: string }) {
  const n = usar((e) => e.notas.find((x) => x.id === id) ?? null);
  if (!n) return <Vazio texto="Nota não encontrada." />;
  const pend = pendentesDaNota(n.texto);
  return (
    <>
      <div style={{ display: "flex", justifyContent: "space-between" }}>
        <button className="botao b-fantasma" onClick={() => irPara({ tela: "notas" })}>‹ Notas</button>
        <button className="botao b-perigo" onClick={() => { excluirNota(id); irPara({ tela: "notas" }); }}><Trash2 size={14} /></button>
      </div>
      <input className="campo-limpo display d-display2" placeholder={n.dia ? rotuloLongo(n.dia) : "Título"} defaultValue={n.titulo} key={id + "t"} onChange={(e) => atualizarNota(id, { titulo: e.target.value })} />
      <textarea className="campo-limpo t-lg" style={{ minHeight: "50vh", resize: "none", lineHeight: 1.6 }} defaultValue={n.texto} key={id + "x"} placeholder="Escreva… ( [ ] vira tarefa )" onChange={(e) => atualizarNota(id, { texto: e.target.value })} />
      {pend.length > 0 && (
        <Secao titulo="Viram tarefa">
          {pend.map((p) => (
            <div key={p.linha} className="linha-tarefa">
              <span className="t-md" style={{ flex: 1 }}>{p.titulo}</span>
              <button className="chip" onClick={() => tarefaDaLinha(id, p.linha)}>Criar tarefa</button>
            </div>
          ))}
        </Secao>
      )}
    </>
  );
}

// MARK: Ajustes

export function TelaAjustes() {
  const e = usar((x) => x);
  const [tema, setTema] = useState<Tema>(() => (localStorage.getItem("tasker.tema") as Tema) || "sistema");
  const mudarTema = (t: Tema) => {
    setTema(t);
    localStorage.setItem("tasker.tema", t);
    aplicarTema();
  };
  const chave = (rotulo: string, k: "contarAtrasadas" | "mostrarEventosNoMenu" | "mostrarAtrasadasNoMenu" | "somAoConcluir") => (
    <div className="linha-tarefa" style={{ cursor: "default" }}>
      <span className="t-md" style={{ flex: 1 }}>{rotulo}</span>
      <button className="chave" role="switch" aria-checked={e.prefs[k]} aria-label={rotulo} onClick={() => mudarPrefs((p) => ({ [k]: !p[k] }))} />
    </div>
  );
  return (
    <>
      <Cabecalho titulo="Ajustes" />
      <Secao titulo="Conta">
        <div className="linha-tarefa" style={{ cursor: "default" }}>
          <span style={{ flex: 1 }}>
            <span className="t-md p-semi" style={{ display: "block" }}>{e.modo === "conta" ? e.nome || e.email : "Sem conta (só neste aparelho)"}</span>
            <span className="t-xs c3">{e.modo === "conta" ? `${e.email ?? ""} · ${e.pendencias ? `${e.pendencias} alteração(ões) esperando rede` : "tudo sincronizado"}` : "Entre com o Google para sincronizar Tasks e Agenda."}</span>
          </span>
          {e.modo === "conta" ? <button className="botao b-superficie" onClick={() => void sair()}>Sair</button> : <button className="botao b-primario" onClick={() => void entrarComGoogle()}>Entrar com Google</button>}
        </div>
        {e.googlePendente && (
          <div className="linha-tarefa" style={{ cursor: "default" }}>
            <span className="t-md" style={{ flex: 1 }}>O Google precisa ser reconectado.</span>
            <button className="botao b-primario" onClick={() => void reconectarGoogle()}>Reconectar</button>
          </div>
        )}
      </Secao>
      <Secao titulo="Aparência">
        <div className="linha-tarefa" style={{ cursor: "default" }}>
          <span className="t-md" style={{ flex: 1 }}>Tema</span>
          <div className="segmentado">
            {(["sistema", "claro", "escuro"] as const).map((t) => <button key={t} aria-pressed={tema === t} onClick={() => mudarTema(t)}>{primeiraMaiuscula(t)}</button>)}
          </div>
        </div>
      </Secao>
      <Secao titulo="Comportamento">
        {chave("Contar atrasadas no número de hoje", "contarAtrasadas")}
        {chave("Eventos no menu", "mostrarEventosNoMenu")}
        {chave("Atrasadas no menu", "mostrarAtrasadasNoMenu")}
        {chave("Som ao concluir", "somAoConcluir")}
      </Secao>
      {e.agendas.length > 0 && (
        <Secao titulo="Agendas">
          {e.agendas.map((a) => (
            <div key={a.id} className="linha-tarefa" style={{ cursor: "default" }}>
              <span style={{ width: 10, height: 10, borderRadius: 9, background: a.cor }} />
              <span className="t-md" style={{ flex: 1 }}>{a.titulo}</span>
              <button className="chave" role="switch" aria-label={a.titulo} aria-checked={e.prefs.agendasVisiveis[a.id] !== false} onClick={() => mudarPrefs((p) => ({ agendasVisiveis: { ...p.agendasVisiveis, [a.id]: p.agendasVisiveis[a.id] === false } }))} />
            </div>
          ))}
        </Secao>
      )}
      <Secao titulo="Listas" acao={<button className="botao b-fantasma t-xs" onClick={() => { const n = prompt("Nova lista"); if (n?.trim()) criarLista(n.trim()); }}>+ Nova</button>}>
        {e.listas.map((l) => (
          <div key={l.id} className="linha-tarefa" style={{ cursor: "default" }}>
            <span className="t-md" style={{ flex: 1 }}>{nomeDaLista(e, l.id)}</span>
            <button className="chip" aria-pressed={e.prefs.listaPadrao === l.id} onClick={() => mudarPrefs(() => ({ listaPadrao: l.id }))}>Padrão</button>
          </div>
        ))}
      </Secao>
      <Secao titulo="Etiquetas">
        {etiquetasOrdenadas(e).map((g) => <div key={g.id} className="linha-tarefa" style={{ color: g.cor }}>#{g.nome}</div>)}
        {!e.etiquetas.length && <Vazio texto="Escreva #nome ao criar uma tarefa." />}
      </Secao>
    </>
  );
}

export function aplicarTema() {
  const t = localStorage.getItem("tasker.tema") || "sistema";
  const escuro = t === "escuro" || (t === "sistema" && matchMedia("(prefers-color-scheme: dark)").matches);
  document.documentElement.dataset.tema = escuro ? "escuro" : "claro";
}

// MARK: Entrar

export function TelaEntrar() {
  return (
    <div style={{ minHeight: "100%", display: "grid", placeItems: "center", padding: 24 }}>
      <div style={{ maxWidth: 380, display: "flex", flexDirection: "column", gap: 16, textAlign: "center" }}>
        <h1 className="display d-display">Tasker</h1>
        <p className="t-md c2">Suas tarefas do Google, sua agenda e suas notas — no Mac, no celular e no navegador. Funciona offline.</p>
        <button className="botao b-primario" style={{ height: 44 }} onClick={() => void entrarComGoogle()}>Entrar com Google</button>
        <button className="botao b-fantasma" onClick={usarSemConta}>Usar sem conta</button>
      </div>
    </div>
  );
}
