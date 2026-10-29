import { useSyncExternalStore, useRef } from "react";
import { gravarEstado } from "./espelho";
import { PREFERENCIAS_PADRAO, type Estado } from "./tipos";

// O estado do app vive aqui, num módulo, fora do React (desempenho §4.1, §4.5): trocar de tela
// não recria nada e a tela volta cheia na hora. O espelho no IndexedDB é gravado com atraso.

export const ESTADO_INICIAL: Estado = {
  modo: "carregando",
  email: null,
  nome: null,
  avatar: null,
  googlePendente: false,
  listas: [],
  listaFixa: null,
  tarefas: {},
  agendas: [],
  eventos: [],
  etiquetas: [],
  etiquetasDaTarefa: {},
  notas: [],
  despejo: [],
  tempos: {},
  cronometro: { tarefaId: null, inicio: null },
  anexos: [],
  prefs: PREFERENCIAS_PADRAO,
  ultimaSync: null,
  sincronizando: false,
  erro: null,
  pendencias: 0,
  online: typeof navigator === "undefined" ? true : navigator.onLine,
};

let estado: Estado = ESTADO_INICIAL;
const ouvintes = new Set<() => void>();
let chaveEspelho: string | null = null;
let gravacao: ReturnType<typeof setTimeout> | null = null;

export function ler(): Estado {
  return estado;
}

export function assinar(fn: () => void): () => void {
  ouvintes.add(fn);
  return () => ouvintes.delete(fn);
}

/** Campos que não vão para o espelho (são da sessão, não dos dados). */
const SO_EM_MEMORIA: (keyof Estado)[] = ["sincronizando", "erro", "online", "pendencias", "modo"];

/** Atualiza o estado. Só avisa quem escuta se algo mudou de verdade (não pinta o que não mudou, §4.8). */
export function definir(mudanca: Partial<Estado> | ((e: Estado) => Partial<Estado>)): void {
  const parcial = typeof mudanca === "function" ? mudanca(estado) : mudanca;
  let mudou = false;
  let deDados = false;
  for (const k of Object.keys(parcial) as (keyof Estado)[]) {
    if (estado[k] !== parcial[k]) {
      mudou = true;
      if (!SO_EM_MEMORIA.includes(k)) deDados = true;
    }
  }
  if (!mudou) return;
  estado = { ...estado, ...parcial };
  for (const fn of ouvintes) fn();
  if (deDados) agendarEspelho();
}

/** Para onde o espelho é gravado (a conta atual, ou "local"). Trocar de conta troca a chave. */
export function usarEspelho(chave: string | null) {
  chaveEspelho = chave;
}

export const espelhoAtual = () => chaveEspelho;

function agendarEspelho() {
  if (!chaveEspelho) return;
  if (gravacao) clearTimeout(gravacao);
  gravacao = setTimeout(gravarAgora, 500);
}

export function gravarAgora() {
  if (gravacao) clearTimeout(gravacao);
  gravacao = null;
  if (!chaveEspelho) return;
  const { sincronizando: _s, erro: _e, online: _o, pendencias: _p, ...dados } = estado;
  void gravarEstado(chaveEspelho, dados);
}

/** Restaura o estado (troca de conta, logout). */
export function substituir(novo: Estado) {
  estado = novo;
  for (const fn of ouvintes) fn();
}

/**
 * Lê um pedaço do estado. Repinta só quando o pedaço muda; `igual` permite comparar listas
 * derivadas por conteúdo (o seletor que monta um array novo a cada chamada não repinta à toa).
 */
export function usar<T>(seletor: (e: Estado) => T, igual: (a: T, b: T) => boolean = Object.is): T {
  // A chave inclui o seletor: um seletor novo (props mudaram) recalcula mesmo com o estado igual.
  const ultimo = useRef<{ entrada: Estado; seletor: unknown; saida: T } | null>(null);
  const ler = () => {
    const atual = estado;
    const u = ultimo.current;
    if (u && u.entrada === atual && u.seletor === seletor) return u.saida;
    const saida = seletor(atual);
    if (u && igual(u.saida, saida)) {
      ultimo.current = { entrada: atual, seletor, saida: u.saida };
      return u.saida;
    }
    ultimo.current = { entrada: atual, seletor, saida };
    return saida;
  };
  return useSyncExternalStore(assinar, ler, ler);
}

export const mesmaLista = <T,>(a: T[], b: T[]) => a.length === b.length && a.every((x, i) => x === b[i]);
