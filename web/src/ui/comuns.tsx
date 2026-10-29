import { iconePorNome } from "./folhas";
import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  AlertCircle, AlignLeft, ChevronDown, Calendar, CalendarDays, Check, ChevronLeft, ChevronRight, Circle, Clock,
  Inbox, Pause, Play, Sun, Tag, X, type LucideIcon,
} from "lucide-react";
import { usar } from "../dados/armazem";
import { alternarCronometro, concluir } from "../dados/acoes";
import { corDaLista, etiquetasDe, horarioDe, iconeDaLista, indice, nomeDaLista, notasVisiveis, tituloDe } from "../dados/consultas";
import type { Tarefa } from "../dados/tipos";
import { deISO, diaISO, hojeISO, primeiraMaiuscula, rotuloComAtraso, rotuloCurto, rotuloLongo, somarDias } from "../dados/util";
import { selecionar, useSelecionada } from "./rota";

/** Ícone de uma lista (nome SF guardado nas preferências → ícone equivalente). */
export function IconeLista({ nome, tamanho = 15 }: { nome: string | null; tamanho?: number }) {
  const I = iconePorNome(nome) ?? Circle;
  return <I size={tamanho} strokeWidth={1.8} />;
}

/** Círculo de concluir (CheckCircle): borda na cor da lista; no hover, véu 14% e o check aparece. */
export function Circulo({ feito, cor, aoClicar, tamanho = 18 }: { feito: boolean; cor: string; aoClicar: () => void; tamanho?: number }) {
  return (
    <button
      className={"circulo" + (feito ? " feito" : "")}
      style={{ ["--cor" as string]: cor, width: tamanho, height: tamanho }}
      aria-label={feito ? "Reabrir" : "Concluir"}
      title={feito ? "Reabrir" : "Concluir"}
      onClick={(ev) => {
        ev.stopPropagation();
        aoClicar();
      }}
    >
      <Check size={tamanho * 0.5} strokeWidth={3.5} />
    </button>
  );
}

/** Ladrilho da lista: ícone ou inicial sobre a cor da lista (16% de tinta), raio 30% do tamanho. */
export function LadrilhoLista({ listaId, tamanho = 20, redondo = false }: { listaId: string; tamanho?: number; redondo?: boolean }) {
  const cor = usar((e) => corDaLista(e, listaId));
  const icone = usar((e) => iconeDaLista(e, listaId));
  const nome = usar((e) => nomeDaLista(e, listaId));
  return (
    <span
      style={{
        width: tamanho, height: tamanho, flex: "none", display: "inline-flex", alignItems: "center", justifyContent: "center",
        borderRadius: redondo ? tamanho / 2 : tamanho * 0.3, background: `color-mix(in srgb, ${cor} 16%, transparent)`, color: cor,
        fontFamily: "ui-rounded, 'SF Pro Rounded', system-ui", fontWeight: 700, fontSize: tamanho * 0.46, lineHeight: 1,
      }}
    >
      {icone ? <IconeLista nome={icone} tamanho={tamanho * 0.5} /> : (nome[0] ?? "").toUpperCase()}
    </span>
  );
}

/** Chip da lista: pílula tingida (13%) com o ladrilho redondo antes do nome. */
export function ChipLista({ listaId, comSeta = false, aberta = false }: { listaId: string; comSeta?: boolean; aberta?: boolean }) {
  const cor = usar((e) => corDaLista(e, listaId));
  const nome = usar((e) => nomeDaLista(e, listaId));
  return (
    <span className="chip-lista" style={{ color: cor, background: `color-mix(in srgb, ${cor} 13%, transparent)` }}>
      <LadrilhoLista listaId={listaId} tamanho={16} redondo />
      <span className="uma-linha">{nome}</span>
      {comSeta && <ChevronDown size={9} strokeWidth={3} style={{ transform: aberta ? "rotate(180deg)" : undefined, marginLeft: 1 }} />}
    </span>
  );
}

