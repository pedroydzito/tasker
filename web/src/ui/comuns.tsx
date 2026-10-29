import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  AlertCircle, AlignLeft, ChevronDown, Briefcase, Book, Calendar, CalendarDays, Check, ChevronLeft, ChevronRight, Circle, Clock, Dumbbell, Folder, Heart, Home,
  Inbox, List, Music, Pause, Play, Plane, ShoppingCart, Star, Sun, Tag, X, type LucideIcon,
} from "lucide-react";
import { usar } from "../dados/armazem";
import { alternarCronometro, concluir } from "../dados/acoes";
import { corDaLista, etiquetasDe, horarioDe, iconeDaLista, indice, nomeDaLista, notasVisiveis, tituloDe } from "../dados/consultas";
import type { Tarefa } from "../dados/tipos";
import { deISO, diaISO, hojeISO, primeiraMaiuscula, rotuloCurto, somarDias } from "../dados/util";
import { selecionar, useSelecionada } from "./rota";

/** Ícones das listas: os nomes SF guardados nas preferências viram ícones lucide. */
const ICONES: Record<string, LucideIcon> = {
  "tray": Inbox, "briefcase": Briefcase, "house": Home, "cart": ShoppingCart, "heart": Heart, "star": Star, "book": Book,
  "airplane": Plane, "music.note": Music, "dumbbell": Dumbbell, "folder": Folder, "calendar": Calendar, "sun.max": Sun, "list.bullet": List,
};
export const NOMES_ICONES = Object.keys(ICONES);
export function IconeLista({ nome, tamanho = 15 }: { nome: string | null; tamanho?: number }) {
  const I = (nome && ICONES[nome.replace(/\.fill$/, "")]) || Circle;
  return <I size={tamanho} strokeWidth={2} />;
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

/** Seletor de data: atalhos + mês. Ocupa a largura disponível. */
export function SeletorData({ valor, aoEscolher }: { valor: string | null; aoEscolher: (d: string | null) => void }) {
  const hoje = hojeISO();
  const [mes, setMes] = useState(() => (valor ?? hoje).slice(0, 7));
  const primeiro = deISO(mes + "-01");
  const inicio = somarDias(mes + "-01", -((primeiro.getDay() + 6) % 7));
  const dias = Array.from({ length: 42 }, (_, i) => somarDias(inicio, i));
  const mudarMes = (d: number) => {
    const m = new Date(primeiro.getFullYear(), primeiro.getMonth() + d, 1);
    setMes(diaISO(m).slice(0, 7));
  };
  const atalhos: [string, string | null][] = [["Hoje", hoje], ["Amanhã", somarDias(hoje, 1)], ["Próx. semana", somarDias(hoje, 7 - ((deISO(hoje).getDay() + 6) % 7))], ["Sem data", null]];
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10, width: "100%" }}>
      <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
        {atalhos.map(([r, d]) => (
          <button key={r} className="chip" aria-pressed={valor === d} onClick={() => aoEscolher(d)}>{r}</button>
        ))}
      </div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <span className="t-sm p-semi">{primeiraMaiuscula(primeiro.toLocaleDateString("pt-BR", { month: "long", year: "numeric" }))}</span>
        <span>
          <button className="icone-botao" aria-label="Mês anterior" onClick={() => mudarMes(-1)}><ChevronLeft size={15} /></button>
          <button className="icone-botao" aria-label="Próximo mês" onClick={() => mudarMes(1)}><ChevronRight size={15} /></button>
        </span>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 2, textAlign: "center" }}>
        {["S", "T", "Q", "Q", "S", "S", "D"].map((d, i) => <span key={i} className="t-xs c3">{d}</span>)}
        {dias.map((d) => (
          <button
            key={d}
            className="veu t-sm"
            onClick={() => aoEscolher(d)}
            style={{
              aspectRatio: "1", borderRadius: 999, opacity: d.slice(0, 7) === mes ? 1 : 0.35,
              background: d === valor ? "var(--acento)" : undefined, color: d === valor ? "#fff" : d === hoje ? "var(--acento)" : undefined,
              fontWeight: d === hoje || d === valor ? 700 : 500,
            }}
          >
            {Number(d.slice(8))}
          </button>
        ))}
      </div>
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
