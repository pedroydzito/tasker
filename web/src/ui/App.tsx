import { PuxarParaAtualizar } from "./puxar";
import { DicaDePrimeiraVez } from "./dicas";
import { moverTarefa } from "../dados/acoes";
import { HospedeDoContexto } from "./contexto";
import { CampoTarefa } from "./campo";
import { CriadorDeEtiqueta, HospedeDeFolhas, NovaLista, folhas } from "./folhas";
import { Suspense, lazy, useEffect, useRef, useState, type ComponentType } from "react";
import { ChevronUp, CircleAlert, Trash2, Circle, Brain, CalendarDays, ChartGantt, Check, ChevronDown, CircleCheck, CircleUserRound, CloudOff, Download, Hash, Inbox, NotepadText, Plus, RefreshCw, Search, Settings, Sun, Sunrise, X } from "lucide-react";
import { usar } from "../dados/armazem";
import { desfazerAgora, textoDoAviso, useAviso } from "../dados/avisos";
import { buscar, contagemHoje, corDaLista, etiquetasOrdenadas, indice, nomeDaLista } from "../dados/consultas";
import { puxar } from "../dados/sync";
import { diaISO, hojeISO, rotuloCurto, somarDias } from "../dados/util";
import { useCelular, LadrilhoLista, Rolagem, querMenosMovimento, useTrilho } from "./comuns";
import { Inspetor } from "./Inspetor";
import { abrirNota, irPara, selecionar, useRota, useSelecionada, type Rota } from "./rota";
import { TelaAmanha, TelaHoje } from "./hoje";

// Telas que não são a de abertura chegam sob demanda (desempenho §3) — e são pedidas no
// primeiro ocioso, para a troca de tela já encontrar o código na mão (§11.4).
const telas = () => import("./telas");
const preguicosa = <K extends keyof Awaited<ReturnType<typeof telas>>>(k: K) =>
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  lazy(() => telas().then((m) => ({ default: m[k] as unknown as ComponentType<any> })));
const TelaAjustes = preguicosa("TelaAjustes") as ComponentType;
const TelaCalendario = preguicosa("TelaCalendario") as ComponentType;
const TelaConcluidas = preguicosa("TelaConcluidas") as ComponentType;
const TelaDespejo = preguicosa("TelaDespejo") as ComponentType;
const TelaEntrar = preguicosa("TelaEntrar") as ComponentType;
const TelaProximas = preguicosa("TelaProximas") as ComponentType;
const TelaTodas = preguicosa("TelaTodas") as ComponentType;
const TelaEtiqueta = preguicosa("TelaEtiqueta") as ComponentType<{ id: string }>;
const TelaLista = preguicosa("TelaLista") as ComponentType<{ id: string }>;
const TelaNotas = preguicosa("TelaNotas") as ComponentType<{ id?: string }>;
const Menu = lazy(() => import("./Menu").then((m) => ({ default: m.Menu })));
if (typeof window !== "undefined") ("requestIdleCallback" in window ? requestIdleCallback : setTimeout)(() => void telas());

/** Enquanto o código da tela chega: o formato do cabeçalho e de um cartão (§10.6). */
let esperou = false;
function EsperaTela() {
  esperou = true;
  return (
    <div className="esqueleto-casca" style={{ height: "auto" }} aria-hidden>
      <div className="esqueleto-conteudo" style={{ padding: 0, margin: 0 }}>
        <i className="e-titulo" /><i className="e-sub" />
        <div className="e-cartao"><i /><i /><i /></div>
      </div>
    </div>
  );
}

/** Esqueleto → conteúdo sem pulo: quando a tela esperou o código, ela entra num fade curto (troca suave). */
function TrocaSuave() {
  const ref = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    if (!esperou) return;
    esperou = false;
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    ref.current?.parentElement?.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 180, easing: "ease-out" });
  }, []);
  return <span ref={ref} hidden />;
}

const ITENS: { tela: Rota["tela"]; rotulo: string; I: typeof Sun }[] = [
  { tela: "hoje", rotulo: "Hoje", I: Sun },
  { tela: "amanha", rotulo: "Amanhã", I: Sunrise },
  { tela: "proximas", rotulo: "Próximas", I: ChartGantt },
  { tela: "calendario", rotulo: "Calendário", I: CalendarDays },
  { tela: "todas", rotulo: "Todas", I: Inbox },
  { tela: "concluidas", rotulo: "Concluídas", I: CircleCheck },
  { tela: "despejo", rotulo: "Despejo", I: Brain },
  { tela: "notas", rotulo: "Notas", I: NotepadText },
];

