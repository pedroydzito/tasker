import { AvisoAtualizacao, procurarAtualizacao, useAtualizacao } from "./atualizacao";
import { Rolagem } from "./comuns";
import { CampoTarefa } from "./campo";
import { EditorDeEtiqueta, EditorDeLista, Nota, folhas } from "./folhas";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { CircleUserRound, HardDrive, Laptop, Paintbrush, Settings, ArchiveRestore, BadgeCheck, Brain, Check, CircleCheck, CircleX, Clock, Ellipsis, Hand, ImagePlus, Layers2, Zap, CalendarCheck, Circle, SquarePen, ChevronLeft, ChevronRight, NotepadText, Calendar, ChevronDown, Hash, ListChecks, Pencil, Plus, Sun, Trash2 } from "lucide-react";
import { mesmaLista, usar } from "../dados/armazem";
import {
  apagarDespejo, despejar, despejoParaNota, despejoParaTarefa, esvaziarNao, excluirNota, fazerAgora, guardarFoto,
  moverDespejo, criarTarefa, editarDespejo, resolverEtiquetas, descartarSeVazia, mudarPrefs, criarDoTexto, novaNota, atualizarNota, escreverNoDia, revisaoDaSemana, tarefaDaLinha,
} from "../dados/acoes";
import { contagemHoje, tempoDe, listaPadrao, tituloDe, corDaLista, eventosDoDia, indice, nomeDaLista, pendentesDaNota } from "../dados/consultas";
import { entrarComGoogle, puxar, reconectarGoogle, sair, usarSemConta } from "../dados/sync";
import { ler as lerEstado } from "../dados/armazem";
import type { EstadoDespejo, ItemDespejo, Tarefa, Tema } from "../dados/tipos";
import { lerArquivo } from "../dados/espelho";
import { supabase } from "../dados/nuvem";
import { duracaoCurta, lerCriacaoRapida, deISO, diaISO, hojeISO, primeiraMaiuscula, rotuloCurto, rotuloLongo, somarDias } from "../dados/util";
import { useCelular, Segmentado, DropdownListas, Cabecalho, CartaoLinhas, ChipLista, EstadoVazio, LadrilhoLista, LinhaTarefa, Secao, SeletorData } from "./comuns";
import { abrirNota, abrirNotaDoDia, irPara, useNotaAberta, type AlvoNota } from "./rota";

import { CampoCelular, Eventos, aplicarTema, linhas, raiz, textoContagem } from "./hoje";

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
      <div data-encadeado className="bloco-tela" style={{ ["--i" as string]: 1, display: "flex", flexDirection: "column", gap: "var(--e6)" }}>
        <CampoCelular prazo={somarDias(hoje, 1)} />
        {!dias.length && <EstadoVazio Icone={Calendar} titulo="Duas semanas livres" descricao="Tarefas e eventos dos próximos dias aparecem aqui." />}
        {dias.map((d) => <DiaComItens key={d} dia={d} />)}
      </div>
    </>
  );
}
/** Calendário (CalendarView.swift): mês à esquerda em cartões por dia, agenda do dia à direita. */
export function TelaCalendario() {
  const hoje = hojeISO();
  const [mes, setMes] = useState(hoje.slice(0, 7));
  const [sel, setSel] = useState(hoje);
  const [altura, setAltura] = useState(84);
  const celular = useCelular();
  const ref = useRef<HTMLDivElement>(null);
  const porDia = usar((e) => indice(e).porDia);
  const feitasPorDia = usar((e) => indice(e).concluidasPorDia);
  const eventos = usar((e) => e.eventos);
  const comNota = usar((e) => new Set(e.notas.filter((n) => n.dia && n.texto.trim()).map((n) => n.dia!)), (a, b) => a.size === b.size && [...a].every((x) => b.has(x)));
  const e = usar((x) => x);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    // Seis semanas dividem a altura que sobra; abaixo de 64 a tela rola.
    const fixa = 56 + 64 + 16 + 20 + 16 + 24 + 6 * 5;
    const o = new ResizeObserver(() => setAltura(Math.max(64, Math.floor((el.clientHeight - fixa) / 6))));
    o.observe(el);
    return () => o.disconnect();
  }, []);
  const primeiro = deISO(mes + "-01");
  const inicio = somarDias(mes + "-01", -primeiro.getDay());
  const dias = Array.from({ length: 42 }, (_, i) => somarDias(inicio, i));
  const mudar = (n: number) => setMes(diaISO(new Date(primeiro.getFullYear(), primeiro.getMonth() + n, 1)).slice(0, 7));
  const agora = Date.now();
  return (
    <div className="tela-calendario" style={{ display: "flex", flex: 1, minWidth: 0, height: "100%" }}>
      <Rolagem casca="casca-flex" rolagemRef={ref} className="pagina" style={{ padding: "56px 32px 24px", display: "flex", flexDirection: "column", gap: "var(--e4)" }}>
        <header className="cabecalho-calendario">
          <div style={{ display: "flex", flexDirection: "column", gap: 3, flex: 1 }}>
            <h1 className="display d-display cabecalho-encolhe">{primeiraMaiuscula(primeiro.toLocaleDateString("pt-BR", { month: "long", year: "numeric" }))}</h1>
            <div className="t-sm c3 cabecalho-encolhe">Calendário</div>
          </div>
          <span style={{ display: "flex", gap: 4, alignItems: "center" }}>
            <button className="botao b-superficie" onClick={() => { setMes(hoje.slice(0, 7)); setSel(hoje); }}>Hoje</button>
            <button className="icone-botao" aria-label="Voltar um mês" onClick={() => mudar(-1)}><ChevronLeft size={14} /></button>
            <button className="icone-botao" aria-label="Avançar um mês" onClick={() => mudar(1)}><ChevronRight size={14} /></button>
          </span>
        </header>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(7, minmax(0, 1fr))", gap: 6 }}>
          {["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"].map((d) => <span key={d} className="rotulo rotulo-semana" style={{ paddingLeft: 8 }}>{d}</span>)}
        </div>
        <div className="entrar" key={mes} style={{ display: "grid", gridTemplateColumns: "repeat(7, minmax(0, 1fr))", gap: 6 }}>
          {dias.map((d) => {
            const noMes = d.slice(0, 7) === mes;
            const evs = eventosDoDia(e, d);
            const itens = [
              ...evs.map((ev) => ({ id: "e" + ev.id, texto: ev.titulo, cor: ev.cor, evento: true, passado: new Date(ev.fim).getTime() < agora, riscado: false })),
              ...[...(porDia.get(d) ?? []), ...(feitasPorDia.get(d) ?? [])].filter((t) => !t.mae).map((t) => ({ id: "t" + t.id, texto: tituloDe(t), cor: corDaLista(e, t.listaId), evento: false, passado: t.concluida, riscado: t.concluida })),
            ];
            const cabem = Math.max(1, Math.floor((altura - 36) / 16));
            const visiveis = itens.length <= cabem ? itens : itens.slice(0, Math.max(cabem - 1, 1));
            const extra = itens.length - visiveis.length;
            const ehHoje = d === hoje;
            return (
              <button key={d} className={"dia-cal" + (celular ? " compacto" : "")} title={rotuloLongo(d)} aria-pressed={d === sel} onClick={() => setSel(d)}
                style={{ height: celular ? undefined : altura, background: noMes ? "var(--superficie)" : "color-mix(in srgb, var(--superficie) 40%, transparent)", borderColor: d === sel ? "var(--acento)" : undefined, borderWidth: d === sel ? 1.5 : 1 }}>
                <span style={{ position: "relative", width: 24, height: 24, borderRadius: 99, display: "inline-flex", alignItems: "center", justifyContent: "center", marginBottom: 1, flex: "none",
                  background: ehHoje ? "var(--acento)" : undefined, color: ehHoje ? "#fff" : noMes ? "var(--texto)" : "var(--texto3)", fontWeight: ehHoje ? 700 : 500 }} className="t-sm">
                  {Number(d.slice(8))}
                  {comNota.has(d) && <NotepadText size={9} strokeWidth={2.6} className="c3" style={{ position: "absolute", left: 26 }} />}
                </span>
                {celular ? (
                  <span className="pontos-dia">
                    {itens.slice(0, 3).map((it) => <span key={it.id} style={{ background: it.cor, opacity: it.passado ? 0.45 : 1 }} />)}
                  </span>
                ) : visiveis.map((it) => (
                  <span key={it.id} className="t-xs uma-linha" style={{ display: "flex", alignItems: "center", gap: 4, width: "100%", color: noMes ? "var(--texto2)" : "var(--texto3)", opacity: it.passado ? 0.45 : 1 }}>
                    {it.evento ? <span style={{ width: 2.5, height: 10, borderRadius: 9, background: it.cor, flex: "none" }} /> : <span style={{ width: 7, height: 7, borderRadius: 9, border: `1.3px solid ${it.cor}`, flex: "none" }} />}
                    <span className={"uma-linha" + (it.riscado ? " riscado" : "")}>{it.texto}</span>
                  </span>
                ))}
                {!celular && extra > 0 && <span className="t-xs p-semi c3" style={{ paddingLeft: 2 }}>+{extra}</span>}
              </button>
            );
          })}
        </div>
      </Rolagem>
      <Rolagem casca="casca-agenda" fundo="var(--superficie)" className="agenda-dia">
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          <span className="rotulo">{rotuloLongo(sel)}</span>
          <span className="display d-titulo">{rotuloCurto(sel, hoje)}</span>
        </div>
        <CampoTarefa key={sel} prazo={sel} />
        <button className="nota-dia-cartao afunda" onClick={() => { abrirNotaDoDia(sel); irPara({ tela: "notas" }); }}>
          <NotepadText size={14} className="c3" style={{ marginTop: 1, flex: "none" }} />
          {e.notas.find((n) => n.dia === sel)?.texto.trim() ? <span className="t-sm c2 tres-linhas">{e.notas.find((n) => n.dia === sel)!.texto.trim()}</span> : <span className="t-sm p-medio c3">Escrever a nota do dia</span>}
        </button>
        <Eventos dia={sel} compacto />
        {(() => {
          const ts = [...(sel === hoje ? indice(e).hoje : porDia.get(sel) ?? []), ...(feitasPorDia.get(sel) ?? [])].filter((t) => !t.mae);
          if (!ts.length && !eventos.some((ev) => eventosDoDia(e, sel).includes(ev))) return <EstadoVazio Icone={Calendar} titulo="Dia livre" />;
          return ts.length ? <CartaoLinhas>{ts.map((t) => <LinhaTarefa key={t.id} t={t} compacta mostrarData={false} />)}</CartaoLinhas> : null;
        })()}
      </Rolagem>
    </div>
  );
}

