import { concluir } from "../dados/acoes";
import { ler } from "../dados/armazem";
import { folhas } from "./folhas";
import { abrirNota, selecionar } from "./rota";

// Gestos (design system §11): só no toque, desligados sob movimento reduzido. O dedo anda três,
// a tela anda um — um deslize distraído não dispara a ação.

const reduzido = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

export function ligarGestos() {
  let g: null | {
    tipo: "folha" | "voltar" | "cartao"; el: HTMLElement; x: number; y: number; decidido: boolean; valeu: boolean; extra?: HTMLElement | null; id?: string;
  } = null;

  window.addEventListener("touchstart", (e) => {
    if (reduzido() || e.touches.length !== 1) return;
    const t = e.touches[0];
    const alvo = e.target as HTMLElement;
    // Fechar folha arrastando para baixo: pela alça/cabeçalho, ou pelo corpo com a rolagem no topo.
    const folha = alvo.closest<HTMLElement>(".folha");
    if (folha && matchMedia("(max-width: 760px)").matches) {
      const corpo = folha.querySelector<HTMLElement>(".folha-corpo");
      if (alvo.closest(".alca, .folha-cabecalho") || (corpo && corpo.scrollTop <= 0 && !alvo.closest("input, textarea"))) {
        g = { tipo: "folha", el: folha, x: t.clientX, y: t.clientY, decidido: false, valeu: false, extra: document.querySelector<HTMLElement>(".veu-modal") };
      }
      return;
    }
    // Voltar pela borda esquerda: detalhe da tarefa ou nota aberta, no celular.
    if (t.clientX < 24 && matchMedia("(max-width: 760px)").matches) {
      const tela = document.querySelector<HTMLElement>(".inspetor, .tela-notas[data-editando] .editor-nota");
      if (tela) { g = { tipo: "voltar", el: tela, x: t.clientX, y: t.clientY, decidido: false, valeu: false }; return; }
    }
    // Deslizar uma tarefa para a direita conclui.
    const linha = alvo.closest<HTMLElement>(".linha-tarefa");
    if (linha && !alvo.closest(".circulo, button, input, textarea") && linha.dataset.tarefa) {
      g = { tipo: "cartao", el: linha, x: t.clientX, y: t.clientY, decidido: false, valeu: false, id: linha.dataset.tarefa };
    }
  }, { passive: true });

  window.addEventListener("touchmove", (e) => {
    if (!g) return;
    const t = e.touches[0];
    const dx = t.clientX - g.x, dy = t.clientY - g.y;
    if (!g.decidido) {
      if (Math.hypot(dx, dy) < 12) return;
      const vertical = Math.abs(dy) > Math.abs(dx);
      if ((g.tipo === "folha" && (!vertical || dy < 0)) || (g.tipo !== "folha" && (vertical || dx < 0))) { g = null; return; }
      g.decidido = true;
      g.el.style.transition = "none";
      if (g.tipo === "cartao") g.el.classList.add("deslizando");
    }
    if (g.tipo === "folha") {
      const andou = Math.max(0, dy / 3);
      g.el.style.transform = `translateY(${andou}px)`;
      if (g.extra) g.extra.style.opacity = String(Math.max(0.3, 1 - andou / 200));
      const valeu = dy >= 64 * 3 / 2;
      if (valeu !== g.valeu) { g.valeu = valeu; if (valeu) navigator.vibrate?.(8); }
    } else if (g.tipo === "voltar") {
      const andou = Math.min(dx / 3, g.el.clientWidth * 0.5);
      g.el.style.transform = `translateX(${Math.max(0, andou)}px)`;
      const valeu = dx >= 90;
      if (valeu !== g.valeu) { g.valeu = valeu; if (valeu) navigator.vibrate?.(8); }
    } else {
      const andou = Math.max(0, dx / 3);
      g.el.style.transform = `translateX(${andou}px)`;
      g.el.style.setProperty("--deslize", String(Math.min(1, dx / 72)));
      const valeu = dx >= 72;
      if (valeu !== g.valeu) { g.valeu = valeu; g.el.toggleAttribute("data-deslize-vale", valeu); if (valeu) navigator.vibrate?.(8); }
    }
  }, { passive: true });

  const soltar = () => {
    if (!g) return;
    const { tipo, el, valeu, extra, id } = g;
    g = null;
    el.style.transition = "transform 260ms var(--curva)";
    if (tipo === "folha") {
      if (extra) extra.style.opacity = "";
      if (valeu) { el.style.transform = ""; el.style.transition = ""; folhas.fechar(); return; }
      el.style.transform = "";
    } else if (tipo === "voltar") {
      if (valeu) {
        el.style.transform = "translateX(100%)";
        setTimeout(() => { el.style.transform = ""; el.style.transition = ""; if (el.classList.contains("inspetor")) selecionar(null); else abrirNota(null); }, 200);
        return;
      }
      el.style.transform = "";
    } else {
      el.classList.remove("deslizando");
      el.removeAttribute("data-deslize-vale");
      el.style.transform = "";
      el.style.removeProperty("--deslize");
      if (valeu && id) {
        const t = ler().tarefas[id];
        if (t) concluir(id, !t.concluida);
      }
    }
    setTimeout(() => { el.style.transition = ""; }, 280);
  };
  window.addEventListener("touchend", soltar, { passive: true });
  window.addEventListener("touchcancel", soltar, { passive: true });
}