function lerBool(chave: string) {
  try {
    return localStorage.getItem(chave) === "1";
  } catch {
    return false;
  }
}
function useRecolhida(chave: string): [boolean, () => void] {
  const [v, setV] = useState(() => lerBool(chave));
  return [v, () => {
    setV(!v);
    try {
      localStorage.setItem(chave, v ? "0" : "1");
    } catch {
      /* nada */
    }
  }];
}

function CabecalhoSecaoLateral({ titulo, recolhida, alternar, acao }: { titulo: string; recolhida: boolean; alternar: () => void; acao?: () => void }) {
  return (
    <div className="secao-lateral">
      <button className="afunda" onClick={alternar} title={(recolhida ? "Mostrar " : "Recolher ") + titulo.toLowerCase()}>
        <span className="rotulo">{titulo}</span>
        <ChevronDown size={9} strokeWidth={3.2} className="c3" style={{ transform: recolhida ? "rotate(-90deg)" : undefined, transition: "transform var(--normal) var(--curva)" }} />
      </button>
      <span style={{ flex: 1 }} />
      {acao && <button className="icone-botao" style={{ width: 22, height: 22 }} aria-label={"Nova " + titulo.toLowerCase().replace(/s$/, "")} onClick={acao}><Plus size={11} strokeWidth={2.5} /></button>}
    </div>
  );
}

function ItemLateral({ ativo, tinta, titulo, contagem, icone, aoClicar, aoSoltar }: { ativo: boolean; tinta?: string; titulo: string; contagem?: number | null; icone: React.ReactNode; aoClicar: () => void; aoSoltar?: (tarefa: string) => void }) {
  const [alvo, setAlvo] = useState(false);
  return (
    <button
      className={"item-lateral sem-veu" + (ativo ? " ativo" : "") + (alvo ? " alvo-soltar" : "")}
      aria-current={ativo}
      style={{ ["--tinta" as string]: tinta ? `color-mix(in srgb, ${tinta} 16%, transparent)` : "var(--superficie2)", ["--cor-alvo" as string]: tinta ?? "var(--acento)" }}
      onClick={aoClicar}
      onDragOver={aoSoltar ? (ev) => { if (ev.dataTransfer.types.includes("text/tasker-tarefa")) { ev.preventDefault(); setAlvo(true); } } : undefined}
      onDragLeave={aoSoltar ? () => setAlvo(false) : undefined}
      onDrop={aoSoltar ? (ev) => { ev.preventDefault(); setAlvo(false); const id = ev.dataTransfer.getData("text/tasker-tarefa"); if (id) aoSoltar(id); } : undefined}
      title={contagem ? `${titulo} · ${contagem}` : titulo}
    >
      <span className="icone">{icone}</span>
      <span className="uma-linha" style={{ flex: 1 }}>{titulo}</span>
      {!!contagem && contagem > 0 && <span className="conta">{contagem}</span>}
    </button>
  );
}

function StatusSync() {
  const sinc = usar((e) => e.sincronizando);
  const ultima = usar((e) => e.ultimaSync);
  const online = usar((e) => e.online);
  const pend = usar((e) => e.pendencias);
  const modo = usar((e) => e.modo);
  const [, tique] = useState(0);
  useEffect(() => {
    const i = setInterval(() => tique((n) => n + 1), 30_000);
    return () => clearInterval(i);
  }, []);
  let texto = "Sincronizar";
  if (modo === "local") texto = "Só neste aparelho";
  else if (!online) texto = pend ? `Offline · ${pend} na fila` : "Offline";
  else if (sinc) texto = "Sincronizando…";
  else if (ultima) {
    const s = (Date.now() - new Date(ultima).getTime()) / 1000;
    texto = s < 60 ? "Sincronizado agora" : s < 3600 ? `Sincronizado há ${Math.floor(s / 60)} min` : `Sincronizado há ${Math.floor(s / 3600)} h`;
  }
  return (
    <button className={"sync" + (sinc ? " girando" : "")} onClick={() => void puxar(true)} title="Sincronizar agora">
      {online ? <RefreshCw size={11} strokeWidth={2.6} /> : <CloudOff size={11} strokeWidth={2.6} />}
      <span className="uma-linha">{texto}</span>
    </button>
  );
}