/** Campo de nova tarefa embutido (QuickAddField .inline): cria na data dada. */
export function CampoRapidoInline({ prazo, aoCriar }: { prazo: string | null; aoCriar?: () => void }) {
  const [texto, setTexto] = useState("");
  return (
    <div className="campo-inline">
      <Plus size={13} className="c3" />
      <input placeholder="Adicionar tarefa" aria-label="Adicionar tarefa" value={texto} onChange={(x) => setTexto(x.target.value)}
        onKeyDown={(x) => { if (x.key === "Enter" && texto.trim()) { criarDoTexto(texto, { prazo }); setTexto(""); aoCriar?.(); } }} />
    </div>
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
      <div data-encadeado className="bloco-tela" style={{ ["--i" as string]: 1, display: "flex", flexDirection: "column", gap: "var(--e6)", alignItems: "stretch" }}>
        <CampoCelular />
        <div style={{ alignSelf: "flex-start", display: "flex", width: "100%" }}><Segmentado rotulo="Agrupar" valor={porLista} aoMudar={mudar} opcoes={[[false, "Por data"], [true, "Por lista"]]} /></div>
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
      <div data-encadeado className="bloco-tela" style={{ ["--i" as string]: 1, display: "flex", flexDirection: "column", gap: "var(--e6)" }}>
        <ResumoConcluidas />
        {[...grupos.keys()].sort().reverse().map((d) => (
          <Secao key={d} titulo={d ? rotuloCurto(d, hoje) : "Sem data"} contagem={grupos.get(d)!.length}>{linhas(grupos.get(d)!, { data: false })}</Secao>
        ))}
        {feitas.length > limite && <button className="botao b-fantasma" onClick={() => setLimite(limite + 40)}>Mostrar mais</button>}
      </div>
    </>
  );
}

type Periodo = "semana" | "mes" | "ano";
const TITULO_PERIODO: Record<Periodo, string> = { semana: "7 dias", mes: "30 dias", ano: "12 meses" };

/** Resumo do período (ResumoConcluidas.swift): concluídas por dia na cor de cada lista, tempo por lista e onde foi o tempo. */
function ResumoConcluidas() {
  const e = usar((x) => x);
  const [periodo, setPeriodoEstado] = useState<Periodo>(() => { try { return (localStorage.getItem("concluidas.periodo") as Periodo) || "semana"; } catch { return "semana"; } });
  const setPeriodo = (p: Periodo) => { setPeriodoEstado(p); try { localStorage.setItem("concluidas.periodo", p); } catch { /* nada */ } };
  const [foco, setFoco] = useState<{ i: number; x: number; y: number } | null>(null);
  const hoje = hojeISO();
  const ano = periodo === "ano";
  const chaves = ano
    ? Array.from({ length: 12 }, (_, i) => { const d = deISO(hoje); return diaISO(new Date(d.getFullYear(), d.getMonth() - 11 + i, 1)).slice(0, 7); })
    : Array.from({ length: periodo === "semana" ? 7 : 30 }, (_, i) => somarDias(hoje, i - (periodo === "semana" ? 6 : 29)));
  const chaveDe = (iso: string) => { const d = diaISO(new Date(iso)); return ano ? d.slice(0, 7) : d; };
  const feitas = indice(e).concluidas.filter((t) => t.concluidaEm && chaveDe(t.concluidaEm) >= chaves[0]);
  // Contagem por período e por lista (na ordem das listas).
  const barras = chaves.map((k) => {
    const m = new Map<string, number>();
    for (const t of feitas) if (chaveDe(t.concluidaEm!) === k) m.set(t.listaId, (m.get(t.listaId) ?? 0) + 1);
    return e.listas.filter((l) => m.has(l.id)).map((l) => ({ lista: l.id, n: m.get(l.id)! }));
  });
  const maximo = Math.max(1, ...barras.map((b) => b.reduce((s, x) => s + x.n, 0)));
  const passo = maximo <= 6 ? 2 : maximo <= 12 ? 4 : Math.ceil(maximo / 4 / 5) * 5;
  const topoEixo = Math.ceil(maximo / passo) * passo;
  const marcas = Array.from({ length: topoEixo / passo + 1 }, (_, i) => i * passo);

  const abertas = Object.values(e.tarefas).filter((t) => !t.concluida);
  const comTempo = [...feitas, ...abertas].map((t) => [t, tempoDe(e, t.id)] as const).filter(([, s]) => s > 0);
  const porLista = [...comTempo.reduce((m, [t, s]) => m.set(t.listaId, (m.get(t.listaId) ?? 0) + s), new Map<string, number>())].sort((a, b) => b[1] - a[1]);
  const total = porLista.reduce((s, [, x]) => s + x, 0);
  const topo = [...comTempo].sort((a, b) => b[1] - a[1]).slice(0, 6);
  const maiorLista = Math.max(1, ...porLista.map(([, x]) => x));

  const rotuloX = (k: string) => (ano ? deISO(k + "-01").toLocaleDateString("pt-BR", { month: "short" }) : deISO(k).toLocaleDateString("pt-BR", { day: "numeric", month: "short" }));
  const mostrarRotulo = (i: number) => periodo !== "mes" || i % 5 === 0;
  const numero = (valor: string, rotulo: string) => (
    <div style={{ display: "flex", flexDirection: "column", gap: 2, paddingRight: 24 }}>
      <span className="display d-display2 numeros">{valor}</span>
      <span className="t-xs c3">{rotulo}</span>
    </div>
  );
  return (
    <div className="cartao" style={{ padding: "var(--e5)", display: "flex", flexDirection: "column", gap: "var(--e5)" }}>
      <div className="resumo-topo" style={{ display: "flex", alignItems: "flex-start" }}>
        {numero(String(feitas.length), feitas.length === 1 ? "concluída" : "concluídas")}
        {numero(total > 0 ? duracaoCurta(total) : "—", "de tempo registrado")}
        <span style={{ flex: 1 }} />
        <Segmentado rotulo="Período" valor={periodo} aoMudar={setPeriodo} opcoes={(["semana", "mes", "ano"] as const).map((p) => [p, TITULO_PERIODO[p]] as [Periodo, string])} />
      </div>
      {!feitas.length ? (
        <div className="t-sm c3" style={{ minHeight: 120, display: "grid", placeItems: "center" }}>Nenhuma tarefa concluída nos últimos {TITULO_PERIODO[periodo]}.</div>
      ) : (
        <div className="grafico" onMouseLeave={() => setFoco(null)}>
          <div className="grafico-y">{[...marcas].reverse().map((m) => <span key={m}>{m}</span>)}</div>
          <div className="grafico-area">
            <div className="grafico-barras">
              {marcas.map((m) => <span key={m} className="grafico-linha" style={{ bottom: `${(m / topoEixo) * 100}%` }} />)}
              {barras.map((b, i) => (
                <div key={chaves[i]} className="grafico-coluna" onMouseMove={(ev) => { const r = (ev.currentTarget.parentElement as HTMLElement).getBoundingClientRect(); setFoco({ i, x: ev.clientX - r.left, y: ev.clientY - r.top }); }}>
                  <div style={{ height: `${(b.reduce((s, x) => s + x.n, 0) / topoEixo) * 100}%`, width: "72%", ["--i" as string]: i, display: "flex", flexDirection: "column-reverse", opacity: foco === null || foco.i === i ? 1 : 0.35, transition: "opacity var(--rapido)", borderRadius: 3, overflow: "hidden" }}>
                    {b.map((x) => <div key={x.lista} style={{ flex: x.n, background: corDaLista(e, x.lista) }} />)}
                  </div>
                </div>
              ))}
            </div>
            {foco && (
              <div className="dica-grafico" style={{ left: foco.x + 200 > 600 ? foco.x - 196 : foco.x + 16, top: Math.max(0, foco.y - 30) }}>
                <span className="t-xs p-semi c3">{primeiraMaiuscula(ano ? deISO(chaves[foco.i] + "-01").toLocaleDateString("pt-BR", { month: "long", year: "numeric" }) : rotuloLongo(chaves[foco.i]))}</span>
                {(() => { const t = barras[foco.i].reduce((s, x) => s + x.n, 0); return <span className="t-sm p-semi">{t === 0 ? "Nenhuma concluída" : t === 1 ? "1 concluída" : `${t} concluídas`}</span>; })()}
                {[...barras[foco.i]].sort((a, b) => b.n - a.n).map((x) => (
                  <span key={x.lista} style={{ display: "flex", alignItems: "center", gap: 6 }}>
                    <span style={{ width: 7, height: 7, borderRadius: 9, background: corDaLista(e, x.lista) }} />
                    <span className="t-xs c2 uma-linha" style={{ flex: 1 }}>{nomeDaLista(e, x.lista)}</span>
                    <span className="t-xs p-semi numeros">{x.n}</span>
                  </span>
                ))}
              </div>
            )}
            <div className="grafico-x">{chaves.map((k, i) => <span key={k}>{mostrarRotulo(i) ? rotuloX(k) : ""}</span>)}</div>
          </div>
        </div>
      )}
      {porLista.length > 0 && (
        <>
          <div style={{ height: 1, background: "var(--borda)" }} />
          <div style={{ display: "flex", gap: "var(--e6)", alignItems: "flex-start" }}>
            <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "var(--e3)" }}>
              <span className="rotulo">Tempo por lista</span>
              {porLista.map(([id, seg]) => (
                <div key={id} style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                  <span style={{ fontSize: 10, color: "var(--texto2)" }}>{nomeDaLista(e, id)}</span>
                  <span style={{ display: "flex", alignItems: "center", gap: 4 }}>
                    <span style={{ height: 6, width: `calc(${(seg / maiorLista) * 100}% - 48px)`, borderRadius: 3, background: corDaLista(e, id) }} />
                    <span className="t-xs p-semi c2">{duracaoCurta(seg)}</span>
                  </span>
                </div>
              ))}
            </div>
            <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
              <span className="rotulo">Onde foi o tempo</span>
              {topo.map(([t, seg]) => (
                <span key={t.id} title={t.concluida ? "Concluída" : "Em aberto"} style={{ display: "flex", alignItems: "center", gap: "var(--e2)" }}>
                  <span style={{ width: 7, height: 7, borderRadius: 9, background: corDaLista(e, t.listaId), flex: "none" }} />
                  <span className={"t-sm uma-linha" + (t.concluida ? " riscado" : "")} style={{ flex: 1 }}>{tituloDe(t)}</span>
                  <span className="t-sm p-semi numeros c2">{duracaoCurta(seg)}</span>
                </span>
              ))}
            </div>
          </div>
          <span className="t-xs c3">Tempo das tarefas concluídas nos últimos {TITULO_PERIODO[periodo]} e das que ainda estão abertas.</span>
        </>
      )}
    </div>
  );
}

