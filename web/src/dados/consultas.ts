import type { Estado, Tarefa } from "./tipos";
import { rotuloLongo, corDaChave, hojeISO, normalizarBusca, separarHorario } from "./util";

// Derivações de tela calculadas uma vez por versão dos dados e guardadas no módulo
// (desempenho §6.3: um useMemo morreria a cada navegação).

export interface Indice {
  abertas: Tarefa[];
  hoje: Tarefa[];
  atrasadas: Tarefa[];
  depois: Tarefa[];
  semData: Tarefa[];
  porDia: Map<string, Tarefa[]>;
  porLista: Map<string, Tarefa[]>;
  concluidas: Tarefa[];
  concluidasHoje: Tarefa[];
  concluidasPorDia: Map<string, Tarefa[]>;
  concluidasPorLista: Map<string, Tarefa[]>;
  filhas: Map<string, Tarefa[]>;
}

let memo: { tarefas: Estado["tarefas"]; listas: Estado["listas"]; hoje: string; indice: Indice } | null = null;

const porPosicao = (a: Tarefa, b: Tarefa) => (a.posicao < b.posicao ? -1 : a.posicao > b.posicao ? 1 : 0);

export function indice(e: Estado): Indice {
  const hoje = hojeISO();
  if (memo && memo.tarefas === e.tarefas && memo.listas === e.listas && memo.hoje === hoje) return memo.indice;
  const ordemLista = new Map(e.listas.map((l, i) => [l.id, i]));
  const abertas: Tarefa[] = [];
  const feitas: Tarefa[] = [];
  const filhas = new Map<string, Tarefa[]>();
  for (const t of Object.values(e.tarefas)) {
    (t.concluida ? feitas : abertas).push(t);
    if (t.mae) {
      const l = filhas.get(t.mae) ?? [];
      l.push(t);
      filhas.set(t.mae, l);
    }
  }
  for (const l of filhas.values()) l.sort(porPosicao);
  // Data, depois ordem das listas, depois posição.
  abertas.sort((a, b) => {
    const da = a.prazo ?? "9999", db = b.prazo ?? "9999";
    if (da !== db) return da < db ? -1 : 1;
    if (a.listaId !== b.listaId) return (ordemLista.get(a.listaId) ?? 999) - (ordemLista.get(b.listaId) ?? 999);
    return porPosicao(a, b);
  });
  feitas.sort((a, b) => ((a.concluidaEm ?? "") > (b.concluidaEm ?? "") ? -1 : 1));

  const ind: Indice = {
    abertas, hoje: [], atrasadas: [], depois: [], semData: [],
    porDia: new Map(), porLista: new Map(), concluidas: feitas, concluidasHoje: [],
    concluidasPorDia: new Map(), concluidasPorLista: new Map(), filhas,
  };
  for (const t of abertas) {
    push(ind.porLista, t.listaId, t);
    if (!t.prazo) { ind.semData.push(t); continue; }
    push(ind.porDia, t.prazo, t);
    if (t.prazo < hoje) ind.atrasadas.push(t);
    else if (t.prazo === hoje) ind.hoje.push(t);
    else ind.depois.push(t);
  }
  // Hoje: com horário primeiro, pela hora.
  ind.hoje.sort((a, b) => (horarioDe(a) ?? "99") < (horarioDe(b) ?? "99") ? -1 : (horarioDe(a) ?? "99") > (horarioDe(b) ?? "99") ? 1 : 0);
  for (const t of feitas) {
    push(ind.concluidasPorLista, t.listaId, t);
    if (t.prazo) push(ind.concluidasPorDia, t.prazo, t);
    if (t.concluidaEm && t.concluidaEm.slice(0, 10) === hoje) ind.concluidasHoje.push(t);
  }
  memo = { tarefas: e.tarefas, listas: e.listas, hoje, indice: ind };
  return ind;
}

function push<K, V>(m: Map<K, V[]>, k: K, v: V) {
  const l = m.get(k);
  if (l) l.push(v);
  else m.set(k, [v]);
}

const horarios = new Map<string, { texto: string; horario: string | null }>();
function partes(t: Tarefa) {
  const chave = t.notas;
  let p = horarios.get(chave);
  if (!p) {
    p = separarHorario(t.notas);
    if (horarios.size > 5000) horarios.clear();
    horarios.set(chave, p);
  }
  return p;
}
export const horarioDe = (t: Tarefa) => partes(t).horario;
export const notasVisiveis = (t: Tarefa) => partes(t).texto;

export function tituloDe(t: Tarefa): string {
  return t.titulo.trim() || "Sem título";
}

/** "🎨 Taís" → "Taís" (o ícone é escolhido no app). */
export function nomeDaLista(e: Estado, id: string): string {
  const l = e.listas.find((x) => x.id === id);
  if (!l) return "";
  const sem = l.titulo.replace(/^[^\p{L}\p{N}]+/u, "").trim();
  return sem || l.titulo;
}

export function corDaLista(e: Estado, id: string): string {
  return e.prefs.coresListas[id] ?? corDaChave(id);
}

export function iconeDaLista(e: Estado, id: string): string | null {
  return e.prefs.iconesListas[id] || null;
}