function Lateral({ rota, aoBuscar }: { rota: Rota; aoBuscar: () => void }) {
  const e = usar((x) => x);
  const [cadernoFechado, alternarCaderno] = useRecolhida("sidebar.cadernoCollapsed");
  const [listasFechadas, alternarListas] = useRecolhida("sidebar.listsCollapsed");
  const [etiquetasFechadas, alternarEtiquetas] = useRecolhida("sidebar.tagsCollapsed");
  const ind = indice(e);
  const trilho = useTrilho<HTMLDivElement>(JSON.stringify(rota) + cadernoFechado + listasFechadas + etiquetasFechadas + e.listas.length);
  const amanha = (ind.porDia.get(somarDias(hojeISO(), 1)) ?? []).filter((t) => !t.mae).length;
  const contagens: Partial<Record<Rota["tela"], number | null>> = {
    hoje: contagemHoje(e),
    amanha,
    todas: ind.abertas.length,
    despejo: e.despejo.filter((d) => d.estado === "caixa").length,
  };
  const item = (i: (typeof ITENS)[number]) => {
    const ativo = rota.tela === i.tela;
    return <ItemLateral key={i.tela} ativo={ativo} titulo={i.rotulo} contagem={contagens[i.tela]} icone={<i.I size={15} strokeWidth={1.9} />} aoClicar={() => irPara({ tela: i.tela } as Rota)} />;
  };
  return (
    <nav className="lateral" aria-label="Navegação">
      <div className="marca">
        <span className="simbolo"><Check size={12} strokeWidth={4} /></span>
        <span className="display d-lg" style={{ flex: 1 }}>Tasker</span>
        <button className="icone-botao" style={{ width: 28, height: 28, color: "var(--acento)" }} aria-label="Conta" title={e.email ?? "Conta"} onClick={() => irPara({ tela: "ajustes" })}>
          {e.avatar ? <img src={e.avatar} alt="" width={26} height={26} style={{ borderRadius: 999 }} /> : <CircleUserRound size={24} strokeWidth={1.8} fill="currentColor" stroke="var(--fundo)" />}
        </button>
      </div>
      <Rolagem casca="casca-lateral" className="lateral-rolagem com-trilho" rolagemRef={trilho}>
        <span className="trilho" />
        <button className="botao-busca" onClick={aoBuscar}>
          <span className="icone"><Search size={14} /></span>
          <span style={{ flex: 1, textAlign: "left" }}>Buscar</span>
          <span className="t-xs p-semi">⌘K</span>
        </button>
        {ITENS.slice(0, 6).map(item)}
        <CabecalhoSecaoLateral titulo="Caderno" recolhida={cadernoFechado} alternar={alternarCaderno} />
        {!cadernoFechado && ITENS.slice(6).map(item)}
        <CabecalhoSecaoLateral titulo="Listas" recolhida={listasFechadas} alternar={alternarListas} acao={() => folhas.abrir("Nova lista", <NovaLista />, { largura: 420 })} />
        {!listasFechadas && e.listas.map((l) => (
          <ItemLateral key={l.id} ativo={rota.tela === "lista" && rota.id === l.id} tinta={corDaLista(e, l.id)} titulo={nomeDaLista(e, l.id)}
            contagem={ind.porLista.get(l.id)?.length ?? 0} icone={<LadrilhoLista listaId={l.id} tamanho={22} />} aoClicar={() => irPara({ tela: "lista", id: l.id })}
            aoSoltar={(tarefa) => { if (e.tarefas[tarefa] && e.tarefas[tarefa].listaId !== l.id) moverTarefa(tarefa, l.id); }} />
        ))}
        <CabecalhoSecaoLateral titulo="Etiquetas" recolhida={etiquetasFechadas} alternar={alternarEtiquetas} acao={() => folhas.abrir("Nova etiqueta", <CriadorDeEtiqueta aoCriar={(id) => irPara({ tela: "etiqueta", id })} />)} />
        {!etiquetasFechadas && etiquetasOrdenadas(e).map((g) => (
          <ItemLateral key={g.id} ativo={rota.tela === "etiqueta" && rota.id === g.id} titulo={g.nome}
            contagem={ind.abertas.filter((t) => e.etiquetasDaTarefa[t.id]?.includes(g.id)).length}
            icone={<Hash size={12} strokeWidth={3} color={g.cor} />} aoClicar={() => irPara({ tela: "etiqueta", id: g.id })} />
        ))}
        {!etiquetasFechadas && !e.etiquetas.length && <div className="dica-lateral">Digite #etiqueta ao criar uma tarefa</div>}
      </Rolagem>
      <div className="rodape-lateral">
        <StatusSync />
        <span style={{ flex: 1 }} />
        <button className={"icone-botao" + (rota.tela === "ajustes" ? " ativo" : "")} aria-label="Ajustes" title="Ajustes" onClick={() => irPara({ tela: "ajustes" })}><Settings size={14} /></button>
      </div>
    </nav>
  );
}

/** Faixa do celular (§9.7): o símbolo leva ao início; a pessoa fica sempre na ponta direita. */
function FaixaCelular() {
  const avatar = usar((e) => e.avatar);
  const nome = usar((e) => e.nome ?? e.email);
  return (
    <div className="faixa-celular">
      <button className="sem-veu" aria-label="Ir para o início" onClick={() => irPara({ tela: "hoje" })}>
        <span className="simbolo"><Check size={15} strokeWidth={4} /></span>
      </button>
      <span style={{ display: "flex", alignItems: "center", gap: "var(--e2)" }}>
        <button className="icone-botao" aria-label="Buscar" onClick={() => abrirBusca()}><Search size={18} /></button>
        <button className="icone-botao" aria-label="Conta e ajustes" title={nome ?? "Conta"} onClick={() => irPara({ tela: "ajustes" })} style={{ color: "var(--acento)" }}>
          {avatar ? <img src={avatar} alt="" width={30} height={30} style={{ borderRadius: 999 }} /> : <CircleUserRound size={28} strokeWidth={1.8} fill="currentColor" stroke="var(--fundo)" />}
        </button>
      </span>
    </div>
  );
}

/** Navegação do celular (§9.6): pílula flutuante, três destinos fixos, "mais" e a ação da tela. */
function NavCelular({ rota }: { rota: Rota }) {
  const [aberto, setAberto] = useState(false);
  const [saindo, setSaindo] = useState(false);
  const [listasFechadas, alternarListas] = useRecolhida("sidebar.listsCollapsed");
  const [etiquetasFechadas, alternarEtiquetas] = useRecolhida("sidebar.tagsCollapsed");
  const e = usar((x) => x);
  const fixos: [Rota["tela"], typeof Sun, string][] = [["hoje", Sun, "Hoje"], ["calendario", CalendarDays, "Calendário"], ["despejo", Brain, "Despejo"]];
  const noFixo = fixos.some(([t]) => t === rota.tela);
  // O que a pílula mostra segue o toque, não a rota: o destino acende na hora (§9.6).
  const [tocado, setTocado] = useState<{ de: string; para: string } | null>(null);
  const [passando, setPassando] = useState<string | null>(null);
  const chaveRota = rota.tela + ("id" in rota ? rota.id : "");
  const destinoBase = tocado && tocado.de === chaveRota ? tocado.para : rota.tela;
  const destino = passando ?? destinoBase;
  const ir = (tela: string) => {
    if (tela === "mais") { setAberto(true); return; }
    if (tela === rota.tela) {
      // Tocar de novo na aba em que se está rola até o topo.
      document.querySelector(".casca-pagina > .pagina")?.scrollTo({ top: 0, behavior: querMenosMovimento() ? "auto" : "smooth" });
      return;
    }
    setTocado({ de: chaveRota, para: tela });
    queueMicrotask(() => irPara({ tela } as Rota));
  };
  const ref = useTrilho<HTMLElement>(destinoBase + String(aberto), {
    arrastavel: (el) => { const tela = el.dataset.tela; if (tela) ir(tela); },
    aoPassar: (el) => setPassando(el?.dataset.tela ?? null),
  });
  const rotuloMais = !noFixo && !aberto ? { amanha: "Amanhã", proximas: "Próximas", todas: "Todas", concluidas: "Concluídas", notas: "Notas", nota: "Notas", ajustes: "Ajustes", lista: e.listas.find((l) => "id" in rota && l.id === rota.id)?.titulo, etiqueta: e.etiquetas.find((g) => "id" in rota && g.id === rota.id)?.nome }[rota.tela as string] : undefined;
  const fechar = () => {
    // Volta para o botão (150ms, o mesmo número do CSS) e só então desmonta.
    setSaindo(true);
    setTimeout(() => { setAberto(false); setSaindo(false); }, querMenosMovimento() ? 0 : 150);
  };
  useEffect(() => { setAberto(false); setSaindo(false); setTocado(null); }, [rota]);
  const item = (r: Rota, I: typeof Sun, rotulo: string, extra?: React.ReactNode) => {
    const atual = rota.tela === r.tela && (!("id" in r) || ("id" in rota && rota.id === r.id));
    return (
      <button key={rotulo + ("id" in r ? r.id : "")} className="item-menu sem-afundar pressionavel" aria-current={atual} onClick={() => irPara(r)}>
        {extra ?? <I size={18} strokeWidth={2.1} />}
        <span className="uma-linha" style={{ flex: 1 }}>{rotulo}</span>
      </button>
    );
  };
  return (
    <>
      {aberto && <div className={"fundo-menu animar-fade-in" + (saindo ? " saindo" : "")} onClick={fechar} />}
      <div className="nav-celular">
        <nav ref={ref} className="com-trilho" aria-label="Navegação" style={{ ["--trilho-cor" as string]: "var(--superficie2)" }}>
          <span className="trilho" />
          {fixos.map(([tela, I, rotulo]) => {
            const ativa = destino === tela && !aberto;
            return (
              <button key={tela} data-trilho="" data-tela={tela} className="item-nav sem-veu sem-afundar pressionavel" aria-label={rotulo} aria-current={ativa} onClick={() => ir(tela)}>
                <I size={19} strokeWidth={2.1} />
                {ativa && !passando && <span className="rotulo-nav">{rotulo}</span>}
              </button>
            );
          })}
          <button data-trilho="" data-tela="mais" className={"item-nav mais sem-veu sem-afundar pressionavel" + (rotuloMais && !passando ? "" : " so-icone")} aria-label="Mais telas" aria-expanded={aberto}
            aria-current={aberto || (passando ? passando === "mais" : !fixos.some(([t]) => t === destino))}
            onClick={() => (aberto ? fechar() : setAberto(true))}>
            <ChevronUp size={20} strokeWidth={2.1} />
            {rotuloMais && !passando && <span className="uma-linha rotulo-nav" style={{ maxWidth: 110 }}>{rotuloMais}</span>}
          </button>
          {aberto && (
            <div className={"menu-mais " + (saindo ? "volta-para-o-botao" : "brota-do-botao")} role="menu">
              {item({ tela: "amanha" }, Sunrise, "Amanhã")}
              {item({ tela: "proximas" }, ChartGantt, "Próximas")}
              {item({ tela: "todas" }, Inbox, "Todas")}
              {item({ tela: "concluidas" }, CircleCheck, "Concluídas")}
              {item({ tela: "notas" }, NotepadText, "Notas")}
              <button className="secao-menu sem-veu" aria-expanded={!listasFechadas} onClick={alternarListas}><span className="rotulo">Listas</span><ChevronDown size={9} strokeWidth={3.2} className="c3" /></button>
              {!listasFechadas && e.listas.map((l) => item({ tela: "lista", id: l.id }, Inbox, nomeDaLista(e, l.id), <LadrilhoLista listaId={l.id} tamanho={22} />))}
              {e.etiquetas.length > 0 && <button className="secao-menu sem-veu" aria-expanded={!etiquetasFechadas} onClick={alternarEtiquetas}><span className="rotulo">Etiquetas</span><ChevronDown size={9} strokeWidth={3.2} className="c3" /></button>}
              {!etiquetasFechadas && etiquetasOrdenadas(e).map((g) => item({ tela: "etiqueta", id: g.id }, Hash, g.nome, <Hash size={16} strokeWidth={2.6} color={g.cor} />))}
              <div style={{ height: 1, background: "var(--borda)", margin: "2px 0" }} />
              {item({ tela: "ajustes" }, Settings, "Ajustes")}
            </div>
          )}
        </nav>
      </div>
    </>
  );
}

/** Barra flutuante de nova tarefa: a ação principal é da tela (cria na lista/dia da tela atual). */
function CriacaoRapida({ rota }: { rota: Rota }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if (e.key === "n" && !e.metaKey && !e.ctrlKey && !(e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement)) {
        e.preventDefault();
        window.dispatchEvent(new Event("tasker:nova"));
      }
    };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, []);
  if (["despejo", "notas", "nota", "ajustes", "calendario", "concluidas"].includes(rota.tela)) return null;
  const hoje = hojeISO();
  return (
    <div className="barra-flutuante">
      <CampoTarefa key={rota.tela + ("id" in rota ? rota.id : "")} estilo="flutuante"
        prazo={rota.tela === "hoje" ? hoje : rota.tela === "amanha" || rota.tela === "proximas" ? somarDias(hoje, 1) : null}
        listaId={rota.tela === "lista" ? rota.id : null} etiqueta={rota.tela === "etiqueta" ? rota.id : null} />
    </div>
  );
}