export function TelaLista({ id }: { id: string }) {
  const existe = usar((e) => e.listas.some((x) => x.id === id));
  const nome = usar((e) => nomeDaLista(e, id));
  const cor = usar((e) => corDaLista(e, id));
  const ts = usar((e) => raiz(indice(e).porLista.get(id) ?? []).sort((a, b) => (a.posicao < b.posicao ? -1 : 1)), mesmaLista);
  const feitas = usar((e) => indice(e).concluidasPorLista.get(id) ?? [], mesmaLista);
  if (!existe) return <EstadoVazio Icone={ListChecks} titulo="Lista não encontrada" />;
  const editar = () => folhas.abrir("Personalizar lista", <EditorDeLista listaId={id} />, { largura: 440 });
  return (
    <>
      <Cabecalho titulo={nome} sub={textoContagem(ts.length)} esquerda={
        <button className="afunda" title="Personalizar ícone e cor" onClick={editar} style={{ position: "relative", padding: 4, borderRadius: 52 * 0.3 + 4, border: `2.5px solid ${cor}`, display: "inline-flex" }}>
          <LadrilhoLista listaId={id} tamanho={52} />
          <span style={{ position: "absolute", right: -4, bottom: -4, width: 20, height: 20, borderRadius: 99, background: cor, color: "#fff", border: "2px solid var(--fundo)", display: "inline-flex", alignItems: "center", justifyContent: "center" }}><Pencil size={9} strokeWidth={3} /></span>
        </button>
      } />
      <div data-encadeado className="bloco-tela" style={{ ["--i" as string]: 1, display: "flex", flexDirection: "column", gap: "var(--e6)" }}>
        <CampoCelular listaId={id} />
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
      <div data-encadeado className="bloco-tela" style={{ ["--i" as string]: 1, display: "flex", flexDirection: "column", gap: "var(--e6)" }}>
        <div><button className="botao b-superficie" onClick={() => folhas.abrir("Editar etiqueta", <EditorDeEtiqueta id={id} />, { largura: 380 })}><Pencil size={13} /> Editar etiqueta</button></div>
        <CampoCelular etiqueta={id} />
        <Secao titulo="Tarefas" contagem={ts.length}>
          {ts.length ? linhas(ts) : <EstadoVazio Icone={Hash} titulo="Nenhuma tarefa aqui" descricao="Clique com o botão direito numa tarefa → Etiquetas." />}
        </Secao>
      </div>
    </>
  );
}

// MARK: Despejo (DespejoView.swift)

/** Miniatura de uma foto guardada (do aparelho; sem ela, do bucket privado). */
export function Miniatura({ caminho, lado = 40 }: { caminho: string; lado?: number }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    let vivo = true;
    let criada: string | null = null;
    void (async () => {
      const blob = await lerArquivo(`fotos/${caminho}`);
      if (blob) { criada = URL.createObjectURL(blob); if (vivo) setUrl(criada); return; }
      try {
        const { data } = await (await supabase()).storage.from("fotos").createSignedUrl(caminho, 3600);
        if (vivo && data) setUrl(data.signedUrl);
      } catch { /* offline e sem cópia local */ }
    })();
    return () => { vivo = false; if (criada) URL.revokeObjectURL(criada); };
  }, [caminho]);
  return (
    <a className="afunda" href={url ?? undefined} target="_blank" rel="noreferrer" title="Abrir a foto" onClick={(e) => e.stopPropagation()}
      style={{ width: lado, height: lado, flex: "none", borderRadius: "var(--raio-p)", border: "1px solid var(--borda)", overflow: "hidden", background: "var(--superficie2)", display: "block" }}>
      {url && <img src={url} alt="" style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }} />}
    </a>
  );
}

