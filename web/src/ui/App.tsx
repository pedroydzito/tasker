import { CriadorDeEtiqueta, HospedeDeFolhas, NovaLista, folhas } from "./folhas";
import { Suspense, lazy, useEffect, useRef, useState, type ComponentType } from "react";
import { ChevronUp, ArrowUp, CircleAlert, Trash2, Circle, Brain, CalendarDays, ChartGantt, Check, ChevronDown, CircleCheck, CircleUserRound, CloudOff, Download, Hash, Inbox, NotepadText, Plus, RefreshCw, Search, Settings, Sun, Sunrise, X } from "lucide-react";
import { usar } from "../dados/armazem";
import { criarDoTexto, novaNota } from "../dados/acoes";
import { desfazerAgora, textoDoAviso, useAviso } from "../dados/avisos";
import { buscar, contagemHoje, corDaLista, etiquetasOrdenadas, indice, nomeDaLista } from "../dados/consultas";
import { puxar } from "../dados/sync";
import { diaISO, hojeISO, rotuloCurto, somarDias } from "../dados/util";
import { LadrilhoLista, querMenosMovimento, useTrilho } from "./comuns";
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
const CampoDespejo = preguicosa("CampoDespejo") as ComponentType;
const Menu = lazy(() => import("./Menu").then((m) => ({ default: m.Menu })));
if (typeof window !== "undefined") ("requestIdleCallback" in window ? requestIdleCallback : setTimeout)(() => void telas());

/** Enquanto o código da tela chega: o formato do cabeçalho e de um cartão (§10.6). */
function EsperaTela() {
  return (
    <div className="esqueleto-casca" style={{ height: "auto" }} aria-hidden>
      <div className="esqueleto-conteudo" style={{ padding: 0, margin: 0 }}>
        <i className="e-titulo" /><i className="e-sub" />
        <div className="e-cartao"><i /><i /><i /></div>
      </div>
    </div>
  );
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

function ItemLateral({ ativo, tinta, titulo, contagem, icone, aoClicar }: { ativo: boolean; tinta?: string; titulo: string; contagem?: number | null; icone: React.ReactNode; aoClicar: () => void }) {
  return (
    <button
      className={"item-lateral" + (ativo ? " ativo" : "")}
      style={ativo && tinta ? { background: `color-mix(in srgb, ${tinta} 16%, transparent)` } : undefined}
      onClick={aoClicar}
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
  const amanha = (ind.porDia.get(somarDias(hojeISO(), 1)) ?? []).filter((t) => !t.mae).length;
  const contagens: Partial<Record<Rota["tela"], number | null>> = {
    hoje: e.prefs.energiaBaixa ? null : contagemHoje(e),
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
      <div className="lateral-rolagem">
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
            contagem={ind.porLista.get(l.id)?.length ?? 0} icone={<LadrilhoLista listaId={l.id} tamanho={22} />} aoClicar={() => irPara({ tela: "lista", id: l.id })} />
        ))}
        <CabecalhoSecaoLateral titulo="Etiquetas" recolhida={etiquetasFechadas} alternar={alternarEtiquetas} acao={() => folhas.abrir("Nova etiqueta", <CriadorDeEtiqueta aoCriar={(id) => irPara({ tela: "etiqueta", id })} />)} />
        {!etiquetasFechadas && etiquetasOrdenadas(e).map((g) => (
          <ItemLateral key={g.id} ativo={rota.tela === "etiqueta" && rota.id === g.id} titulo={g.nome}
            contagem={ind.abertas.filter((t) => e.etiquetasDaTarefa[t.id]?.includes(g.id)).length}
            icone={<Hash size={12} strokeWidth={3} color={g.cor} />} aoClicar={() => irPara({ tela: "etiqueta", id: g.id })} />
        ))}
        {!etiquetasFechadas && !e.etiquetas.length && <div className="dica-lateral">Digite #etiqueta ao criar uma tarefa</div>}
      </div>
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

/** Ação principal da tela (§14.3): o "+" da pílula faz o que a tela atual cria. */
function acaoPrincipal(rota: Rota): { rotulo: string; fazer: () => void } | null {
  const hoje = hojeISO();
  switch (rota.tela) {
    case "ajustes": return null;
    case "despejo": return { rotulo: "Despejar", fazer: () => folhas.abrir("Despejar", <CampoDespejo />) };
    case "notas": case "nota": return { rotulo: "Nova nota", fazer: () => { abrirNota({ nota: novaNota() }); irPara({ tela: "notas" }); } };
    default: {
      const padrao = {
        prazo: rota.tela === "hoje" ? hoje : rota.tela === "amanha" || rota.tela === "proximas" ? somarDias(hoje, 1) : null,
        listaId: rota.tela === "lista" ? rota.id : null,
        etiqueta: rota.tela === "etiqueta" ? rota.id : null,
      };
      return { rotulo: "Nova tarefa", fazer: () => folhas.abrir("Nova tarefa", <NovaTarefaFolha padrao={padrao} />) };
    }
  }
}

function NovaTarefaFolha({ padrao }: { padrao: { prazo: string | null; listaId: string | null; etiqueta: string | null } }) {
  const [texto, setTexto] = useState("");
  const criar = () => { if (texto.trim()) { criarDoTexto(texto, padrao); setTexto(""); } };
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e3)" }}>
      <div className="campo-menu">
        <Plus size={16} className="c3" />
        <input autoFocus placeholder="Adicionar tarefa" aria-label="Adicionar tarefa" value={texto} enterKeyHint="done"
          onChange={(e) => setTexto(e.target.value)} onKeyDown={(e) => e.key === "Enter" && criar()} />
      </div>
      <span className="t-xs c3">Entende hoje, amanhã, sexta, 30/10, ~lista e #etiqueta. Enter adiciona e deixa pronto para a próxima.</span>
      <button className="botao m b-primario largo" disabled={!texto.trim()} onClick={criar}>Adicionar tarefa</button>
    </div>
  );
}

