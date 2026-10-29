import { useSyncExternalStore } from "react";

// Avisos do rodapé: "Desfazer" (3 s, só então a exclusão vai de verdade), sucesso (2 s, ações
// seguidas se somam: "3 tarefas adicionadas") e erro.

export interface Aviso {
  id: number;
  texto: string;
  tipo: "desfazer" | "sucesso" | "erro";
  quantidade: number;
  plural?: string;
  desfazer?: () => void;
  confirmar?: () => void;
}

let atual: Aviso | null = null;
let timer: ReturnType<typeof setTimeout> | null = null;
let seq = 0;
const ouvintes = new Set<() => void>();
const emitir = () => ouvintes.forEach((f) => f());

function trocar(novo: Aviso | null, ms: number) {
  // Um "Desfazer" que estava na tela confirma ao dar lugar ao próximo.
  if (atual?.tipo === "desfazer" && atual.confirmar && atual !== novo) atual.confirmar();
  if (timer) clearTimeout(timer);
  atual = novo;
  emitir();
  if (novo) {
    timer = setTimeout(() => {
      if (atual?.id !== novo.id) return;
      if (novo.tipo === "desfazer") novo.confirmar?.();
      atual = null;
      emitir();
    }, ms);
  }
}

/** Exclusão com "Desfazer": `confirmar` roda quando o aviso some sem ninguém desfazer. */
export function comDesfazer(texto: string, desfazer: () => void, confirmar: () => void) {
  trocar({ id: ++seq, texto, tipo: "desfazer", quantidade: 1, desfazer, confirmar }, 3000);
}

export function desfazerAgora() {
  const a = atual;
  if (!a || a.tipo !== "desfazer") return;
  if (timer) clearTimeout(timer);
  atual = null;
  a.desfazer?.();
  emitir();
}

/** "✓ Tarefa adicionada"; repetido em seguida vira "3 tarefas adicionadas". */
export function sucesso(singular: string, plural?: string) {
  if (atual?.tipo === "desfazer") return; // o Desfazer tem prioridade
  const quantidade = atual?.tipo === "sucesso" && atual.texto === singular ? atual.quantidade + 1 : 1;
  trocar({ id: ++seq, texto: singular, plural, tipo: "sucesso", quantidade }, 2000);
}

export function avisar(texto: string, _o: { erro?: boolean } = {}) {
  trocar({ id: ++seq, texto, tipo: "erro", quantidade: 1 }, 5000);
}

export function textoDoAviso(a: Aviso): string {
  return a.quantidade > 1 && a.plural ? `${a.quantidade} ${a.plural}` : a.texto;
}

export function useAviso(): Aviso | null {
  return useSyncExternalStore(
    (f) => {
      ouvintes.add(f);
      return () => ouvintes.delete(f);
    },
    () => atual,
    () => null,
  );
}

/** Confirma o que estiver esperando (antes de sair da conta, por exemplo). */
export function confirmarPendente() {
  if (atual?.tipo === "desfazer") {
    const a = atual;
    atual = null;
    if (timer) clearTimeout(timer);
    a.confirmar?.();
    emitir();
  }
}
