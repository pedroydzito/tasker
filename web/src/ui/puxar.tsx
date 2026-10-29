import { useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";
import { puxar } from "../dados/sync";

// Puxar para atualizar (design system §8.41): só no app instalado e no celular. Começa com a
// página no topo e o dedo descendo; anda 0,45 × o dedo (teto 96 px) e vale a partir de 64 px.

export function PuxarParaAtualizar() {
  const [puxado, setPuxado] = useState(0);
  const [atualizando, setAtualizando] = useState(false);
  useEffect(() => {
    const instalado = matchMedia("(display-mode: standalone)").matches || (navigator as { standalone?: boolean }).standalone;
    if (!instalado || !matchMedia("(max-width: 760px)").matches) return;
    let inicio: number | null = null;
    let valeu = false;
    let atual = 0;
    const pagina = () => document.querySelector<HTMLElement>(".casca-pagina > .pagina");
    const start = (e: TouchEvent) => {
      const alvo = e.target as Element;
      if (alvo.closest('[role="dialog"], [data-sem-puxar], .menu-mais, .nav-celular')) return;
      const p = pagina();
      if (!p || !p.contains(alvo) || p.scrollTop > 0) return;
      inicio = e.touches[0].clientY;
      valeu = false;
    };
    const move = (e: TouchEvent) => {
      if (inicio === null) return;
      const dy = e.touches[0].clientY - inicio;
      if (dy <= 0 || (pagina()?.scrollTop ?? 0) > 0) { if (atual) { atual = 0; setPuxado(0); } return; }
      atual = Math.min(96, dy * 0.45);
      if (atual >= 64 && !valeu) { valeu = true; navigator.vibrate?.(8); }
      if (atual < 64) valeu = false;
      setPuxado(atual);
    };
    const end = () => {
      if (inicio === null) return;
      inicio = null;
      if (atual >= 64) {
        setAtualizando(true);
        void puxar(true).finally(() => { setAtualizando(false); setPuxado(0); });
      } else setPuxado(0);
      atual = 0;
    };
    window.addEventListener("touchstart", start, { passive: true });
    window.addEventListener("touchmove", move, { passive: true });
    window.addEventListener("touchend", end, { passive: true });
    window.addEventListener("touchcancel", end, { passive: true });
    return () => {
      window.removeEventListener("touchstart", start);
      window.removeEventListener("touchmove", move);
      window.removeEventListener("touchend", end);
      window.removeEventListener("touchcancel", end);
    };
  }, []);
  if (!puxado && !atualizando) return null;
  const altura = atualizando ? 48 / 0.6 : puxado;
  return (
    <div className="puxar" role={atualizando ? "status" : undefined} aria-label={atualizando ? "Atualizando" : undefined}>
      <span className="puxar-circulo" style={{ transform: `translateY(${altura * 0.6}px)`, transition: puxado && !atualizando ? "none" : undefined }}>
        <RefreshCw size={16} className={atualizando ? "girando" : undefined}
          style={atualizando ? undefined : { transform: `rotate(${(puxado / 64) * 270}deg)`, opacity: Math.min(1, puxado / 64) }} />
      </span>
    </div>
  );
}