/** Navegação do celular (§9.6): pílula flutuante, três destinos fixos, "mais" e a ação da tela. */
function NavCelular({ rota }: { rota: Rota }) {
  const [aberto, setAberto] = useState(false);
  const [saindo, setSaindo] = useState(false);
  const e = usar((x) => x);
  const fixos: [Rota["tela"], typeof Sun, string][] = [["hoje", Sun, "Hoje"], ["calendario", CalendarDays, "Calendário"], ["despejo", Brain, "Despejo"]];
  const noFixo = fixos.some(([t]) => t === rota.tela);
  const ref = useTrilho<HTMLElement>(rota.tela + String(aberto));
  const acao = acaoPrincipal(rota);
  const fechar = () => {
    // Volta para o botão (150ms, o mesmo número do CSS) e só então desmonta.
    setSaindo(true);
    setTimeout(() => { setAberto(false); setSaindo(false); }, querMenosMovimento() ? 0 : 150);
  };
  useEffect(() => { setAberto(false); setSaindo(false); }, [rota]);
  const ir = (r: Rota) => { irPara(r); };
  const item = (r: Rota, I: typeof Sun, rotulo: string, extra?: React.ReactNode) => {
    const atual = rota.tela === r.tela && (!("id" in r) || ("id" in rota && rota.id === r.id));
    return (
      <button key={rotulo + ("id" in r ? r.id : "")} className="item-menu sem-afundar pressionavel" aria-current={atual} onClick={() => ir(r)}>
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
            const ativa = rota.tela === tela && !aberto;
            return (
              <button key={tela} className="item-nav sem-veu sem-afundar pressionavel" aria-label={rotulo} aria-current={ativa} onClick={() => irPara({ tela } as Rota)}>
                <I size={19} strokeWidth={2.1} />
                {ativa && <span>{rotulo}</span>}
              </button>
            );
          })}
          <button className="item-nav so-icone mais sem-veu sem-afundar pressionavel" aria-label="Mais telas" aria-expanded={aberto} aria-current={aberto || !noFixo}
            onClick={() => (aberto ? fechar() : setAberto(true))}>
            <ChevronUp size={20} strokeWidth={2.1} />
          </button>
          {acao && (
            <>
              <span className="sep-nav" />
              <button className="item-nav so-icone acao sem-veu pressionavel" aria-label={acao.rotulo} title={acao.rotulo} onClick={acao.fazer}>
                <Plus size={22} strokeWidth={2.5} />
              </button>
            </>
          )}
          {aberto && (
            <div className={"menu-mais " + (saindo ? "volta-para-o-botao" : "brota-do-botao")} role="menu">
              {item({ tela: "amanha" }, Sunrise, "Amanhã")}
              {item({ tela: "proximas" }, ChartGantt, "Próximas")}
              {item({ tela: "todas" }, Inbox, "Todas")}
              {item({ tela: "concluidas" }, CircleCheck, "Concluídas")}
              {item({ tela: "notas" }, NotepadText, "Notas")}
              <span className="rotulo">Listas</span>
              {e.listas.map((l) => item({ tela: "lista", id: l.id }, Inbox, nomeDaLista(e, l.id), <LadrilhoLista listaId={l.id} tamanho={22} />))}
              {e.etiquetas.length > 0 && <span className="rotulo">Etiquetas</span>}
              {etiquetasOrdenadas(e).map((g) => item({ tela: "etiqueta", id: g.id }, Hash, g.nome, <Hash size={16} strokeWidth={2.6} color={g.cor} />))}
              <div style={{ height: 1, background: "var(--borda)", margin: "2px 0" }} />
              {item({ tela: "ajustes" }, Settings, "Ajustes")}
            </div>
          )}
        </nav>
      </div>
    </>
  );
}