/** Busca única (⌘K, BuscaView.swift): setas escolhem, Enter abre. */
function ConteudoBusca() {
  const aoFechar = folhas.fechar;
  const [q, setQ] = useState("");
  const [escolhido, setEscolhido] = useState(0);
  const e = usar((x) => x);
  const r = q.trim() ? buscar(e, q) : [];
  const hoje = hojeISO();
  const abrir = (i: number) => {
    const x = r[i];
    if (!x) return;
    aoFechar();
    if (x.tipo === "tarefa") {
      const t = e.tarefas[x.alvo];
      if (t) { irPara(t.concluida ? { tela: "concluidas" } : { tela: "lista", id: t.listaId }); setTimeout(() => selecionar(t.id), 0); }
    } else if (x.tipo === "nota") {
      const n = e.notas.find((m) => m.id === x.alvo);
      irPara({ tela: "notas" });
      if (n) abrirNota(n.dia ? { dia: n.dia } : { nota: n.id });
    } else if (x.tipo === "despejo") irPara({ tela: "despejo" });
    else {
      const ev = e.eventos.find((v) => v.id === x.alvo);
      if (ev?.link) window.open(ev.link, "_blank", "noopener");
      else irPara({ tela: "calendario" });
    }
  };
  const Icone = (x: (typeof r)[number]) => (x.tipo === "tarefa" ? (x.concluida ? CircleCheck : Circle) : x.tipo === "nota" ? NotepadText : x.tipo === "despejo" ? Brain : CalendarDays);
  return (
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--e3)" }}>
        <div className="campo-busca">
          <Search size={15} strokeWidth={2.6} className="c3" />
          <input autoFocus placeholder="Buscar em tarefas, notas, despejo e agenda" value={q} aria-label="Buscar"
            onChange={(x) => { setQ(x.target.value); setEscolhido(0); }}
            onKeyDown={(x) => {
              if (x.key === "Enter") abrir(escolhido);
              if (x.key === "ArrowDown" && r.length) { x.preventDefault(); setEscolhido((escolhido + 1) % r.length); }
              if (x.key === "ArrowUp" && r.length) { x.preventDefault(); setEscolhido((escolhido - 1 + r.length) % r.length); }
            }} />
        </div>
        {!q.trim() ? (
          <span className="t-xs c3" style={{ padding: "0 8px" }}>Dica: várias palavras procuram todas ao mesmo tempo; acentos e maiúsculas não importam.</span>
        ) : !r.length ? (
          <span className="t-sm c3" style={{ padding: 12 }}>Nada encontrado para “{q}”.</span>
        ) : (
          <Rolagem casca="casca-busca" fundo="var(--superficie)" style={{ maxHeight: 360, overflow: "auto", display: "flex", flexDirection: "column", gap: 1 }}>
            {r.map((x, i) => {
              const I = Icone(x);
              return (
                <button key={x.tipo + x.alvo} className="resultado afunda" aria-selected={i === escolhido} onMouseEnter={() => setEscolhido(i)} onClick={() => abrir(i)}>
                  <I size={14} className="c3" style={{ width: 18, marginTop: 2, flex: "none" }} />
                  <span style={{ display: "flex", flexDirection: "column", gap: 2, flex: 1, minWidth: 0 }}>
                    <span className={"t-sm p-semi uma-linha" + (x.concluida ? " riscado" : "")}>{x.titulo}</span>
                    {x.trecho && <span className="t-xs c3 uma-linha">{x.trecho}</span>}
                  </span>
                  <span style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 2 }}>
                    <span className="t-xs p-semi c3">{{ tarefa: "Tarefa", nota: "Nota", despejo: "Despejo", evento: "Evento" }[x.tipo]}</span>
                    {x.data && x.tipo !== "despejo" && <span className="t-xs c3">{rotuloCurto(x.data.length > 10 ? diaISO(new Date(x.data)) : x.data, hoje)}</span>}
                  </span>
                </button>
              );
            })}
          </Rolagem>
        )}
      </div>
  );
}

