import { useSyncExternalStore } from "react";

// Rotas por hash (#/hoje, #/lista/<id>...): o mesmo build serve Vercel, PWA e o app do Mac
// (que carrega o index.html do pacote, sem servidor).

export type Rota =
  | { tela: "hoje" | "amanha" | "proximas" | "calendario" | "todas" | "concluidas" | "despejo" | "notas" | "ajustes" | "menu" }
  | { tela: "lista"; id: string }
  | { tela: "etiqueta"; id: string }
  | { tela: "nota"; id: string };

export function lerRota(hash = location.hash): Rota {
  const [tela, id] = hash.replace(/^#\/?/, "").split("/").map(decodeURIComponent);
  if ((tela === "lista" || tela === "etiqueta" || tela === "nota") && id) return { tela, id };
  const simples = ["hoje", "amanha", "proximas", "calendario", "todas", "concluidas", "despejo", "notas", "ajustes", "menu"] as const;
  return { tela: (simples as readonly string[]).includes(tela) ? (tela as (typeof simples)[number]) : "hoje" };
}

export function irPara(r: Rota) {
  const h = "#/" + r.tela + ("id" in r ? "/" + encodeURIComponent(r.id) : "");
  if (location.hash !== h) location.hash = h;
}

let cache = { hash: "", rota: lerRota("") };
export function useRota(): Rota {
  return useSyncExternalStore(
    (f) => {
      window.addEventListener("hashchange", f);
      return () => window.removeEventListener("hashchange", f);
    },
    () => {
      if (cache.hash !== location.hash) cache = { hash: location.hash, rota: lerRota() };
      return cache.rota;
    },
  );
}

// Tarefa aberta no inspetor (estado de módulo: sobrevive à troca de tela).
let selecionada: string | null = null;
const ouvintes = new Set<() => void>();
export function selecionar(id: string | null) {
  selecionada = id;
  ouvintes.forEach((f) => f());
}
export function useSelecionada() {
  return useSyncExternalStore(
    (f) => {
      ouvintes.add(f);
      return () => ouvintes.delete(f);
    },
    () => selecionada,
  );
}
