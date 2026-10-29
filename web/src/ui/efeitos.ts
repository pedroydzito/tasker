// Efeitos de classe que precisam de um ouvinte (design system §6.7), instalados uma vez.

const AQUECE = ".linha-tarefa, .cartao-despejo, .linha-nota, .linha-pilha, .resultado, .pasta, .dia-cal, .item-lateral, .item-menu";

export function ligarEfeitos() {
  // O cartão aquece no toque: entre encostar o dedo e a tela trocar, ele já respondeu.
  let quente: Element | null = null;
  const esfriar = () => { quente?.classList.remove("aquecendo"); quente = null; };
  window.addEventListener("pointerdown", (e) => {
    if (e.pointerType !== "touch") return;
    const alvo = (e.target as Element).closest(AQUECE);
    if (alvo && !(e.target as Element).closest("input, textarea, .circulo")) { quente = alvo; alvo.classList.add("aquecendo"); }
  }, { passive: true });
  for (const ev of ["pointerup", "pointercancel"]) window.addEventListener(ev, esfriar, { passive: true });
  window.addEventListener("scroll", esfriar, { passive: true, capture: true });

  // O ícone do estado vazio segue o ponteiro de longe (−1..1 em --px/--py).
  if (matchMedia("(pointer: fine)").matches && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
    let quadro = 0;
    window.addEventListener("pointermove", (e) => {
      if (quadro) return;
      quadro = requestAnimationFrame(() => {
        quadro = 0;
        const r = document.documentElement.style;
        r.setProperty("--px", ((e.clientX / innerWidth) * 2 - 1).toFixed(3));
        r.setProperty("--py", ((e.clientY / innerHeight) * 2 - 1).toFixed(3));
      });
    }, { passive: true });
  }
}