// Subtarefas abertas embaixo da mãe (estado de módulo, como o nav.subtarefasAbertas do Mac).
const abertas = new Set<string>();
const ouvintesAbertas = new Set<() => void>();
function useAberta(id: string): [boolean, () => void] {
  const [, f] = useState(0);
  useEffect(() => {
    const o = () => f((n) => n + 1);
    ouvintesAbertas.add(o);
    return () => void ouvintesAbertas.delete(o);
  }, []);
  return [abertas.has(id), () => {
    if (abertas.has(id)) abertas.delete(id);
    else abertas.add(id);
    ouvintesAbertas.forEach((o) => o());
  }];
}

/** Linha de tarefa: [círculo] título [▸ 1/3] nota/#etiquetas …… data · [chip da lista]. */
export function LinhaTarefa({ t, mostrarData = true, mostrarLista = true, compacta = false, nivel = 0 }: { t: Tarefa; mostrarData?: boolean; mostrarLista?: boolean; compacta?: boolean; nivel?: number }) {
  const sel = useSelecionada();
  const cor = usar((e) => corDaLista(e, t.listaId));
  const etiquetas = usar((e) => etiquetasDe(e, t.id), (a, b) => a.length === b.length && a.every((x, i) => x === b[i]));
  const filhas = usar((e) => (nivel === 0 ? indice(e).filhas.get(t.id) ?? [] : []), (a, b) => a.length === b.length && a.every((x, i) => x === b[i]));
  const [aberta, alternar] = useAberta(t.id);
  const [marcando, setMarcando] = useState(false);
  const hoje = hojeISO();
  const horario = horarioDe(t);
  const feito = t.concluida || marcando;
  const atrasada = !!t.prazo && t.prazo < hoje && !t.concluida;
  const nota = notasVisiveis(t).split("\n")[0]?.trim() ?? "";

  let data: string | null = null;
  if (t.prazo) {
    const r = rotuloCurto(t.prazo, hoje);
    if (horario) data = !mostrarData || (compacta && t.prazo === hoje) ? horario : `${r} · ${horario}`;
    else data = mostrarData ? r : null;
  }
  const IconeData = atrasada ? AlertCircle : horario ? Clock : Calendar;

  const concluirComPausa = () => {
    if (t.concluida) return concluir(t.id, false);
    setMarcando(true);
    setTimeout(() => {
      concluir(t.id, true);
      setMarcando(false);
    }, 420);
  };

  const seta = filhas.length > 0 && (
    <button className="seta-sub" aria-expanded={aberta} title={(aberta ? "Esconder" : "Mostrar") + " subtarefas"} onClick={(e) => { e.stopPropagation(); alternar(); }}>
      <ChevronRight size={9} strokeWidth={3.2} style={{ transform: aberta ? "rotate(90deg)" : undefined }} />
      <span className="numeros">{filhas.filter((f) => f.concluida).length}/{filhas.length}</span>
    </button>
  );
  const meta = (nota || etiquetas.length > 0) && (
    <span className="meta-linha">
      {nota && (<><AlignLeft size={10} /><span className="uma-linha" style={{ maxWidth: 220 }}>{nota}</span></>)}
      {etiquetas.map((g) => <span key={g.id} style={{ color: g.cor }}>#{g.nome}</span>)}
    </span>
  );
  const dataEl = data && (
    <span className="data-linha numeros" style={atrasada ? { color: "var(--perigo-texto)" } : undefined}>
      {!compacta && <IconeData size={10} strokeWidth={2.6} />}
      {data}
    </span>
  );

  return (
    <>
      <div
        className={"linha-tarefa" + (sel === t.id && !compacta ? " selecionada" : "") + (compacta ? " compacta" : "")}
        style={{ paddingLeft: 12 + nivel * 26, opacity: t.provisoria ? 0.55 : undefined }}
        onClick={() => selecionar(t.id)}
        data-tarefa={t.id}
      >
        <Circulo feito={feito} cor={cor} aoClicar={concluirComPausa} />
        {compacta ? (
          <>
            <span className={"titulo-tarefa t-sm uma-linha" + (feito ? " feito" : "")}>{tituloDe(t)}</span>
            {seta}
            <span style={{ flex: 1 }} />
            {nota && <AlignLeft size={10.5} className="c3" />}
            {dataEl}
          </>
        ) : (
          <div className="linha-corpo">
            <span className="linha-titulo">
              <span className={"titulo-tarefa t-md uma-linha" + (feito ? " feito" : "")}>{tituloDe(t)}</span>
              {seta}
            </span>
            <span className="linha-detalhes">
              {meta}
              <span className="linha-respiro" />
              {dataEl}
            </span>
            {mostrarLista && <ChipLista listaId={t.listaId} />}
          </div>
        )}
      </div>
      {aberta && filhas.map((f) => <LinhaTarefa key={f.id} t={f} mostrarData={mostrarData} mostrarLista={false} compacta={compacta} nivel={nivel + 1} />)}
    </>
  );
}

export function BotaoTempo({ id }: { id: string }) {
  const ativo = usar((e) => e.cronometro.tarefaId === id);
  return (
    <button className="icone-botao" aria-label={ativo ? "Pausar" : "Começar"} onClick={() => alternarCronometro(id)}>
      {ativo ? <Pause size={15} /> : <Play size={15} />}
    </button>
  );
}

/** Seção: "TÍTULO · n ˅" (recolhível), ação fantasma à direita, cartão com as linhas. */
export function Secao({ titulo, contagem, tom, acao, recolhida = false, children }: { titulo: string; contagem?: number; tom?: string; acao?: ReactNode; recolhida?: boolean; children: ReactNode }) {
  const [fechada, setFechada] = useState(recolhida);
  return (
    <section style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
      <div style={{ display: "flex", alignItems: "center", gap: "var(--e2)", padding: "0 var(--e1)" }}>
        <button className="cabecalho-secao afunda" onClick={() => setFechada(!fechada)} aria-expanded={!fechada}>
          <span style={{ color: tom }}>{titulo}{contagem !== undefined ? ` · ${contagem}` : ""}</span>
          <ChevronDown size={9} strokeWidth={3.2} className="c3" style={{ transform: fechada ? "rotate(-90deg)" : undefined, transition: "transform var(--normal) var(--curva)" }} />
        </button>
        <span style={{ flex: 1 }} />
        {acao}
      </div>
      {!fechada && <div className="cartao-linhas entrar">{children}</div>}
    </section>
  );
}

export function CartaoLinhas({ children }: { children: ReactNode }) {
  return <div className="cartao-linhas">{children}</div>;
}

export function Vazio({ texto }: { texto: string }) {
  return <div className="vazio t-sm c3">{texto}</div>;
}

/** Estado vazio: ícone grande que flutua, título display e descrição. */
export function EstadoVazio({ Icone, titulo, descricao }: { Icone: LucideIcon; titulo: string; descricao?: string }) {
  return (
    <div className="estado-vazio">
      <Icone size={30} strokeWidth={1.5} className="flutua c3" />
      <div className="display d-lg">{titulo}</div>
      {descricao && <div className="t-sm c3" style={{ maxWidth: 280, textAlign: "center" }}>{descricao}</div>}
    </div>
  );
}

/** Cabeçalho da tela: [leading] título display + rótulo embaixo …… [ações]. */
export function Cabecalho({ titulo, sub, direita, esquerda }: { titulo: string; sub?: string; direita?: ReactNode; esquerda?: ReactNode }) {
  return (
    <header className="entrar" style={{ display: "flex", alignItems: "center", gap: "var(--e4)" }}>
      {esquerda}
      <div style={{ display: "flex", flexDirection: "column", gap: 3, minWidth: 0 }}>
        <h1 className="display d-display">{titulo}</h1>
        {sub && <div className="t-sm c3">{sub}</div>}
      </div>
      <span style={{ flex: 1, minWidth: 16 }} />
      {direita}
    </header>
  );
}

/** Folha (modal) com fechar por Esc e clique fora. */
export function Folha({ titulo, aoFechar, children, largura }: { titulo: string; aoFechar: () => void; children: ReactNode; largura?: number }) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === "Escape" && aoFechar();
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, [aoFechar]);
  return (
    <>
      <div className="veu-modal" onClick={aoFechar} />
      <div className="folha" role="dialog" aria-label={titulo} style={largura ? { ["--largura" as string]: largura + "px" } : undefined}>
        <div className="folha-cabecalho">
          <h2 className="display d-titulo" style={{ flex: 1 }}>{titulo}</h2>
          <button className="icone-botao" aria-label="Fechar" onClick={aoFechar}>
            <X size={16} />
          </button>
        </div>
        <div className="folha-corpo">{children}</div>
      </div>
    </>
  );
}