export function CampoDespejo({ compacto = false }: { compacto?: boolean }) {
  const [texto, setTexto] = useState("");
  const [foto, setFoto] = useState<File | null>(null);
  const [previa, setPrevia] = useState<string | null>(null);
  const [confirmacao, setConfirmacao] = useState<string | null>(null);
  const [foco, setFoco] = useState(false);
  const [arrastando, setArrastando] = useState(false);
  const ref = useRef<HTMLTextAreaElement>(null);
  useEffect(() => { if (!foto) { setPrevia(null); return; } const u = URL.createObjectURL(foto); setPrevia(u); return () => URL.revokeObjectURL(u); }, [foto]);
  useEffect(() => { const t = ref.current; if (t) { t.style.height = "auto"; t.style.height = Math.min(t.scrollHeight, 5 * 22) + "px"; } }, [texto]);
  const guardar = async () => {
    let total = 0;
    if (foto) total = despejar(texto, await guardarFoto(foto), true);
    else total = despejar(texto, null, true);
    if (!total) return;
    setFoto(null);
    setTexto("");
    const msg = total === 1 ? "Guardado no despejo" : `${total} itens guardados no despejo`;
    setConfirmacao(msg);
    setTimeout(() => setConfirmacao((c) => (c === msg ? null : c)), 1600);
  };
  return (
    <div className={compacto ? undefined : "cartao"} style={compacto ? undefined : { padding: "var(--e2)" }}>
      <div className="campo-despejo" style={arrastando ? { outline: "1.5px dashed var(--acento)" } : undefined}
        onDragOver={(e) => { e.preventDefault(); setArrastando(true); }} onDragLeave={() => setArrastando(false)}
        onDrop={(e) => { e.preventDefault(); setArrastando(false); const f = [...e.dataTransfer.files].find((x) => x.type.startsWith("image/")); if (f) { setFoto(f); ref.current?.focus(); } }}>
        <Brain size={13} strokeWidth={2.4} style={{ color: foco ? "var(--acento)" : "var(--texto3)", marginTop: 4, flex: "none" }} />
        <textarea ref={ref} rows={1} value={texto} aria-label="Despejo"
          placeholder={foto ? "Por que salvou esta foto?" : compacto ? "Despejar algo…" : "Escreva o que vier — uma coisa por vez, ou cole uma lista"}
          onFocus={() => setFoco(true)} onBlur={() => setFoco(false)} onChange={(e) => setTexto(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); void guardar(); } if (e.key === "Escape") setTexto(""); }} />
        {previa ? (
          <span style={{ position: "relative", flex: "none" }}>
            <img src={previa} alt="" style={{ width: 34, height: 34, objectFit: "cover", borderRadius: "var(--raio-p)", display: "block" }} />
            <button className="afunda" aria-label="Tirar a foto" onClick={() => setFoto(null)} style={{ position: "absolute", top: -5, right: -5, color: "var(--texto2)", background: "var(--superficie)", borderRadius: 99, display: "inline-flex" }}><CircleX size={13} fill="currentColor" stroke="var(--superficie)" /></button>
          </span>
        ) : (
          <label className="afunda" title="Guardar uma foto (ou arraste uma imagem para cá)" style={{ width: 26, height: 26, display: "inline-flex", alignItems: "center", justifyContent: "center", color: "var(--texto3)", cursor: "pointer", flex: "none" }}>
            <ImagePlus size={14} />
            <input type="file" accept="image/*" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) { setFoto(f); ref.current?.focus(); } e.target.value = ""; }} />
          </label>
        )}
      </div>
      {(!compacto || confirmacao || foto) && <div className="t-xs" style={{ padding: "8px 12px 0", color: confirmacao ? "var(--sucesso)" : "var(--texto3)", display: "flex", alignItems: "center", gap: 4 }}>
        {confirmacao ? <><CircleCheck size={12} fill="currentColor" stroke="var(--superficie)" />{confirmacao}</> : foto ? "Escreva por que salvou esta foto (opcional) e aperte Enter." : "Enter guarda e já deixa pronto para o próximo. Sem data, sem lista — organize depois."}
      </div>}
    </div>
  );
}

export function AcoesRapidas({ id, tamanho = 28, depois, mais }: { id: string; tamanho?: number; depois?: () => void; mais?: () => void }) {
  const b = (I: typeof Sun, rotulo: string, f: () => void) => (
    <button className="icone-botao" style={{ width: tamanho, height: tamanho }} title={rotulo} aria-label={rotulo} onClick={(e) => { e.stopPropagation(); f(); depois?.(); }}><I size={13} /></button>
  );
  return (
    <span className="acoes-sobre">
      {b(Zap, "Agora: vira tarefa para hoje", () => fazerAgora(id))}
      {b(Clock, "Depois: importante, mas não agora", () => moverDespejo(id, "depois"))}
      {b(Hand, "Não: decidi não carregar isso", () => moverDespejo(id, "nao"))}
      {mais && b(Ellipsis, "Mais opções (nota, lista e data)", mais)}
    </span>
  );
}

function OpcoesDeTarefa({ texto, criar, cancelar }: { texto: string; criar: (n: { titulo: string; listaId: string | null; prazo: string | null; horario: string | null; etiquetas: string[] }) => void; cancelar: () => void }) {
  const e = usar((x) => x);
  const lido = useMemo(() => lerCriacaoRapida(texto, e.listas, hojeISO()), [texto]);
  const [titulo, setTitulo] = useState(lido.titulo.trim() || texto);
  const [listaId, setListaId] = useState<string | null>(lido.listaId);
  const [prazo, setPrazo] = useState<string | null>(lido.prazo ?? null);
  const [horario, setHorario] = useState<string | null>(null);
  const [listasAbertas, setListasAbertas] = useState(false);
  const [dataAberta, setDataAberta] = useState(false);
  const atual = listaId ?? listaPadrao(e);
  return (
    <div className="entrar" style={{ display: "flex", flexDirection: "column", gap: "var(--e3)" }}>
      <input className="campo" value={titulo} onChange={(x) => setTitulo(x.target.value)} placeholder="Título da tarefa" />
      <div style={{ display: "flex", gap: "var(--e2)" }}>
        {atual && <button className="afunda" onClick={() => { setListasAbertas(!listasAbertas); setDataAberta(false); }}><ChipLista listaId={atual} comSeta aberta={listasAbertas} /></button>}
        <button className="chip afunda" onClick={() => { setDataAberta(!dataAberta); setListasAbertas(false); }}>
          <Calendar size={10} strokeWidth={2.6} />{(prazo ? rotuloCurto(prazo, hojeISO()) : "Sem data") + (horario ? ` · ${horario}` : "")}
        </button>
      </div>
      {listasAbertas && (
        <div className="cartao" style={{ padding: 4, maxWidth: 300 }}>
          {e.listas.map((l) => (
            <button key={l.id} className="linha-nota" style={{ alignItems: "center" }} onClick={() => { setListaId(l.id); setListasAbertas(false); }}>
              <LadrilhoLista listaId={l.id} tamanho={22} /><span className="t-sm p-medio" style={{ flex: 1 }}>{nomeDaLista(e, l.id)}</span>
              {l.id === atual && <Check size={12} strokeWidth={3} color="var(--acento)" />}
            </button>
          ))}
        </div>
      )}
      {dataAberta && (
        <div className="cartao" style={{ padding: 12 }}>
          <SeletorData valor={prazo} aoEscolher={(d) => { setPrazo(d); setDataAberta(false); }} />
          {prazo && <input type="time" className="campo" style={{ marginTop: 8 }} value={horario ?? ""} onChange={(x) => setHorario(x.target.value || null)} />}
        </div>
      )}
      <div style={{ display: "flex", alignItems: "center" }}>
        <button className="botao b-superficie" onClick={cancelar} title="Volta às escolhas">Voltar</button>
        <span style={{ flex: 1 }} />
        <button className="botao m b-primario" disabled={!titulo.trim()} onClick={() => criar({ titulo: titulo.trim(), listaId, prazo, horario: prazo ? horario : null, etiquetas: resolverEtiquetas(lido.etiquetas) })}><Check size={14} /> Criar tarefa</button>
      </div>
    </div>
  );
}