export function listaPadrao(e: Estado): string | null {
  const p = e.prefs.listaPadrao;
  if (p && e.listas.some((l) => l.id === p)) return p;
  return e.listas[0]?.id ?? null;
}

export function etiquetasDe(e: Estado, tarefaId: string) {
  const ids = e.etiquetasDaTarefa[tarefaId] ?? [];
  return e.etiquetas.filter((t) => ids.includes(t.id));
}

export function etiquetasOrdenadas(e: Estado) {
  const ordem = e.prefs.ordemEtiquetas;
  const pos = new Map(ordem.map((id, i) => [id, i]));
  return [...e.etiquetas].sort((a, b) => (pos.get(a.id) ?? ordem.length + a.ordem) - (pos.get(b.id) ?? ordem.length + b.ordem));
}

/** Número do ícone e da barra lateral (sem energia, nenhum número cobra). */
export function contagemHoje(e: Estado): number {
  const i = indice(e);
  return i.hoje.length + (e.prefs.contarAtrasadas ? i.atrasadas.length : 0);
}

export function eventosDoDia(e: Estado, dia: string) {
  const inicio = new Date(dia + "T00:00:00").getTime();
  const fim = inicio + 86_400_000;
  return e.eventos.filter((ev) => {
    if (e.prefs.agendasVisiveis[ev.agendaId] === false) return false;
    if (ev.diaTodo) return ev.inicio.slice(0, 10) <= dia && dia < ev.fim.slice(0, 10);
    const a = new Date(ev.inicio).getTime(), b = new Date(ev.fim).getTime();
    return a < fim && b > inicio;
  });
}

export function tempoDe(e: Estado, id: string, agora = Date.now()): number {
  let t = e.tempos[id] ?? 0;
  if (e.cronometro.tarefaId === id && e.cronometro.inicio) t += Math.max(0, (agora - new Date(e.cronometro.inicio).getTime()) / 1000);
  return t;
}

// MARK: Busca (⌘K)

export interface Resultado {
  tipo: "tarefa" | "nota" | "despejo" | "evento";
  alvo: string;
  titulo: string;
  trecho: string | null;
  data: string | null;
  concluida: boolean;
  pontos: number;
}

export function buscar(e: Estado, consulta: string, limite = 40): Resultado[] {
  const q = normalizarBusca(consulta).trim();
  const palavras = q.split(/\s+/).filter(Boolean);
  if (!palavras.length) return [];
  const pontuar = (titulo: string, corpo: string): number | null => {
    const t = normalizarBusca(titulo), c = normalizarBusca(corpo);
    if (!palavras.every((p) => t.includes(p) || c.includes(p))) return null;
    if (t.startsWith(q)) return 100;
    if (t.includes(q)) return 70;
    if (palavras.every((p) => t.includes(p))) return 50;
    return 20;
  };
  const trecho = (corpo: string) => {
    const l = corpo.split("\n").map((x) => x.trim()).filter(Boolean);
    const achada = l.find((x) => palavras.some((p) => normalizarBusca(x).includes(p))) ?? l[0];
    if (!achada) return null;
    return achada.length > 90 ? achada.slice(0, 90) + "…" : achada;
  };
  const r: Resultado[] = [];
  for (const t of Object.values(e.tarefas)) {
    if (t.provisoria) continue;
    const corpo = notasVisiveis(t);
    const p = pontuar(t.titulo, corpo);
    if (p !== null) r.push({ tipo: "tarefa", alvo: t.id, titulo: tituloDe(t), trecho: trecho(corpo), data: t.prazo, concluida: t.concluida, pontos: p + (t.concluida ? 0 : 5) });
  }
  for (const n of e.notas) {
    const titulo = n.titulo || (n.dia ? rotuloLongo(n.dia) : n.texto.split("\n")[0] || "Sem título");
    const p = pontuar(titulo, n.texto);
    if (p !== null) r.push({ tipo: "nota", alvo: n.id, titulo, trecho: trecho(n.texto), data: n.dia ?? n.editadaEm, concluida: false, pontos: p + 3 });
  }
  for (const d of e.despejo) {
    const p = pontuar(d.texto, "");
    if (p !== null) r.push({ tipo: "despejo", alvo: d.id, titulo: d.texto || "Foto", trecho: null, data: d.criadoEm, concluida: false, pontos: p + 2 });
  }
  const vistos = new Set<string>();
  for (const ev of e.eventos) {
    if (vistos.has(ev.id)) continue;
    vistos.add(ev.id);
    const p = pontuar(ev.titulo, "");
    if (p !== null) r.push({ tipo: "evento", alvo: ev.id, titulo: ev.titulo, trecho: null, data: ev.inicio, concluida: false, pontos: p });
  }
  return r.sort((a, b) => b.pontos - a.pontos || ((b.data ?? "") > (a.data ?? "") ? 1 : -1)).slice(0, limite);
}

/** Linhas "[ ] algo" de uma nota que ainda não viraram tarefa. */
export function pendentesDaNota(texto: string): { linha: number; titulo: string }[] {
  return texto.split("\n").flatMap((l, i) => {
    const s = l.trim();
    for (const p of ["- [ ]", "[ ]", "☐"]) {
      if (s.startsWith(p)) {
        const titulo = s.slice(p.length).trim();
        return titulo ? [{ linha: i, titulo }] : [];
      }
    }
    return [];
  });
}