export const abrirBusca = () => folhas.abrir("Buscar", <ConteudoBusca />, { largura: 560 });

/** Aviso do rodapé (ToastDesfazer): "excluído — Desfazer" ou o sucesso com o ícone verde. */
function Toast() {
  const a = useAviso();
  if (!a) return null;
  if (a.tipo === "desfazer")
    return (
      <div className="toast" role="status" key={a.id}>
        <Trash2 size={12} strokeWidth={2.6} className="c3" />
        <span className="t-sm p-medio uma-linha">{textoDoAviso(a)}</span>
        <button className="botao b-fantasma" style={{ color: "var(--acento)", flex: "none" }} title="Desfazer a exclusão" onClick={desfazerAgora}>Desfazer</button>
      </div>
    );
  return (
    <div className="toast sucesso" role="status" key={a.id}>
      {a.tipo === "erro" ? <CircleAlert size={13} strokeWidth={2.6} color="var(--perigo-texto)" /> : <CircleCheck size={13} strokeWidth={2.6} color="var(--sucesso)" />}
      <span className="t-sm p-medio uma-linha">{textoDoAviso(a)}</span>
    </div>
  );
}

/** Aviso de instalação: no Mac, o app; nos outros, o PWA. Some para sempre ao fechar. */
function AvisoInstalar() {
  const [evento, setEvento] = useState<{ prompt: () => Promise<void> } | null>(null);
  const [fechado, setFechado] = useState(() => {
    try {
      return localStorage.getItem("tasker.avisoInstalar") === "fechado";
    } catch {
      return false;
    }
  });
  useEffect(() => {
    const f = (e: Event) => {
      e.preventDefault();
      setEvento(e as unknown as { prompt: () => Promise<void> });
    };
    window.addEventListener("beforeinstallprompt", f);
    return () => window.removeEventListener("beforeinstallprompt", f);
  }, []);
  const instalado = matchMedia("(display-mode: standalone)").matches || (navigator as { standalone?: boolean }).standalone || "webkit" in window && !!(window as { webkit?: { messageHandlers?: { tasker?: unknown } } }).webkit?.messageHandlers?.tasker;
  if (fechado || instalado) return null;
  const mac = /Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints < 2;
  const ios = /iPhone|iPad/.test(navigator.userAgent) || (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1);
  const fechar = () => {
    setFechado(true);
    try {
      localStorage.setItem("tasker.avisoInstalar", "fechado");
    } catch {
      /* nada */
    }
  };
  let texto: string, acao: React.ReactNode;
  if (mac) {
    texto = "Tem o Tasker para Mac, com o número no menu e ⌥Espaço.";
    acao = <a className="botao b-primario" href="https://github.com/pedroydzito/tasker/releases/latest" target="_blank" rel="noreferrer"><Download size={14} /> Baixar</a>;
  } else if (ios) {
    texto = "Instale: toque em Compartilhar e depois em “Adicionar à Tela de Início”.";
    acao = null;
  } else {
    texto = "Instale o Tasker para abrir direto e usar offline.";
    acao = evento ? <button className="botao b-primario" onClick={() => void evento.prompt().then(fechar)}>Instalar</button> : null;
    if (!evento) return null;
  }
  return (
    <div className="cartao" role="note" style={{ display: "flex", alignItems: "center", gap: 10, padding: "10px 12px" }}>
      <span className="t-sm" style={{ flex: 1 }}>{texto}</span>
      {acao}
      <button className="icone-botao" aria-label="Dispensar" onClick={fechar}><X size={14} /></button>
    </div>
  );
}

