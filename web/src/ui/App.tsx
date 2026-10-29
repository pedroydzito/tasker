import { Menu } from "./Menu";
import { CriadorDeEtiqueta, HospedeDeFolhas, NovaLista, folhas } from "./folhas";
import { useEffect, useRef, useState } from "react";
import { Menu as IconeMenu, ArrowUp, CircleAlert, Trash2, Circle, Brain, CalendarDays, ChartGantt, Check, ChevronDown, CircleCheck, CircleUserRound, CloudOff, Download, Hash, Inbox, NotepadText, Plus, RefreshCw, Search, Settings, Sun, Sunrise, X } from "lucide-react";
import { usar } from "../dados/armazem";
import { criarDoTexto } from "../dados/acoes";
import { desfazerAgora, textoDoAviso, useAviso } from "../dados/avisos";
import { buscar, contagemHoje, corDaLista, etiquetasOrdenadas, indice, nomeDaLista } from "../dados/consultas";
import { puxar } from "../dados/sync";
import { diaISO, hojeISO, rotuloCurto, somarDias } from "../dados/util";
import { Folha, LadrilhoLista } from "./comuns";
import { Inspetor } from "./Inspetor";
import { abrirNota, irPara, selecionar, useRota, useSelecionada, type Rota } from "./rota";
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

/** Navegação do celular: a pílula do menu do Mac (rótulo só no ativo) + o restante numa gaveta. */
function NavPilula({ rota, aoAbrirMais }: { rota: Rota; aoAbrirMais: () => void }) {
  const abas: [Rota["tela"], typeof Sun, string][] = [["hoje", Sun, "Hoje"], ["calendario", CalendarDays, "Calendário"], ["despejo", Brain, "Despejo"], ["notas", NotepadText, "Notas"]];
  return (
    <nav className="nav-pilula" aria-label="Navegação">
      {abas.map(([tela, I, rotulo]) => {
        const ativa = rota.tela === tela || (tela === "notas" && rota.tela === "nota");
        return (
          <button key={tela} className={"aba-pilula" + (ativa ? " ativa" : "")} aria-label={rotulo} aria-current={ativa} onClick={() => irPara({ tela } as Rota)}>
            <I size={16} strokeWidth={2.2} />
            {ativa && <span className="t-sm p-semi">{rotulo}</span>}
          </button>
        );
      })}
      <span style={{ width: 1, height: 22, background: "var(--borda)", margin: "0 2px", alignSelf: "center" }} />
      <button className="icone-botao" style={{ width: 40, height: 40 }} aria-label="Listas, etiquetas e ajustes" onClick={aoAbrirMais}><IconeMenu size={16} /></button>
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

/** Busca única (⌘K, BuscaView.swift): setas escolhem, Enter abre. */
function Busca({ aoFechar }: { aoFechar: () => void }) {
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
    <Folha titulo="Buscar" aoFechar={aoFechar} largura={560}>
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
    </Folha>
  );
}

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
  const [busca, setBusca] = useState(false);
  const [gaveta, setGaveta] = useState(false);
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
  useEffect(() => setGaveta(false), [rota]);

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
      <NavPilula rota={rota} aoAbrirMais={() => setGaveta(true)} />
      {gaveta && <><div className="veu-modal" onClick={() => setGaveta(false)} /><div className="gaveta" onClick={(e) => (e.target as HTMLElement).closest("button.item-lateral, .rodape-lateral button") && setGaveta(false)}><Lateral rota={rota} aoBuscar={() => { setGaveta(false); setBusca(true); }} /></div></>}
      {busca && <Busca aoFechar={() => setBusca(false)} />}
      <Toast />
      <HospedeDeFolhas />
    </div>
  );
}