function CartaoDespejo({ item, aberto, abrir, resolvido }: { item: ItemDespejo; aberto: boolean; abrir: () => void; resolvido: () => void }) {
  const [editando, setEditando] = useState(false);
  const [virandoTarefa, setVirandoTarefa] = useState(false);
  useEffect(() => { if (!aberto) setVirandoTarefa(false); }, [aberto]);
  const escolha = (titulo: string, I: typeof Sun, tecla: string, ajuda: string, f: () => void) => (
    <button className="botao m b-superficie largo" title={`${ajuda} (⌘${tecla})`} onClick={() => { f(); resolvido(); }}><I size={14} />{titulo}</button>
  );
  useEffect(() => {
    if (!aberto || virandoTarefa) return;
    const k = (e: KeyboardEvent) => {
      if (e.key === "Escape") abrir();
      if (!(e.metaKey || e.ctrlKey)) return;
      const f = { "1": () => fazerAgora(item.id), "2": () => moverDespejo(item.id, "depois"), "3": () => moverDespejo(item.id, "nao"), "4": () => despejoParaNota(item.id) }[e.key];
      if (f) { e.preventDefault(); f(); resolvido(); }
    };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, [aberto, virandoTarefa, item.id]);
  return (
    <div className={"cartao-despejo" + (aberto ? " aberto" : "")}>
      <div className="linha-despejo">
        {item.foto ? <Miniatura caminho={item.foto} lado={aberto ? 56 : 36} /> : <span style={{ width: 6, height: 6, borderRadius: 9, flex: "none", background: aberto ? "var(--acento)" : "color-mix(in srgb, var(--texto3) 50%, transparent)" }} />}
        {editando ? (
          <textarea autoFocus className="campo-limpo t-md" rows={1} defaultValue={item.texto} style={{ flex: 1, resize: "none" }}
            onBlur={(e) => { setEditando(false); editarDespejo(item.id, e.target.value); }}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); e.currentTarget.blur(); } if (e.key === "Escape") setEditando(false); }} />
        ) : (
          <span className={aberto ? "t-lg p-semi" : "t-md"} style={{ flex: 1, cursor: "pointer", color: item.texto ? "var(--texto)" : "var(--texto3)" }} title="Clique para editar o texto" onClick={() => setEditando(true)}>
            {item.texto || "Foto"}
          </span>
        )}
        {!editando && !aberto && <AcoesRapidas id={item.id} depois={resolvido} mais={() => { setVirandoTarefa(false); abrir(); }} />}
      </div>
      {aberto && (virandoTarefa ? (
        <OpcoesDeTarefa texto={item.texto} cancelar={() => setVirandoTarefa(false)} criar={(n) => { despejoParaTarefa(item.id, n); resolvido(); }} />
      ) : (
        <div className="entrar" style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
          <div style={{ display: "flex", gap: "var(--e2)" }}>
            {escolha("Agora", Zap, "1", "Vira tarefa para hoje", () => fazerAgora(item.id))}
            {escolha("Depois", Clock, "2", "Importante, mas não agora: fica guardado em Depois", () => moverDespejo(item.id, "depois"))}
            {escolha("Não", Hand, "3", "Decidi não carregar isso (fica guardado em Não)", () => moverDespejo(item.id, "nao"))}
            {escolha("Nota", NotepadText, "4", "Vira uma nota, com este texto como título", () => despejoParaNota(item.id))}
          </div>
          <div style={{ display: "flex" }}>
            <button className="botao b-fantasma" onClick={() => setVirandoTarefa(true)} title="Virar tarefa escolhendo a lista, a data e o horário">Escolher lista e data…</button>
            <span style={{ flex: 1 }} />
            <button className="botao b-fantasma" onClick={abrir} title="Fecha o card sem mudar nada (Esc)">Fechar</button>
          </div>
        </div>
      ))}
    </div>
  );
}

function LinhaPilha({ item }: { item: ItemDespejo }) {
  const b = (I: typeof Sun, rotulo: string, f: () => void) => (
    <button className="icone-botao" style={{ width: 28, height: 28 }} title={rotulo} aria-label={rotulo} onClick={f}><I size={13} /></button>
  );
  return (
    <div className="linha-pilha">
      {item.foto && <Miniatura caminho={item.foto} lado={32} />}
      <span style={{ display: "flex", flexDirection: "column", gap: 2, flex: 1, minWidth: 0 }}>
        <span className="t-md" style={{ color: item.texto ? "var(--texto)" : "var(--texto3)" }}>{item.texto || "Foto"}</span>
        <span className="t-xs c3">{primeiraMaiuscula(haQuanto(item.movidoEm ?? item.criadoEm))}</span>
      </span>
      <span className="acoes-sobre">
        {b(Zap, "Agora: vira tarefa para hoje", () => fazerAgora(item.id))}
        {b(ArchiveRestore, "Voltar para a caixa", () => moverDespejo(item.id, "caixa"))}
        {item.estado === "depois" ? b(Hand, "Não: decidi não carregar isso", () => moverDespejo(item.id, "nao")) : b(Clock, "Mover para Depois", () => moverDespejo(item.id, "depois"))}
        {b(Trash2, "Apagar (dá para desfazer)", () => apagarDespejo(item.id))}
      </span>
    </div>
  );
}

function Pilha({ estado }: { estado: "depois" | "nao" }) {
  const itens = usar((e) => e.despejo.filter((d) => d.estado === estado), mesmaLista);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e4)" }}>
      <div style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
        <span className="t-sm c3" style={{ flex: 1 }}>{estado === "depois" ? "Importante, mas não agora. Fica aqui guardado — sem prazo e sem cobrança." : "O que você decidiu não carregar. Uma ideia não precisa ser feita só porque é boa."}</span>
        {estado === "nao" && itens.length > 0 && <button className="botao b-fantasma" onClick={esvaziarNao} title="Apaga de vez os itens desta pilha (dá para desfazer logo depois)">Apagar tudo</button>}
      </div>
      {!itens.length ? (
        <EstadoVazio Icone={estado === "depois" ? Clock : Hand} titulo={estado === "depois" ? "Nada guardado para depois" : "Nada por aqui"}
          descricao={estado === "depois" ? "No despejo, use “Depois” para o que é importante, mas não agora." : "No despejo, use “Não” para o que você decidiu não carregar."} />
      ) : (
        <div className="cartao-linhas fio-curto">{itens.map((i) => <LinhaPilha key={i.id} item={i} />)}</div>
      )}
    </div>
  );
}

export function TelaDespejo() {
  const itens = usar((e) => e.despejo);
  const [pilha, setPilha] = useState<EstadoDespejo>("caixa");
  const [aberto, setAberto] = useState<string | null>(null);
  const [emSequencia, setEmSequencia] = useState(false);
  const [nestaRodada, setNestaRodada] = useState(0);
  const [pausa, setPausa] = useState(false);
  // Mais antigos primeiro: é a ordem em que se organiza.
  const caixa = itens.filter((i) => i.estado === "caixa").sort((a, b) => (a.criadoEm < b.criadoEm ? -1 : 1));
  const n = (e: EstadoDespejo) => itens.filter((i) => i.estado === e).length;
  const comecar = () => { setPausa(false); setNestaRodada(0); setEmSequencia(true); setAberto(caixa[0]?.id ?? null); };
  const parar = () => { setEmSequencia(false); setPausa(false); setAberto(null); };
  const proximo = (id: string) => {
    if (!emSequencia) { if (aberto === id) setAberto(null); return; }
    const feitos = nestaRodada + 1;
    setNestaRodada(feitos);
    const fila = caixa.filter((i) => i.id !== id);
    if (!fila.length) { setEmSequencia(false); setAberto(null); }
    else if (feitos >= 3) { setEmSequencia(false); setAberto(null); setPausa(true); }
    else setAberto(fila[0].id);
  };
  return (
    <>
      <Cabecalho titulo="Despejo" sub="Tire da cabeça. Organize depois." />
      <div data-encadeado className="bloco-tela" style={{ ["--i" as string]: 1, display: "flex", flexDirection: "column", gap: "var(--e5)" }}>
        <CampoDespejo />
        <div style={{ alignSelf: "flex-start", display: "flex", width: "100%" }}>
          <Segmentado rotulo="Pilha" valor={pilha} aoMudar={(p) => { setPilha(p); parar(); }} opcoes={(["caixa", "depois", "nao"] as const).map((p) => [p, `${{ caixa: "Caixa", depois: "Depois", nao: "Não" }[p]} · ${n(p)}`] as [EstadoDespejo, string])} />
        </div>
        {pilha !== "caixa" ? <Pilha estado={pilha} /> : !caixa.length ? (
          <EstadoVazio Icone={Brain} titulo="Cabeça leve" descricao="Escreva aqui tudo o que estiver ocupando espaço. Depois, com calma, decida: Agora, Depois ou Não." />
        ) : (
          <>
            <div style={{ display: "flex", alignItems: "center" }}>
              <span className="t-sm p-medio c3" style={{ flex: 1 }}>{caixa.length === 1 ? "1 coisa para organizar" : `${caixa.length} coisas para organizar`}</span>
              {emSequencia
                ? <button className="botao m b-superficie" onClick={parar} title="Sai do modo de organizar; os itens ficam como estão">Parar</button>
                : <button className="botao m b-primario" onClick={comecar} title="Abre um item por vez, do mais antigo, de 3 em 3 — sem precisar esvaziar tudo"><Layers2 size={14} />{caixa.length > 3 ? "Organizar 3" : "Organizar"}</button>}
            </div>
            {pausa && (
              <div className="entrar" style={{ display: "flex", alignItems: "center", gap: 12, padding: 16, borderRadius: "var(--raio-cartao)", background: "var(--sucesso-tenue)" }}>
                <BadgeCheck size={18} color="var(--sucesso)" />
                <span style={{ display: "flex", flexDirection: "column", gap: 2, flex: 1 }}>
                  <span className="t-sm p-semi">Pronto, 3 organizadas.</span>
                  <span className="t-xs c3">Pode parar aqui. O resto espera.</span>
                </span>
                <button className="botao b-fantasma" onClick={parar}>Por hoje chega</button>
                <button className="botao b-primario" onClick={comecar}>Mais 3</button>
              </div>
            )}
            <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
              {caixa.map((i) => <CartaoDespejo key={i.id} item={i} aberto={aberto === i.id} abrir={() => setAberto(aberto === i.id ? null : i.id)} resolvido={() => proximo(i.id)} />)}
            </div>
          </>
        )}
      </div>
    </>
  );
}

