import { assinar, ler } from "../dados/armazem";
import { contagemHoje } from "../dados/consultas";

// Favicon como o ícone da barra de menus do Mac: o ícone do app e, no cantinho,
// o número de tarefas de hoje (sem energia, nenhum número cobra).

function desenhar(n: number): string {
  const t = 64;
  const c = document.createElement("canvas");
  c.width = c.height = t;
  const g = c.getContext("2d")!;
  g.fillStyle = "#0097FF";
  g.beginPath();
  g.roundRect(0, 0, t, t, t * 0.28);
  g.fill();
  g.strokeStyle = "#fff";
  g.lineWidth = 7;
  g.lineCap = g.lineJoin = "round";
  g.beginPath();
  g.moveTo(18.5, 33);
  g.lineTo(27.5, 42);
  g.lineTo(45.5, 23);
  g.stroke();
  if (n > 0) {
    const texto = n > 99 ? "99+" : String(n);
    const r = 15;
    const w = Math.max(r * 2, 14 + texto.length * 13);
    const x = t - w, y = t - r * 2;
    // Anel na cor do fundo da aba separa o selo do ícone, como no Mac.
    g.fillStyle = "#fff";
    g.beginPath();
    g.roundRect(x - 3, y - 3, w + 6, r * 2 + 6, r + 3);
    g.fill();
    g.fillStyle = "#E5484D";
    g.beginPath();
    g.roundRect(x, y, w, r * 2, r);
    g.fill();
    g.fillStyle = "#fff";
    g.font = "700 22px Geist, system-ui, sans-serif";
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillText(texto, x + w / 2, y + r + 1);
  }
  return c.toDataURL("image/png");
}

export function ligarFavicon() {
  let ultimo = -1;
  const atualizar = () => {
    const e = ler();
    const n = e.modo === "carregando" || e.modo === "entrar" || e.prefs.energiaBaixa ? 0 : contagemHoje(e);
    if (n === ultimo) return;
    ultimo = n;
    let link = document.querySelector<HTMLLinkElement>("link[rel='icon']");
    if (!link) {
      link = document.createElement("link");
      link.rel = "icon";
      document.head.appendChild(link);
    }
    link.type = "image/png";
    link.href = desenhar(n);
    document.title = n > 0 ? `(${n}) Tasker` : "Tasker";
  };
  assinar(atualizar);
  atualizar();
  // Virada do dia muda o que é "hoje".
  setInterval(atualizar, 60_000);
}