/** Chip neutro ou tingido (Chip do design system). */
export function Chip({ texto, cor, children }: { texto: string; cor?: string; children?: ReactNode }) {
  return (
    <span className="chip-ds" style={{ color: cor ?? "var(--texto3)", background: cor ? `color-mix(in srgb, ${cor} 12%, transparent)` : "var(--superficie2)", paddingLeft: children ? 4 : 10 }}>
      {children}
      <span className="uma-linha">{texto}</span>
    </span>
  );
}

/** Calendário do mês (CalendarioMes): ponto embaixo dos dias com tarefa. */
export function CalendarioMes({ selecionado, aoEscolher, ocupado }: { selecionado: string | null; aoEscolher: (d: string) => void; ocupado?: (d: string) => boolean }) {
  const hoje = hojeISO();
  const [mes, setMes] = useState(() => (selecionado ?? hoje).slice(0, 7));
  const primeiro = deISO(mes + "-01");
  const inicio = somarDias(mes + "-01", -primeiro.getDay());
  const dias = Array.from({ length: 42 }, (_, i) => somarDias(inicio, i));
  const mudar = (n: number) => setMes(diaISO(new Date(primeiro.getFullYear(), primeiro.getMonth() + n, 1)).slice(0, 7));
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e3)" }}>
      <div style={{ display: "flex", alignItems: "center" }}>
        <span className="display d-lg" style={{ flex: 1 }}>{primeiraMaiuscula(primeiro.toLocaleDateString("pt-BR", { month: "long", year: "numeric" }))}</span>
        <button className="icone-botao" style={{ width: 28, height: 28 }} aria-label="Voltar um mês" onClick={() => mudar(-1)}><ChevronLeft size={13} /></button>
        <button className="icone-botao" style={{ width: 28, height: 28 }} aria-label="Avançar um mês" onClick={() => mudar(1)}><ChevronRight size={13} /></button>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", textAlign: "center" }}>
        {["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"].map((d) => <span key={d} className="rotulo">{d}</span>)}
      </div>
      <div className="entrar" key={mes} style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 2 }}>
        {dias.map((d) => {
          const noMes = d.slice(0, 7) === mes, esc = d === selecionado, ehHoje = d === hoje;
          return (
            <button key={d} className="dia-mes" onClick={() => aoEscolher(d)} title={rotuloLongo(d)}
              style={{ background: esc ? "var(--acento)" : undefined, color: esc ? "#fff" : ehHoje ? "var(--acento)" : noMes ? "var(--texto)" : "color-mix(in srgb, var(--texto3) 60%, transparent)", fontWeight: esc || ehHoje ? 600 : 400 }}>
              <span className="t-sm">{Number(d.slice(8))}</span>
              <span style={{ width: 4, height: 4, borderRadius: 9, background: esc ? "#fff" : "var(--acento)", opacity: ocupado?.(d) ? 1 : 0 }} />
            </button>
          );
        })}
      </div>
    </div>
  );
}