/** Telas com colunas próprias (Mac: Calendário e Notas não usam a moldura de página). */
const TELA_CHEIA: Rota["tela"][] = ["calendario", "notas", "nota"];

function Tela({ rota }: { rota: Rota }) {
  switch (rota.tela) {
    case "hoje": return <TelaHoje />;
    case "amanha": return <TelaAmanha />;
    case "proximas": return <TelaProximas />;
    case "calendario": return <TelaCalendario />;
    case "todas": return <TelaTodas />;
    case "concluidas": return <TelaConcluidas />;
    case "despejo": return <TelaDespejo />;
    case "notas": return <TelaNotas />;
    case "nota": return <TelaNotas id={rota.id} />;
    case "ajustes": return <TelaAjustes />;
    case "lista": return <TelaLista id={rota.id} />;
    case "etiqueta": return <TelaEtiqueta id={rota.id} />;
    case "menu": return <TelaHoje />;
  }
}

export function App() {
  const modo = usar((e) => e.modo);
  const rota = useRota();
  const sel = useSelecionada();
  const celular = useCelular();
  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        abrirBusca();
      }
    };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, []);
  // Troca de tela fecha o inspetor da tela anterior.
  useEffect(() => () => selecionar(null), [rota]);

  if (modo === "carregando") return null;
  // No menu da barra sem conta: o convite do menu nativo; entrar é na janela grande.
  if (modo === "entrar" && rota.tela === "menu") return <MenuSemConta />;
  if (modo === "entrar") return <Suspense fallback={null}><TelaEntrar /></Suspense>;
  if (rota.tela === "menu") return <Suspense fallback={null}><Menu /></Suspense>;
  return (
    <div className="casca">
      <Lateral rota={rota} aoBuscar={abrirBusca} />
      <main className="principal">
        {/* Primeira sincronização da conta, sem nada ainda: a espera que não sabe o tamanho. */}
        <BarraSync />
        {/* key: a tela nova monta de novo e a entrada roda a cada troca (§9.3). */}
        <Rolagem key={rota.tela + ("id" in rota ? rota.id : "")} casca={"casca-pagina" + (TELA_CHEIA.includes(rota.tela) ? " cheia" : "")} className={"pagina animar-tela" + (TELA_CHEIA.includes(rota.tela) ? " cheia" : "")}>
          {TELA_CHEIA.includes(rota.tela) ? (
            <>
              <div className="faixa-solta"><FaixaCelular /></div>
              <Suspense fallback={null}><Tela rota={rota} /></Suspense>
            </>
          ) : (
            <div className="pagina-conteudo">
              <FaixaCelular />
              <AvisoInstalar />
              <Suspense fallback={<EsperaTela />}><TrocaSuave /><Tela rota={rota} /></Suspense>
            </div>
          )}
        </Rolagem>
        <CriacaoRapida rota={rota} />
        {sel && <Inspetor key={sel} id={sel} />}
      </main>
      <NavCelular rota={rota} />
      <Toast />
      <HospedeDeFolhas />
      <HospedeDoContexto />
      <DicaDePrimeiraVez rota={rota} celular={celular} />
      <PuxarParaAtualizar />
    </div>
  );
}

function MenuSemConta() {
  const abrir = () => {
    const p = (window as { webkit?: { messageHandlers?: { tasker?: { postMessage: (m: unknown) => void } } } }).webkit?.messageHandlers?.tasker;
    if (p) p.postMessage({ acao: "abrirJanela", rota: "#/hoje", tarefa: null });
    else location.hash = "#/hoje";
  };
  return (
    <div className="menu-sem-conta animar-surgir">
      <span className="simbolo" style={{ width: 44, height: 44, borderRadius: 12 }}><Check size={22} strokeWidth={4} /></span>
      <h1 className="display d-lg">Conecte sua conta</h1>
      <p className="t-sm c3">Para ver as tarefas e os eventos de hoje.</p>
      <button className="botao m b-primario" onClick={abrir}>Configurar</button>
    </div>
  );
}

function BarraSync() {
  const mostrar = usar((e) => e.modo === "conta" && e.sincronizando && !e.ultimaSync);
  return mostrar ? <div className="barra-espera barra-sync" role="progressbar" aria-label="Sincronizando pela primeira vez" /> : null;
}
