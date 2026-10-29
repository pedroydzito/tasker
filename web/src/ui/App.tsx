import { useEffect, useRef, useState } from "react";
import { CalendarDays, CheckCircle2, CloudOff, Inbox, Layers, NotebookPen, Search, Settings, Sun, Sunrise, CalendarRange, Download, X } from "lucide-react";
import { usar } from "../dados/armazem";
import { criarDoTexto } from "../dados/acoes";
import { desfazerAgora, textoDoAviso, useAviso } from "../dados/avisos";
import { buscar, contagemHoje, corDaLista, etiquetasOrdenadas, iconeDaLista, indice, nomeDaLista } from "../dados/consultas";
import { hojeISO, somarDias } from "../dados/util";
import { IconeLista, LinhaTarefa } from "./comuns";
import { Inspetor } from "./Inspetor";
import { irPara, selecionar, useRota, useSelecionada, type Rota } from "./rota";
import {
  TelaAjustes, TelaAmanha, TelaCalendario, TelaConcluidas, TelaDespejo, TelaEntrar, TelaEtiqueta, TelaHoje, TelaLista, TelaNota, TelaNotas, TelaProximas, TelaTodas,
} from "./telas";

const ITENS: { tela: Rota["tela"]; rotulo: string; I: typeof Sun }[] = [
  { tela: "hoje", rotulo: "Hoje", I: Sun },
  { tela: "amanha", rotulo: "Amanhã", I: Sunrise },
  { tela: "proximas", rotulo: "Próximas", I: CalendarRange },
  { tela: "calendario", rotulo: "Calendário", I: CalendarDays },
  { tela: "todas", rotulo: "Todas", I: Layers },
  { tela: "concluidas", rotulo: "Concluídas", I: CheckCircle2 },
  { tela: "despejo", rotulo: "Despejo", I: Inbox },
  { tela: "notas", rotulo: "Notas", I: NotebookPen },
];

function Lateral({ rota, aoBuscar }: { rota: Rota; aoBuscar: () => void }) {
  const e = usar((x) => x);
  const n = contagemHoje(e);
  const caixa = e.despejo.filter((d) => d.estado === "caixa").length;
  const porLista = indice(e).porLista;
  return (
    <nav className="lateral" aria-label="Navegação">
      <div style={{ padding: "18px 14px 8px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <span className="display d-lg">Tasker</span>
        <button className="icone-botao" aria-label="Buscar (⌘K)" onClick={aoBuscar}><Search size={15} /></button>
      </div>
      <div style={{ flex: 1, overflow: "auto", padding: "4px 8px 16px", display: "flex", flexDirection: "column", gap: 1 }}>
        {ITENS.map(({ tela, rotulo, I }) => (
          <button key={tela} className={"item-lateral" + (rota.tela === tela ? " ativo" : "")} onClick={() => irPara({ tela } as Rota)}>
            <span className="icone"><I size={15} /></span>
            <span style={{ flex: 1 }}>{rotulo}</span>
            {tela === "hoje" && n > 0 && <span className="t-xs c3 numeros">{n}</span>}
            {tela === "despejo" && caixa > 0 && <span className="t-xs c3 numeros">{caixa}</span>}
          </button>
        ))}
        <div className="rotulo" style={{ padding: "14px 10px 4px" }}>Listas</div>
        {e.listas.map((l) => (
          <button key={l.id} className={"item-lateral" + (rota.tela === "lista" && rota.id === l.id ? " ativo" : "")} onClick={() => irPara({ tela: "lista", id: l.id })}>
            <span className="icone" style={{ color: corDaLista(e, l.id) }}><IconeLista nome={iconeDaLista(e, l.id)} /></span>
            <span style={{ flex: 1 }} className="uma-linha">{nomeDaLista(e, l.id)}</span>
            <span className="t-xs c3 numeros">{porLista.get(l.id)?.length || ""}</span>
          </button>
        ))}
        {e.etiquetas.length > 0 && <div className="rotulo" style={{ padding: "14px 10px 4px" }}>Etiquetas</div>}
        {etiquetasOrdenadas(e).map((g) => (
          <button key={g.id} className={"item-lateral" + (rota.tela === "etiqueta" && rota.id === g.id ? " ativo" : "")} onClick={() => irPara({ tela: "etiqueta", id: g.id })}>
            <span className="icone" style={{ color: g.cor }}>#</span>
            <span style={{ flex: 1 }}>{g.nome}</span>
          </button>
        ))}
      </div>
      <div style={{ padding: 8, borderTop: "1px solid var(--borda)" }}>
        <button className={"item-lateral" + (rota.tela === "ajustes" ? " ativo" : "")} onClick={() => irPara({ tela: "ajustes" })}>
          <span className="icone">{e.online ? <Settings size={15} /> : <CloudOff size={15} />}</span>
          <span style={{ flex: 1 }} className="uma-linha">{e.online ? "Ajustes" : "Offline"}{e.pendencias ? ` · ${e.pendencias} na fila` : ""}</span>
        </button>
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
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, []);
  if (rota.tela === "despejo" || rota.tela === "notas" || rota.tela === "nota" || rota.tela === "ajustes") return null;
  const hoje = hojeISO();
  const padrao = {
    prazo: rota.tela === "hoje" ? hoje : rota.tela === "amanha" ? somarDias(hoje, 1) : null,
    listaId: rota.tela === "lista" ? rota.id : null,
    etiqueta: rota.tela === "etiqueta" ? rota.id : null,
  };
  return (
    <div className="barra-flutuante">
      <input ref={ref} className="campo campo-limpo t-md" style={{ width: "100%", height: 42, padding: "0 14px" }} placeholder="Nova tarefa… (amanhã, sexta, ~lista, #etiqueta)"
        value={texto} onChange={(e) => setTexto(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter" && texto.trim()) { criarDoTexto(texto, padrao); setTexto(""); } if (e.key === "Escape") e.currentTarget.blur(); }}
        onPaste={(e) => { const t = e.clipboardData.getData("text"); if (t.includes("\n")) { e.preventDefault(); criarDoTexto(t, padrao); } }} />
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
    case "nota": return <TelaNota id={rota.id} />;
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
        <div className="pagina">
          <div className="pagina-conteudo">
            <AvisoInstalar />
            <Tela rota={rota} />
          </div>
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