/** "9", "930", "9:30", "09h30" → "09:30". */
export function lerHorario(texto: string): string | null | undefined {
  const d = texto.replace(/\D/g, "");
  if (!d) return null;
  let h = 0, m = 0;
  if (d.length <= 2) h = Number(d);
  else if (d.length === 3) { h = Number(d[0]); m = Number(d.slice(1)); }
  else { h = Number(d.slice(0, 2)); m = Number(d.slice(2, 4)); }
  if (h > 23 || m > 59) return undefined;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

/** Seletor de data no lugar (SeletorDeDataEmbutido): atalhos, mês, horário opcional e "Pronto". */
export function SeletorData({ valor, horario = null, aoEscolher, aoMudarHorario, fechar }: { valor: string | null; horario?: string | null; aoEscolher: (d: string | null) => void; aoMudarHorario?: (h: string | null) => void; fechar?: () => void }) {
  const hoje = hojeISO();
  const porDia = usar((e) => indice(e).porDia);
  const [textoHora, setTextoHora] = useState(horario ?? "");
  const atalho = (r: string, dias: number) => {
    const d = somarDias(hoje, dias);
    return <button key={r} className={"botao " + (valor === d ? "b-primario" : "b-superficie")} title={rotuloLongo(d)} onClick={() => { aoEscolher(d); fechar?.(); }}>{r}</button>;
  };
  const mudarHora = (t: string) => {
    setTextoHora(t);
    const h = lerHorario(t);
    if (h !== undefined) aoMudarHorario?.(h);
  };
  return (
    <div className="seletor-data">
      <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--e1)" }}>
        {atalho("Hoje", 0)}
        {atalho("Amanhã", 1)}
        {atalho("Próx. semana", 7)}
        <button className={"botao " + (valor === null ? "b-primario" : "b-fantasma")} title="Tirar a data" onClick={() => { aoEscolher(null); aoMudarHorario?.(null); fechar?.(); }}>Sem data</button>
      </div>
      <CalendarioMes selecionado={valor} aoEscolher={aoEscolher} ocupado={(d) => (porDia.get(d)?.length ?? 0) > 0} />
      {aoMudarHorario && (
        <div className="linha-horario" style={{ opacity: valor ? 1 : 0.5, pointerEvents: valor ? undefined : "none" }}>
          <Clock size={12} className="c3" />
          <input className="campo-hora numeros" placeholder="Sem horário" value={textoHora} title="Digite: 9, 930, 9:30 ou 09h30" onChange={(e) => mudarHora(e.target.value)} />
          {["09:00", "12:00", "15:00"].map((h) => <button key={h} className={"botao sugestao-hora " + (horario === h ? "b-primario" : "b-superficie")} title={`Às ${h}`} onClick={() => mudarHora(h)}>{h}</button>)}
          {horario && <button className="icone-botao" style={{ width: 24, height: 24 }} aria-label="Tirar o horário" onClick={() => mudarHora("")}><X size={10} /></button>}
        </div>
      )}
      {fechar && (
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span className={"t-xs uma-linha " + (valor ? "p-medio c2" : "c3")} style={{ flex: 1 }}>{valor ? rotuloComAtraso(valor, hoje) + (horario ? ` · ${horario}` : "") : "Sem data"}</span>
          <button className="botao b-superficie" title="Fechar o calendário" onClick={fechar}>Pronto</button>
        </div>
      )}
    </div>
  );
}

