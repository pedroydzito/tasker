import { useEffect, useState, useSyncExternalStore } from "react";
import { Check } from "lucide-react";
import { ler } from "../dados/armazem";
import { alternarEtiqueta, concluir, definirPrazo, excluirTarefa } from "../dados/acoes";
import { etiquetasOrdenadas, tituloDe } from "../dados/consultas";
import { hojeISO, somarDias } from "../dados/util";
import { folhas } from "./folhas";

// Menu de contexto da tarefa (o contextMenu do TaskRow.swift): botão direito no computador,
// segurar o dedo no celular.

let alvo: { id: string; x: number; y: number } | null = null;
const ouvintes = new Set<() => void>();
export function abrirContexto(id: string, x: number, y: number) {
  alvo = { id, x, y };
  ouvintes.forEach((f) => f());
}
const fechar = () => { alvo = null; ouvintes.forEach((f) => f()); };

/** Liga o menu numa linha: onContextMenu e o toque longo (500 ms parado). */
export function propsContexto(id: string) {
  let timer: ReturnType<typeof setTimeout> | null = null;
  let inicio = { x: 0, y: 0 };
  return {
    onContextMenu: (e: React.MouseEvent) => { e.preventDefault(); abrirContexto(id, e.clientX, e.clientY); },
    onTouchStart: (e: React.TouchEvent) => {
      const t = e.touches[0];
      inicio = { x: t.clientX, y: t.clientY };
      timer = setTimeout(() => { navigator.vibrate?.(8); abrirContexto(id, inicio.x, inicio.y); }, 500);
    },
    onTouchMove: (e: React.TouchEvent) => {
      const t = e.touches[0];
      if (timer && Math.hypot(t.clientX - inicio.x, t.clientY - inicio.y) > 8) { clearTimeout(timer); timer = null; }
    },
    onTouchEnd: () => { if (timer) clearTimeout(timer); timer = null; },
  };
}

export function HospedeDoContexto() {
  const a = useSyncExternalStore((f) => { ouvintes.add(f); return () => ouvintes.delete(f); }, () => alvo);
  const [etiquetas, setEtiquetas] = useState(false);
  useEffect(() => {
    setEtiquetas(false);
    if (!a) return;
    const k = (e: KeyboardEvent) => e.key === "Escape" && fechar();
    window.addEventListener("keydown", k);
    window.addEventListener("scroll", fechar, true);
    window.addEventListener("resize", fechar);
    return () => { window.removeEventListener("keydown", k); window.removeEventListener("scroll", fechar, true); window.removeEventListener("resize", fechar); };
  }, [a]);
  if (!a) return null;
  const e = ler();
  const t = e.tarefas[a.id];
  if (!t) return null;
  const hoje = hojeISO();
  const minhas = e.etiquetasDaTarefa[t.id] ?? [];
  const todas = etiquetasOrdenadas(e);
  const fazer = (f: () => void) => () => { fechar(); f(); };
  // Dentro da janela: abre para o lado que tem espaço.
  const larg = 220, alt = 300;
  const x = Math.min(a.x, innerWidth - larg - 8), y = a.y + alt > innerHeight ? Math.max(8, a.y - alt) : a.y;
  return (
    <>
      <div className="fundo-contexto" onClick={fechar} onContextMenu={(ev) => { ev.preventDefault(); fechar(); }} />
      <div className="menu-contexto brota-do-botao" role="menu" style={{ left: x, top: y, transformOrigin: "top left" }}>
        <button role="menuitem" onClick={fazer(() => concluir(t.id, !t.concluida))}>{t.concluida ? "Reabrir" : "Concluir"}</button>
        <hr />
        <button role="menuitem" onClick={fazer(() => definirPrazo(t.id, hoje))}>Para hoje</button>
        <button role="menuitem" onClick={fazer(() => definirPrazo(t.id, somarDias(hoje, 1)))}>Para amanhã</button>
        <button role="menuitem" onClick={fazer(() => definirPrazo(t.id, null))}>Tirar a data</button>
        {todas.length > 0 && (
          <>
            <button role="menuitem" aria-expanded={etiquetas} onClick={() => setEtiquetas(!etiquetas)}>Etiquetas <span style={{ marginLeft: "auto" }}>{etiquetas ? "▾" : "▸"}</span></button>
            {etiquetas && todas.map((g) => (
              <button key={g.id} role="menuitemcheckbox" aria-checked={minhas.includes(g.id)} className="sub" onClick={() => alternarEtiqueta(t.id, g.id)}>
                <span style={{ width: 14, display: "inline-flex" }}>{minhas.includes(g.id) && <Check size={12} strokeWidth={3} />}</span>
                <span style={{ color: g.cor }}>#{g.nome}</span>
              </button>
            ))}
          </>
        )}
        <hr />
        {t.link && <a role="menuitem" href={t.link} target="_blank" rel="noreferrer" onClick={fechar}>Abrir no Google</a>}
        <button role="menuitem" className="perigo" onClick={fazer(() => folhas.confirmar("Excluir tarefa", `“${tituloDe(t)}” será excluída. Dá para desfazer logo depois.`, () => excluirTarefa(t.id)))}>Excluir…</button>
      </div>
    </>
  );
}