// MARK: Notas (NotasView.swift)

const relativo = new Intl.RelativeTimeFormat("pt-BR", { numeric: "auto" });
function haQuanto(iso: string): string {
  const s = (new Date(iso).getTime() - Date.now()) / 1000;
  const a = Math.abs(s);
  if (a < 60) return relativo.format(Math.round(s), "second");
  if (a < 3600) return relativo.format(Math.round(s / 60), "minute");
  if (a < 86400) return relativo.format(Math.round(s / 3600), "hour");
  return relativo.format(Math.round(s / 86400), "day");
}
const tituloDaNota = (n: { titulo: string; texto: string; dia: string | null }) =>
  n.titulo.trim() || (n.dia ? rotuloLongo(n.dia) : n.texto.split("\n").map((l) => l.trim()).find(Boolean) ?? "Sem título");
const mesmoAlvo = (a: AlvoNota | null, b: AlvoNota) => !!a && ("dia" in a ? "dia" in b && a.dia === b.dia : "nota" in b && a.nota === b.nota);

function LinhaNota({ titulo, detalhe, Icone, selecionada, aoClicar }: { titulo: string; detalhe: string; Icone: typeof Sun; selecionada: boolean; aoClicar: () => void }) {
  return (
    <button className="linha-nota" aria-current={selecionada} onClick={aoClicar} title={`Abrir “${titulo}”`}>
      <Icone size={14} style={{ color: selecionada ? "var(--acento)" : "var(--texto3)", marginTop: 2, flex: "none", width: 18 }} />
      <span style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0 }}>
        <span className="t-sm p-semi uma-linha">{titulo}</span>
        <span className="t-xs c3 uma-linha">{detalhe}</span>
      </span>
    </button>
  );
}

export function TelaNotas({ id }: { id?: string }) {
  const notas = usar((e) => e.notas);
  const alvo = useNotaAberta();
  const hoje = hojeISO();
  const celular = useCelular();
  // No celular a lista é a tela; a nota abre por cima só quando a pessoa escolhe uma.
  const [escolhida, setEscolhida] = useState(!!id);
  useEffect(() => {
    if (id) abrirNota({ nota: id });
    else if (!alvo && !celular) abrirNota({ dia: hoje });
  }, [id]);
  useEffect(() => { if (alvo) setEscolhida(true); }, [alvo]);
  const anterior = useRef(alvo);
  useEffect(() => {
    // Nota solta criada e deixada em branco não fica acumulando.
    const a = anterior.current;
    if (a && "nota" in a && !mesmoAlvo(alvo, a)) descartarSeVazia(a.nota);
    anterior.current = alvo;
  }, [alvo]);
  const ordenadas = [...notas].sort((a, b) => (b.dia && a.dia ? (a.dia < b.dia ? 1 : -1) : a.editadaEm < b.editadaEm ? 1 : -1));
  const resumo = (n: (typeof notas)[number]) => {
    const t = tituloDaNota(n);
    const corpo = n.texto.split("\n").map((l) => l.trim()).find((l) => l && l !== t) ?? "";
    const quando = n.dia ? rotuloCurto(n.dia, hoje) : haQuanto(n.editadaEm);
    return corpo ? `${quando} · ${corpo}` : quando;
  };
  const existe = alvo && ("dia" in alvo || notas.some((n) => n.id === alvo.nota));
  return (
    <div className="tela-notas" data-editando={alvo && (!celular || escolhida) ? "" : undefined} style={{ display: "flex", flex: 1, minWidth: 0, height: "100%" }}>
      <div className="lista-notas">
        <div style={{ display: "flex", alignItems: "center", gap: 4, padding: "44px 20px 16px" }}>
          <div style={{ display: "flex", flexDirection: "column", gap: 3, flex: 1 }}>
            <h1 className="display d-display2">Notas</h1>
            <span className="t-sm c3">{notas.length} {notas.length === 1 ? "nota" : "notas"}</span>
          </div>
          <button className="icone-botao" title="Revisão da semana (nota pronta com o que foi feito e o que ficou)" aria-label="Revisão da semana" onClick={() => abrirNota({ nota: revisaoDaSemana() })}><CalendarCheck size={14} /></button>
          <button className="icone-botao" title="Nova nota" aria-label="Nova nota" onClick={() => abrirNota({ nota: novaNota() })}><SquarePen size={14} /></button>
        </div>
        <Rolagem casca="casca-flex" style={{ flex: 1, overflow: "auto", padding: "0 12px 20px", display: "flex", flexDirection: "column", gap: 2 }}>
          {!notas.some((n) => n.dia === hoje) && <LinhaNota titulo="Hoje" detalhe="Escrever a nota do dia" Icone={Sun} selecionada={mesmoAlvo(alvo, { dia: hoje })} aoClicar={() => abrirNota({ dia: hoje })} />}
          {ordenadas.map((n) => {
            const a: AlvoNota = n.dia ? { dia: n.dia } : { nota: n.id };
            return <LinhaNota key={n.id} titulo={n.dia === hoje ? "Hoje" : tituloDaNota(n)} detalhe={resumo(n)} Icone={n.dia ? Calendar : NotepadText} selecionada={mesmoAlvo(alvo, a)} aoClicar={() => abrirNota(a)} />;
          })}
        </Rolagem>
      </div>
      <div className="editor-nota">
        {existe && alvo ? <EditorDeNota key={"dia" in alvo ? "d" + alvo.dia : "n" + alvo.nota} alvo={alvo} /> : (
          <div style={{ margin: "auto" }}><EstadoVazio Icone={NotepadText} titulo="Escolha ou crie uma nota" descricao="A nota do dia é um diário de planejamento: o que você quer da semana, como foi hoje. Escreva [ ] no começo da linha para virar tarefa." /></div>
        )}
      </div>
    </div>
  );
}