/** Dropdown de listas no lugar (DropdownDeListas). */
export function DropdownListas({ atual, aoEscolher }: { atual: string | null; aoEscolher: (id: string) => void }) {
  const listas = usar((e) => e.listas);
  const nomes = usar((e) => e.listas.map((l) => nomeDaLista(e, l.id)), (a, b) => a.join() === b.join());
  return (
    <div className="dropdown-listas entrar">
      {listas.map((l, i) => (
        <button key={l.id} className="opcao-lista" onClick={() => aoEscolher(l.id)}>
          <LadrilhoLista listaId={l.id} tamanho={22} />
          <span className={"t-sm " + (l.id === atual ? "p-semi" : "p-medio")} style={{ flex: 1 }}>{nomes[i]}</span>
          {l.id === atual && <Check size={11} strokeWidth={3.2} color="var(--acento)" />}
        </button>
      ))}
    </div>
  );
}

export function useClicarFora<T extends HTMLElement>(aberto: boolean, fechar: () => void) {
  const ref = useRef<T>(null);
  useEffect(() => {
    if (!aberto) return;
    const f = (e: PointerEvent) => ref.current && !ref.current.contains(e.target as Node) && fechar();
    window.addEventListener("pointerdown", f);
    return () => window.removeEventListener("pointerdown", f);
  }, [aberto, fechar]);
  return ref;
}

export { CalendarDays, Clock, Tag, Inbox, Sun };
