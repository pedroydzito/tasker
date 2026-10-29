import { useEffect, useRef, useState } from "react";
import { ArrowUp, Brain, CalendarDays, ChartGantt, Check, ChevronDown, CircleCheck, CircleUserRound, CloudOff, Download, Hash, Inbox, NotepadText, Plus, RefreshCw, Search, Settings, Sun, Sunrise, X } from "lucide-react";
import { usar } from "../dados/armazem";
import { criarDoTexto, criarEtiqueta, criarLista } from "../dados/acoes";
import { desfazerAgora, textoDoAviso, useAviso } from "../dados/avisos";
import { buscar, contagemHoje, corDaLista, etiquetasOrdenadas, indice, nomeDaLista } from "../dados/consultas";
import { puxar } from "../dados/sync";
import { hojeISO, somarDias } from "../dados/util";
import { LadrilhoLista, LinhaTarefa } from "./comuns";
import { Inspetor } from "./Inspetor";
import { irPara, selecionar, useRota, useSelecionada, type Rota } from "./rota";
import {
  TelaAjustes, TelaAmanha, TelaCalendario, TelaConcluidas, TelaDespejo, TelaEntrar, TelaEtiqueta, TelaHoje, TelaLista, TelaNotas, TelaProximas, TelaTodas,
} from "./telas";

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
        <CabecalhoSecaoLateral titulo="Listas" recolhida={listasFechadas} alternar={alternarListas} acao={() => { const n = prompt("Nome da nova lista"); if (n?.trim()) criarLista(n.trim()); }} />
        {!listasFechadas && e.listas.map((l) => (
          <ItemLateral key={l.id} ativo={rota.tela === "lista" && rota.id === l.id} tinta={corDaLista(e, l.id)} titulo={nomeDaLista(e, l.id)}
            contagem={ind.porLista.get(l.id)?.length ?? 0} icone={<LadrilhoLista listaId={l.id} tamanho={22} />} aoClicar={() => irPara({ tela: "lista", id: l.id })} />
        ))}
        <CabecalhoSecaoLateral titulo="Etiquetas" recolhida={etiquetasFechadas} alternar={alternarEtiquetas} acao={() => { const n = prompt("Nome da nova etiqueta"); if (n?.trim()) { const g = criarEtiqueta(n.trim().replace(/^#/, "")); irPara({ tela: "etiqueta", id: g.id }); } }} />
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

function NavPilula({ rota }: { rota: Rota }) {
  const itens = [ITENS[0], ITENS[1], ITENS[3], ITENS[6], ITENS[7]];
  return (
    <nav className="nav-pilula" aria-label="Navegação">
      {itens.map(({ tela, rotulo, I }) => (
        <button key={tela} className="icone-botao" aria-label={rotulo} aria-current={rota.tela === tela} style={{ width: 48, height: 40, color: rota.tela === tela ? "var(--acento)" : undefined }} onClick={() => irPara({ tela } as Rota)}>
          <I size={18} />
        </button>
      ))}
      <button className="icone-botao" aria-label="Ajustes" style={{ width: 48, height: 40 }} onClick={() => irPara({ tela: "ajustes" })}><Settings size={18} /></button>
    </nav>
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

function Busca({ aoFechar }: { aoFechar: () => void }) {
  const [q, setQ] = useState("");
  const e = usar((x) => x);
  const r = buscar(e, q);
  const abrir = (i: number) => {
    const x = r[i];
    if (!x) return;
    if (x.tipo === "tarefa") selecionar(x.alvo);
    else if (x.tipo === "nota") irPara({ tela: "nota", id: x.alvo });
    else if (x.tipo === "despejo") irPara({ tela: "despejo" });
    aoFechar();
  };
  return (
    <>
      <div className="veu-modal" onClick={aoFechar} />
      <div className="folha" role="dialog" aria-label="Buscar" style={{ top: "18%", transform: "translateX(-50%)", ["--largura" as string]: "560px" }}>
        <input autoFocus className="campo-limpo t-lg" style={{ padding: 16, borderBottom: "1px solid var(--borda)" }} placeholder="Buscar tarefas, notas, despejo, eventos" value={q}
          onChange={(x) => setQ(x.target.value)} onKeyDown={(x) => { if (x.key === "Escape") aoFechar(); if (x.key === "Enter") abrir(0); }} />
        <div style={{ maxHeight: 420, overflow: "auto", padding: 6 }}>
          {r.map((x, i) => (
            <button key={x.tipo + x.alvo} className="linha-tarefa" style={{ width: "100%", textAlign: "left" }} onClick={() => abrir(i)}>
              <span style={{ flex: 1, minWidth: 0 }}>
                <span className={"t-md uma-linha" + (x.concluida ? " riscado" : "")} style={{ display: "block" }}>{x.titulo}</span>
                {x.trecho && <span className="t-xs c3 uma-linha" style={{ display: "block" }}>{x.trecho}</span>}
              </span>
              <span className="t-xs c3">{{ tarefa: "Tarefa", nota: "Nota", despejo: "Despejo", evento: "Evento" }[x.tipo]}</span>
            </button>
          ))}
          {q && !r.length && <div className="vazio t-sm c3">Nada encontrado.</div>}
        </div>
      </div>
    </>
  );
}

function Toast() {
  const a = useAviso();
  if (!a) return null;
  return (
    <div className={"toast " + a.tipo} role="status">
      <span className="t-sm" style={a.tipo === "erro" ? { color: "var(--perigo)" } : undefined}>{a.tipo === "sucesso" ? "✓ " : ""}{textoDoAviso(a)}</span>
      {a.tipo === "desfazer" && <button className="botao b-superficie" onClick={desfazerAgora}>Desfazer</button>}
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

/** Layout compacto do popover do Mac (#/menu). */
function Menu() {
  const hoje = usar((e) => indice(e).hoje.filter((t) => !t.mae));
  const atrasadas = usar((e) => (e.prefs.mostrarAtrasadasNoMenu ? indice(e).atrasadas : []));
  const amanha = usar((e) => indice(e).porDia.get(somarDias(hojeISO(), 1)) ?? []);
  const [aba, setAba] = useState<"hoje" | "amanha">("hoje");
  const [texto, setTexto] = useState("");
  const ts = aba === "hoje" ? [...atrasadas, ...hoje] : amanha;
  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", padding: 10, gap: 8 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div className="segmentado">
          <button aria-pressed={aba === "hoje"} onClick={() => setAba("hoje")}>Hoje</button>
          <button aria-pressed={aba === "amanha"} onClick={() => setAba("amanha")}>Amanhã</button>
        </div>
      </div>
      <input className="campo t-md" placeholder="Nova tarefa…" value={texto} onChange={(e) => setTexto(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter" && texto.trim()) { criarDoTexto(texto, { prazo: aba === "hoje" ? hojeISO() : somarDias(hojeISO(), 1) }); setTexto(""); } }} />
      <div className="cartao-linhas" style={{ flex: 1, overflow: "auto" }}>
        {ts.map((t) => <LinhaTarefa key={t.id} t={t} mostrarData={aba === "hoje" && t.prazo !== hojeISO()} compacta />)}
        {!ts.length && <div className="vazio t-sm c3">Nada por aqui.</div>}
      </div>
      <Toast />
    </div>
  );
}

export function App() {
  const modo = usar((e) => e.modo);
  const rota = useRota();
  const sel = useSelecionada();
  const [busca, setBusca] = useState(false);
  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setBusca((b) => !b);
      }
    };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, []);
  // Troca de tela fecha o inspetor da tela anterior.
  useEffect(() => () => selecionar(null), [rota]);

  if (modo === "carregando") return null;
  if (modo === "entrar") return <TelaEntrar />;
  if (rota.tela === "menu") return <Menu />;
  return (
    <div className="casca">
      <Lateral rota={rota} aoBuscar={() => setBusca(true)} />
      <main className="principal">
        <div className={"pagina" + (TELA_CHEIA.includes(rota.tela) ? " cheia" : "")}>
          {TELA_CHEIA.includes(rota.tela) ? <Tela rota={rota} /> : (
            <div className="pagina-conteudo">
              <AvisoInstalar />
              <Tela rota={rota} />
            </div>
          )}
        </div>
        <CriacaoRapida rota={rota} />
        {sel && <Inspetor key={sel} id={sel} />}
      </main>
      <NavPilula rota={rota} />
      {busca && <Busca aoFechar={() => setBusca(false)} />}
      <Toast />
    </div>
  );
}