function EditorDeNota({ alvo }: { alvo: AlvoNota }) {
  const nota = usar((e) => e.notas.find((n) => ("dia" in alvo ? n.dia === alvo.dia : n.id === alvo.nota)) ?? null);
  const listaPadraoNome = usar((e) => { const l = e.prefs.listaPadrao ?? e.listas[0]?.id; return l ? nomeDaLista(e, l) : null; });
  const [texto, setTexto] = useState(nota?.texto ?? "");
  const hoje = hojeISO();
  const dia = "dia" in alvo ? alvo.dia : null;
  // A nota pode mudar por fora (ex.: "[ ]" virou "→" ao criar a tarefa).
  useEffect(() => { if (nota && nota.texto !== texto) setTexto(nota.texto); }, [nota?.texto]);
  const salvar = (v: string) => {
    setTexto(v);
    if (dia) escreverNoDia(dia, v);
    else if (nota) atualizarNota(nota.id, { texto: v });
  };
  const pend = pendentesDaNota(texto);
  const area = useRef<HTMLTextAreaElement>(null);
  useEffect(() => { const t = area.current; if (t) { t.style.height = "auto"; t.style.height = Math.max(320, t.scrollHeight) + "px"; } }, [texto]);
  return (
    <>
      <div style={{ display: "flex", alignItems: "center", gap: 4, height: 52, padding: "16px 24px 0" }}>
        <button className="icone-botao so-celular" aria-label="Voltar" style={{ marginLeft: -12 }} onClick={() => abrirNota(null)}><ChevronLeft size={20} /></button>
        {nota && <span className="t-xs c3">Editada {haQuanto(nota.editadaEm)}</span>}
        <span style={{ flex: 1 }} />
        {nota && <button className="icone-botao" aria-label="Excluir nota" title="Excluir nota" onClick={() => folhas.confirmar("Excluir nota", `“${tituloDaNota(nota)}” será excluída. Dá para desfazer logo depois.`, () => { abrirNota(null); excluirNota(nota.id); })}><Trash2 size={14} /></button>}
      </div>
      <Rolagem casca="casca-flex" fundo="var(--superficie)" style={{ flex: 1, overflow: "auto", padding: "0 24px 32px", display: "flex", flexDirection: "column", gap: 16 }}>
        {dia ? (
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <span className="rotulo">{rotuloLongo(dia)}</span>
            <span className="display d-titulo">{rotuloCurto(dia, hoje)}</span>
          </div>
        ) : (
          <input className="campo-limpo display d-titulo" placeholder="Título" defaultValue={nota?.titulo ?? ""} onChange={(e) => nota && atualizarNota(nota.id, { titulo: e.target.value })} />
        )}
        <textarea ref={area} className="campo-limpo t-md" value={texto} onChange={(e) => salvar(e.target.value)} style={{ resize: "none", minHeight: 320, lineHeight: 1.45, overflow: "hidden" }}
          placeholder={dia ? "Como está o dia? O que você quer fazer? [ ] no começo da linha vira tarefa." : "Escreva livremente. [ ] no começo da linha vira tarefa."} />
        {pend.length > 0 && nota && (
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <div style={{ display: "flex", alignItems: "center" }}>
              <span className="rotulo" style={{ flex: 1 }}>Viram tarefa</span>
              {pend.length > 1 && <button className="botao b-fantasma" onClick={() => [...pend].reverse().forEach((p) => tarefaDaLinha(nota.id, p.linha))}>Criar todas</button>}
            </div>
            <div style={{ padding: 4, background: "var(--superficie2)", borderRadius: "var(--raio-m)", display: "flex", flexDirection: "column", gap: 1 }}>
              {pend.map((p) => (
                <div key={p.linha} style={{ display: "flex", alignItems: "center", gap: 12, padding: "6px 12px" }}>
                  <Circle size={13} className="c3" />
                  <span className="t-sm" style={{ flex: 1 }}>{p.titulo}</span>
                  <button className="botao b-superficie" onClick={() => tarefaDaLinha(nota.id, p.linha)}>Criar tarefa</button>
                </div>
              ))}
            </div>
            {listaPadraoNome && <span className="t-xs c3">Vão para “{listaPadraoNome}”{nota.dia ? `, com a data ${rotuloCurto(nota.dia, hoje).toLowerCase()}` : ""}.</span>}
          </div>
        )}
      </Rolagem>
    </>
  );
}

// MARK: Ajustes (SettingsView.swift): lista de assuntos (pastas), na ordem em que se procura.

function Pasta({ Icone, titulo, subtitulo, aberta = false, children }: { Icone: typeof Sun; titulo: string; subtitulo: string; aberta?: boolean; children: ReactNode }) {
  const [aberto, setAberto] = useState(aberta);
  return (
    <div className="pasta">
      <button className="pasta-cabecalho sem-veu sem-afundar" aria-expanded={aberto} title={(aberto ? "Recolher " : "Mostrar ") + titulo.toLowerCase()} onClick={() => setAberto(!aberto)}>
        <Icone size={16} strokeWidth={1.9} className="c2" style={{ width: 22, flex: "none" }} />
        <span style={{ display: "flex", flexDirection: "column", gap: 1, flex: 1, minWidth: 0, textAlign: "left" }}>
          <span className="t-sm p-semi">{titulo}</span>
          <span className="t-xs c3 uma-linha">{subtitulo}</span>
        </span>
        <ChevronDown size={12} strokeWidth={2.6} className="c3" style={{ transform: aberto ? "rotate(180deg)" : undefined, transition: "transform var(--normal) var(--curva)" }} />
      </button>
      {aberto && <div className="pasta-corpo entrar">{children}</div>}
    </div>
  );
}

function LinhaAjuste({ titulo, descricao, children }: { titulo: string; descricao?: string; children?: ReactNode }) {
  return (
    <div className="linha-ajuste">
      <span className="linha-ajuste-texto">
        <span className="t-sm p-medio">{titulo}</span>
        {descricao && <span className="t-xs c3">{descricao}</span>}
      </span>
      {children}
    </div>
  );
}

const Chave = ({ ligada, rotulo, aoMudar }: { ligada: boolean; rotulo: string; aoMudar: () => void }) => (
  <button className="chave" role="switch" aria-checked={ligada} aria-label={rotulo} onClick={aoMudar} />
);

