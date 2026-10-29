import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  Briefcase, Book, Calendar, CalendarDays, Check, ChevronLeft, ChevronRight, Circle, Clock, Dumbbell, Folder, Heart, Home,
  Inbox, List, Music, Paperclip, Pause, Play, Plane, ShoppingCart, Star, Sun, Tag, X, type LucideIcon,
} from "lucide-react";
import { usar } from "../dados/armazem";
import { alternarCronometro, concluir } from "../dados/acoes";
import { corDaLista, etiquetasDe, horarioDe, indice, nomeDaLista, tituloDe } from "../dados/consultas";
import type { Tarefa } from "../dados/tipos";
import { deISO, diaISO, hojeISO, primeiraMaiuscula, rotuloComAtraso, somarDias } from "../dados/util";
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

export function Circulo({ feito, cor, aoClicar }: { feito: boolean; cor: string; aoClicar: () => void }) {
  return (
    <button
      className={"circulo" + (feito ? " feito" : "")}
      style={{ ["--cor" as string]: cor }}
      aria-label={feito ? "Desmarcar" : "Concluir"}
      onClick={(ev) => {
        ev.stopPropagation();
        aoClicar();
      }}
    >
      <Check size={11} strokeWidth={3} />
    </button>
  );
}

/** Linha de tarefa no desenho original: círculo, título, e uma linha discreta de data/lista. */
export function LinhaTarefa({ t, mostrarData = true, mostrarLista = true, compacta = false }: { t: Tarefa; mostrarData?: boolean; mostrarLista?: boolean; compacta?: boolean }) {
  const sel = useSelecionada();
  const cor = usar((e) => corDaLista(e, t.listaId));
  const lista = usar((e) => (mostrarLista ? nomeDaLista(e, t.listaId) : ""));
  const etiquetas = usar((e) => etiquetasDe(e, t.id), (a, b) => a.length === b.length && a.every((x, i) => x === b[i]));
  const filhas = usar((e) => indice(e).filhas.get(t.id)?.length ?? 0);
  const anexos = usar((e) => e.anexos.filter((a) => a.tarefaId === t.id).length);
  const hoje = hojeISO();
  const horario = horarioDe(t);
  const meta: string[] = [];
  if (mostrarData && t.prazo) meta.push(rotuloComAtraso(t.prazo, hoje));
  if (horario) meta.push(horario);
  if (lista) meta.push(lista);
  const atrasada = !t.concluida && t.prazo && t.prazo < hoje;
  return (
    <div className={"linha-tarefa" + (sel === t.id ? " selecionada" : "") + (compacta ? " compacta" : "")} onClick={() => selecionar(t.id)} data-tarefa={t.id}>
      <Circulo feito={t.concluida} cor={cor} aoClicar={() => concluir(t.id, !t.concluida)} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className={"t-md uma-linha" + (t.concluida ? " riscado" : "")}>{tituloDe(t)}</div>
        {(meta.length > 0 || etiquetas.length > 0 || filhas > 0 || anexos > 0) && (
          <div className="t-xs c3" style={{ display: "flex", gap: 8, alignItems: "center", marginTop: 2 }}>
            {meta.length > 0 && <span style={atrasada ? { color: "var(--perigo)" } : undefined}>{meta.join(" · ")}</span>}
            {etiquetas.map((g) => (
              <span key={g.id} style={{ color: g.cor }}>#{g.nome}</span>
            ))}
            {filhas > 0 && <span>{filhas} sub</span>}
            {anexos > 0 && (
              <span style={{ display: "inline-flex", alignItems: "center", gap: 2 }}>
                <Paperclip size={11} />
                {anexos}
              </span>
            )}
          </div>
        )}
      </div>
    </div>
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

export function Secao({ titulo, children, acao }: { titulo: string; children: ReactNode; acao?: ReactNode }) {
  return (
    <section style={{ display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 12px" }}>
        <span className="rotulo">{titulo}</span>
        {acao}
      </div>
      <div className="cartao-linhas">{children}</div>
    </section>
  );
}

export function Vazio({ texto }: { texto: string }) {
  return <div className="vazio t-sm c3">{texto}</div>;
}

export function Cabecalho({ titulo, sub, direita }: { titulo: string; sub?: string; direita?: ReactNode }) {
  return (
    <header style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between", gap: 12 }}>
      <div>
        <h1 className="display d-display">{titulo}</h1>
        {sub && <div className="t-sm c3" style={{ marginTop: 4 }}>{sub}</div>}
      </div>
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
