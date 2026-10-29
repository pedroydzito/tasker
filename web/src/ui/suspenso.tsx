import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import { normalizarBusca } from "../dados/util";

// Menu suspenso (design system §8.37): a base de todo menu que nasce de um botão. Pinta no
// body por portal (o z-index de uma lista animada não o prende), abaixo do gatilho e, se não
// couber, acima; acompanha a rolagem; Esc e Tab saindo devolvem o foco ao gatilho.

export function MenuSuspenso({ aberto, ancora, aoFechar, alinhar = "esquerda", className, children }: {
  aberto: boolean; ancora: React.RefObject<HTMLElement | null>; aoFechar: () => void; alinhar?: "esquerda" | "direita" | "esticar"; className?: string; children: ReactNode;
}) {
  const painel = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ left: number; top: number; width?: number } | null>(null);
  const fechar = useRef(aoFechar);
  fechar.current = aoFechar;

  useLayoutEffect(() => {
    if (!aberto) { setPos(null); return; }
    let ultima = "";
    const medir = () => {
      const a = ancora.current?.getBoundingClientRect();
      const p = painel.current;
      if (!a || !p) return;
      const folga = 8;
      const largura = alinhar === "esticar" ? a.width : Math.min(p.offsetWidth, innerWidth - folga * 2);
      let left = alinhar === "direita" ? a.right - largura : a.left;
      left = Math.max(folga, Math.min(left, innerWidth - largura - folga));
      const alt = p.offsetHeight;
      let top = a.bottom + 4;
      if (top + alt > innerHeight - folga && a.top - 4 - alt >= folga) top = a.top - 4 - alt;
      const novo = { left, top, width: alinhar === "esticar" ? largura : undefined };
      const sig = JSON.stringify(novo);
      if (sig !== ultima) { ultima = sig; setPos(novo); }
    };
    medir();
    const rolar = (e: Event) => { if (painel.current?.contains(e.target as Node)) return; medir(); };
    window.addEventListener("scroll", rolar, true);
    window.addEventListener("resize", medir);
    const tecla = (e: KeyboardEvent) => {
      if (e.key === "Escape") { e.stopPropagation(); fechar.current(); ancora.current?.focus(); }
    };
    window.addEventListener("keydown", tecla, true);
    // Aberto pelo teclado, o foco entra no primeiro item; pelo toque, não.
    if (ancora.current?.matches(":focus-visible")) requestAnimationFrame(() => painel.current?.querySelector<HTMLElement>("button, a, input")?.focus());
    return () => { window.removeEventListener("scroll", rolar, true); window.removeEventListener("resize", medir); window.removeEventListener("keydown", tecla, true); };
  }, [aberto, alinhar]);

  if (!aberto) return null;
  return createPortal(
    <>
      <div className="fundo-suspenso" onClick={aoFechar} onContextMenu={(e) => { e.preventDefault(); aoFechar(); }} />
      <div ref={painel} className={"painel-suspenso animar-surgir-baixo " + (className ?? "")}
        style={{ left: pos?.left ?? 0, top: pos?.top ?? 0, width: pos?.width, visibility: pos ? "visible" : "hidden" }}
        onKeyDown={(e) => {
          if (e.key !== "Tab") return;
          const f = painel.current?.querySelectorAll<HTMLElement>("button, a, input");
          if (!f?.length) return;
          if ((!e.shiftKey && document.activeElement === f[f.length - 1]) || (e.shiftKey && document.activeElement === f[0])) { e.preventDefault(); aoFechar(); ancora.current?.focus(); }
        }}>
        {children}
      </div>
    </>,
    document.body,
  );
}

/**
 * Campo com sugestões (§8.36), no modo "vários": o texto é só busca, as escolhidas viram fichas
 * e saem da lista; a lista só existe enquanto se procura. Busca sem acento nem caixa.
 */
export function CampoSugestoes({ opcoes, escolhidas, aoEscolher, aoRemover, aoCriar, placeholder }: {
  opcoes: { id: string; rotulo: string; cor?: string }[]; escolhidas: string[]; aoEscolher: (id: string) => void; aoRemover: (id: string) => void; aoCriar?: (texto: string) => void; placeholder: string;
}) {
  const [texto, setTexto] = useState("");
  const [aberto, setAberto] = useState(false);
  const campo = useRef<HTMLInputElement>(null);
  const termo = normalizarBusca(texto.replace(/^#/, "")).trim();
  const lista = opcoes.filter((o) => !escolhidas.includes(o.id) && (!termo || normalizarBusca(o.rotulo + " " + o.id).includes(termo)));
  const exato = opcoes.some((o) => normalizarBusca(o.rotulo) === termo);
  useEffect(() => { if (!texto) return; setAberto(true); }, [texto]);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
      <input ref={campo} className="campo" value={texto} placeholder={placeholder}
        onFocus={() => setAberto(true)} onBlur={() => setTimeout(() => setAberto(false), 150)}
        onChange={(e) => setTexto(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && texto.trim()) { e.preventDefault(); if (lista[0] && (exato || !aoCriar)) aoEscolher(lista[0].id); else aoCriar?.(texto.replace(/^#/, "").trim()); setTexto(""); }
          if (e.key === "Backspace" && !texto && escolhidas.length) aoRemover(escolhidas[escolhidas.length - 1]);
        }} />
      {escolhidas.length > 0 && (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
          {escolhidas.map((id) => {
            const o = opcoes.find((x) => x.id === id);
            if (!o) return null;
            return (
              <span key={id} className="ficha" style={o.cor ? { background: o.cor, color: "#fff" } : undefined}>
                #{o.rotulo}
                <button className="sem-veu" aria-label={`Remover ${o.rotulo}`} onClick={() => aoRemover(id)}><X size={12} strokeWidth={2.6} /></button>
              </span>
            );
          })}
        </div>
      )}
      <MenuSuspenso aberto={aberto && (lista.length > 0 || (!!aoCriar && !!termo && !exato))} ancora={campo} aoFechar={() => setAberto(false)} alinhar="esticar" className="cartao-suspenso">
        <div className="lista-sugestoes">
          {lista.map((o) => (
            <button key={o.id} className="sugestao sem-veu" style={o.cor ? { color: o.cor } : undefined} onMouseDown={(e) => e.preventDefault()} onClick={() => { aoEscolher(o.id); setTexto(""); campo.current?.focus(); }}>#{o.rotulo}</button>
          ))}
          {aoCriar && termo && !exato && (
            <button className="sugestao sem-veu" onMouseDown={(e) => e.preventDefault()} onClick={() => { aoCriar(texto.replace(/^#/, "").trim()); setTexto(""); }}>Criar “{texto.replace(/^#/, "").trim()}”</button>
          )}
        </div>
      </MenuSuspenso>
    </div>
  );
}