/** Criação rápida: entende "amanhã", "sexta", "~lista", "#etiqueta". */
function CriacaoRapida({ rota }: { rota: Rota }) {
  const [texto, setTexto] = useState("");
  const ref = useRef<HTMLInputElement>(null);
  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if (e.key === "n" && !e.metaKey && !e.ctrlKey && !(e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement)) {
        e.preventDefault();
        ref.current?.focus();
      }
    };
    const focar = () => ref.current?.focus();
    window.addEventListener("keydown", k);
    window.addEventListener("tasker:nova", focar);
    return () => {
      window.removeEventListener("keydown", k);
      window.removeEventListener("tasker:nova", focar);
    };
  }, []);
  if (["despejo", "notas", "nota", "ajustes", "calendario", "concluidas"].includes(rota.tela)) return null;
  const hoje = hojeISO();
  const padrao = {
    prazo: rota.tela === "hoje" ? hoje : rota.tela === "amanha" ? somarDias(hoje, 1) : null,
    listaId: rota.tela === "lista" ? rota.id : null,
    etiqueta: rota.tela === "etiqueta" ? rota.id : null,
  };
  const noMac = !!(window as { webkit?: { messageHandlers?: { tasker?: unknown } } }).webkit?.messageHandlers?.tasker;
  const enviar = () => {
    if (!texto.trim()) return;
    criarDoTexto(texto, padrao);
    setTexto("");
  };
  return (
    <div className="barra-flutuante">
      <div className="campo-rapido">
        <Plus size={15} className="c3" />
        <input ref={ref} placeholder={noMac ? "Adicionar tarefa  ·  ⌥Espaço de qualquer lugar" : "Adicionar tarefa"} aria-label="Adicionar tarefa"
          value={texto} onChange={(e) => setTexto(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") enviar(); if (e.key === "Escape") e.currentTarget.blur(); }}
          onPaste={(e) => { const t = e.clipboardData.getData("text"); if (t.includes("\n")) { e.preventDefault(); criarDoTexto(t, padrao); } }} />
        <button className={"enviar" + (texto.trim() ? " pronto" : "")} aria-label="Adicionar" onClick={enviar}><ArrowUp size={14} strokeWidth={2.6} /></button>
      </div>
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
          <div style={{ maxHeight: 360, overflow: "auto", display: "flex", flexDirection: "column", gap: 1 }}>
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
          </div>
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
  if (modo === "entrar") return <Suspense fallback={null}><TelaEntrar /></Suspense>;
  if (rota.tela === "menu") return <Suspense fallback={null}><Menu /></Suspense>;
  return (
    <div className="casca">
      <Lateral rota={rota} aoBuscar={abrirBusca} />
      <main className="principal">
        {/* key: a tela nova monta de novo e a entrada roda a cada troca (§9.3). */}
        <div key={rota.tela + ("id" in rota ? rota.id : "")} className={"pagina animar-tela" + (TELA_CHEIA.includes(rota.tela) ? " cheia" : "")}>
          {TELA_CHEIA.includes(rota.tela) ? (
            <>
              <div className="faixa-solta"><FaixaCelular /></div>
              <Suspense fallback={null}><Tela rota={rota} /></Suspense>
            </>
          ) : (
            <div className="pagina-conteudo">
              <FaixaCelular />
              <AvisoInstalar />
              <Suspense fallback={<EsperaTela />}><Tela rota={rota} /></Suspense>
            </div>
          )}
        </div>
        <CriacaoRapida rota={rota} />
        {sel && <Inspetor key={sel} id={sel} />}
      </main>
      <NavCelular rota={rota} />
      <Toast />
      <HospedeDeFolhas />
    </div>
  );
}