function exportarDados() {
  const e = lerEstado();
  const dados = { versao: 1, exportadoEm: new Date().toISOString(), listas: e.listas, tarefas: Object.values(e.tarefas), etiquetas: e.etiquetas, etiquetasDaTarefa: e.etiquetasDaTarefa, notas: e.notas, despejo: e.despejo, tempos: e.tempos };
  const url = URL.createObjectURL(new Blob([JSON.stringify(dados, null, 2)], { type: "application/json" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = `Tasker ${new Date().toLocaleDateString("pt-BR").replace(/\//g, "-")}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

async function importarDados(arquivo: File): Promise<number> {
  const d = JSON.parse(await arquivo.text()) as { tarefas?: { titulo: string; notas?: string; prazo?: string | null; concluida?: boolean }[] };
  if (!Array.isArray(d.tarefas)) throw new Error("formato");
  let n = 0;
  for (const t of d.tarefas) if (t.titulo && !t.concluida) { criarTarefa({ titulo: t.titulo, notas: t.notas, prazo: t.prazo ?? null, silencioso: true }); n++; }
  return n;
}

export function TelaAjustes() {
  const e = usar((x) => x);
  const [tema, setTema] = useState<Tema>(() => (localStorage.getItem("tasker.tema") as Tema) || "sistema");
  const [msgDados, setMsgDados] = useState<[string, "info" | "erro"] | null>(null);
  const [listasAbertas, setListasAbertas] = useState(false);
  const mudarTema = (t: Tema) => { setTema(t); localStorage.setItem("tasker.tema", t); aplicarTema(); };
  const p = e.prefs;
  const alternar = (k: "contarAtrasadas" | "mostrarEventosNoMenu" | "mostrarAtrasadasNoMenu" | "somAoConcluir" | "energiaBaixa") => mudarPrefs((x) => ({ [k]: !x[k] }));
  const n = contagemHoje(e);
  const padrao = listaPadrao(e);
  const atualizacao = useAtualizacao();
  const versao = atualizacao?.atual ?? (import.meta.env.VITE_VERSAO as string | undefined) ?? "web";
  return (
    <>
      <Cabecalho titulo="Ajustes" sub={`Tasker ${versao}`} />
      <div data-encadeado className="bloco-tela" style={{ ["--i" as string]: 1, display: "flex", flexDirection: "column", gap: "var(--e3)" }}>
        <AvisoAtualizacao />
        <Pasta Icone={CircleUserRound} titulo="Conta" subtitulo={e.modo === "local" ? "Usando só neste aparelho" : e.email ?? "Google"} aberta>
          {e.modo === "local" ? (
            <>
              <Nota texto="Suas tarefas estão guardadas só neste aparelho. Conecte o Google para sincronizar com o celular e o Mac — depois use Dados → Importar para levar as tarefas de agora." />
              <button className="botao m b-primario largo" onClick={() => void entrarComGoogle()}><CircleUserRound size={15} />Entrar com Google</button>
            </>
          ) : (
            <>
              <div style={{ display: "flex", alignItems: "center", gap: "var(--e3)" }}>
                <span style={{ width: 40, height: 40, borderRadius: 99, overflow: "hidden", background: "var(--superficie2)", border: "1px solid var(--borda)", display: "inline-flex", alignItems: "center", justifyContent: "center", flex: "none" }} className="t-lg p-semi c2">
                  {e.avatar ? <img src={e.avatar} alt="" width={40} height={40} /> : (e.nome ?? e.email ?? "?")[0].toUpperCase()}
                </span>
                <span style={{ display: "flex", flexDirection: "column", gap: 2, flex: 1, minWidth: 0 }}>
                  <span className="t-sm p-semi">{e.nome ?? "Conta Google"}</span>
                  <span className="t-xs c3 uma-linha">{e.email}</span>
                </span>
                <button className="botao b-superficie" style={{ flex: "none" }} onClick={() => folhas.confirmar("Sair da conta", "As tarefas continuam no Google e o resto no servidor. Neste aparelho, tudo sai até você entrar de novo.", () => void sair(), "Sair")}>Sair</button>
              </div>
              {e.googlePendente && (
                <Nota tom="aviso" texto="O Google precisa ser reconectado para as tarefas e a agenda voltarem a sincronizar.">
                  <div><button className="botao b-primario" onClick={() => void reconectarGoogle()}>Reconectar</button></div>
                </Nota>
              )}
              <LinhaAjuste titulo="Alterações esperando a rede" descricao={e.pendencias ? "Sobem sozinhas quando a internet voltar" : "Tudo já está no servidor"}>
                <span className="t-sm p-semi numeros c2">{e.pendencias}</span>
              </LinhaAjuste>
            </>
          )}
        </Pasta>

        <Pasta Icone={Paintbrush} titulo="Aparência" subtitulo="Tema, contador e o que aparece no menu">
          <LinhaAjuste titulo="Tema" descricao="Vale para a janela e para o menu da barra">
            <Segmentado rotulo="Tema" valor={tema} aoMudar={mudarTema} opcoes={(["sistema", "claro", "escuro"] as const).map((t) => [t, primeiraMaiuscula(t)] as [Tema, string])} />
          </LinhaAjuste>
          <LinhaAjuste titulo="Contar atrasadas" descricao={`Agora: ${n} tarefa${n === 1 ? "" : "s"}`}><Chave ligada={p.contarAtrasadas} rotulo="Contar atrasadas" aoMudar={() => alternar("contarAtrasadas")} /></LinhaAjuste>
          <LinhaAjuste titulo="Eventos no menu" descricao="Mostrar a agenda do dia acima das tarefas"><Chave ligada={p.mostrarEventosNoMenu} rotulo="Eventos no menu" aoMudar={() => alternar("mostrarEventosNoMenu")} /></LinhaAjuste>
          <LinhaAjuste titulo="Atrasadas no menu" descricao="Mostrar a seção “Em atraso”"><Chave ligada={p.mostrarAtrasadasNoMenu} rotulo="Atrasadas no menu" aoMudar={() => alternar("mostrarAtrasadasNoMenu")} /></LinhaAjuste>
        </Pasta>

        <Pasta Icone={ListChecks} titulo="Tarefas" subtitulo="Lista padrão, som e energia">
          <LinhaAjuste titulo="Lista padrão" descricao="Para onde vão as tarefas novas">
            <span style={{ position: "relative" }}>
              {padrao && <button className="afunda" onClick={() => setListasAbertas(!listasAbertas)}><ChipLista listaId={padrao} /></button>}
              {listasAbertas && <div style={{ position: "absolute", right: 0, top: 30, zIndex: 5, width: 240 }}><DropdownListas atual={padrao} aoEscolher={(id) => { mudarPrefs(() => ({ listaPadrao: id })); setListasAbertas(false); }} /></div>}
            </span>
          </LinhaAjuste>
          <LinhaAjuste titulo="Som ao concluir"><Chave ligada={p.somAoConcluir} rotulo="Som ao concluir" aoMudar={() => alternar("somAoConcluir")} /></LinhaAjuste>
          <LinhaAjuste titulo="Estou sem energia" descricao="O Hoje mostra uma coisa por vez, sem atrasadas e sem número na barra"><Chave ligada={p.energiaBaixa} rotulo="Estou sem energia" aoMudar={() => alternar("energiaBaixa")} /></LinhaAjuste>
        </Pasta>

        {e.modo === "conta" && (
          <Pasta Icone={Calendar} titulo="Agenda e sincronização" subtitulo="Quais agendas aparecem">
            {!e.agendas.length && <Nota texto="Nenhuma agenda carregada ainda." />}
            {e.agendas.map((a) => (
              <LinhaAjuste key={a.id} titulo={a.titulo}>
                <Chave ligada={p.agendasVisiveis[a.id] !== false} rotulo={a.titulo} aoMudar={() => mudarPrefs((x) => ({ agendasVisiveis: { ...x.agendasVisiveis, [a.id]: x.agendasVisiveis[a.id] === false } }))} />
              </LinhaAjuste>
            ))}
            <div style={{ display: "flex", justifyContent: "flex-end" }}><button className="botao b-superficie" onClick={() => void puxar(true)}>Sincronizar agora</button></div>
          </Pasta>
        )}

        <Pasta Icone={HardDrive} titulo="Dados" subtitulo="Exportar e importar listas, tarefas e etiquetas">
          <LinhaAjuste titulo="Exportar tudo" descricao="Um arquivo .json para guardar ou levar a outro aparelho"><button className="botao b-superficie" onClick={exportarDados}>Exportar…</button></LinhaAjuste>
          <LinhaAjuste titulo="Importar" descricao="Junta um arquivo exportado às suas listas">
            <label className="botao b-superficie" style={{ cursor: "pointer" }}>Importar…
              <input type="file" accept="application/json,.json" hidden onChange={async (x) => {
                const f = x.target.files?.[0];
                x.target.value = "";
                if (!f) return;
                try { const total = await importarDados(f); setMsgDados([`${total} tarefa${total === 1 ? "" : "s"} importada${total === 1 ? "" : "s"}.`, "info"]); }
                catch { setMsgDados(["Esse arquivo não pôde ser importado. Use um arquivo exportado pelo Tasker.", "erro"]); }
              }} />
            </label>
          </LinhaAjuste>
          {msgDados && <Nota texto={msgDados[0]} tom={msgDados[1]} />}
        </Pasta>

        <Pasta Icone={Settings} titulo="Geral" subtitulo={`Atalhos e versão ${versao}`}>
          <LinhaAjuste titulo="Nova tarefa"><span className="tecla">N</span></LinhaAjuste>
          <LinhaAjuste titulo="Buscar"><span className="tecla">⌘ K</span></LinhaAjuste>
          <LinhaAjuste titulo="Criação rápida" descricao="hoje · amanhã · sexta · 30/10 · ~lista · #etiqueta" />
          {atualizacao && (
            <>
              <AvisoAtualizacao />
              <LinhaAjuste titulo={`Versão ${atualizacao.atual}`} descricao={atualizacao.estado === "emDia" ? "Em dia" : atualizacao.estado === "procurando" ? "Procurando…" : atualizacao.estado === "erro" ? atualizacao.erro : undefined}>
                <button className="botao b-superficie" onClick={procurarAtualizacao}>Procurar atualização</button>
              </LinhaAjuste>
            </>
          )}
          <LinhaAjuste titulo="Funciona sem internet" descricao="Tudo fica guardado neste aparelho e sobe quando a rede voltar" />
        </Pasta>
      </div>
    </>
  );
}

// MARK: Entrar (OnboardingView.swift)

export function TelaEntrar() {
  return (
    <div style={{ height: "100%", overflow: "auto" }}>
      <div className="tela-entrar">
        <div className="entrar" style={{ display: "flex", flexDirection: "column", gap: "var(--e3)" }}>
          <span className="simbolo" style={{ width: 52, height: 52, borderRadius: 52 * 0.28 }}><Check size={26} strokeWidth={4} /></span>
          <h1 className="display d-display">Bem-vindo ao Tasker</h1>
          <p className="t-lg c2">Suas tarefas e os eventos do dia, no Mac, no celular e no navegador — também sem internet.</p>
        </div>
        <div className="cartao entrar-2" style={{ padding: "var(--e5)", display: "flex", flexDirection: "column", gap: "var(--e4)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "var(--e3)" }}>
            <span style={{ width: 36, height: 36, borderRadius: "var(--raio-m)", background: "color-mix(in srgb, var(--acento) 12%, transparent)", color: "var(--acento)", display: "inline-flex", alignItems: "center", justifyContent: "center", fontWeight: 800 }}>G</span>
            <span style={{ display: "flex", flexDirection: "column", gap: 2 }}>
              <span className="t-md p-semi">Conectar Google Tasks e Agenda</span>
              <span className="t-sm c3">Sincroniza com o celular, com o Mac e com o navegador.</span>
            </span>
          </div>
          <button className="botao m b-primario largo" onClick={() => void entrarComGoogle()}><CircleUserRound size={15} />Entrar com Google</button>
        </div>
        <div className="cartao entrar-2 cartao-opcao">
          <span style={{ width: 36, height: 36, borderRadius: "var(--raio-m)", background: "var(--superficie2)", color: "var(--texto2)", display: "inline-flex", alignItems: "center", justifyContent: "center", flex: "none" }}><Laptop size={16} strokeWidth={2.2} /></span>
          <span className="cartao-opcao-texto">
            <span className="t-md p-semi">Usar sem conta</span>
            <span className="t-sm c3">Tudo fica só neste aparelho. Dá para exportar e conectar o Google depois.</span>
          </span>
          <button className="botao m b-superficie" onClick={usarSemConta}>Começar</button>
        </div>
      </div>
    </div>
  );
}
