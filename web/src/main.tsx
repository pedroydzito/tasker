import { createRoot } from "react-dom/client";
import { ligarFavicon } from "./ui/favicon";
import "./estilo/base.css";
import { iniciar, concluirLoginDoMac, ponteMac, recarregarDoEspelho, puxar } from "./dados/sync";
import { assinar, ler } from "./dados/armazem";
import { contagemHoje } from "./dados/consultas";
import { App } from "./ui/App";
import { aplicarTema } from "./ui/telas";

aplicarTema();
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", aplicarTema);

// Ponte com o app do Mac: o Swift chama estas funções.
Object.assign(window, {
  taskerLoginDoMac: concluirLoginDoMac,
  taskerTema: aplicarTema,
  taskerRecarregar: () => void recarregarDoEspelho().then(() => puxar()),
  taskerNovaTarefa: () => window.dispatchEvent(new Event("tasker:nova")),
});

// O Mac mostra o número de hoje e o cronômetro na barra de menus: manda só quando muda.
const ponte = ponteMac();
if (ponte) {
  let ultimo = "";
  assinar(() => {
    const e = ler();
    if (e.modo === "carregando") return;
    const t = e.cronometro.tarefaId ? e.tarefas[e.cronometro.tarefaId] : null;
    const msg = {
      acao: "estado",
      hoje: e.prefs.energiaBaixa ? 0 : contagemHoje(e),
      cronometro: e.cronometro.inicio && t ? { inicio: e.cronometro.inicio, segundosAntes: e.tempos[t.id] ?? 0, titulo: t.titulo } : null,
    };
    const s = JSON.stringify(msg);
    if (s !== ultimo) {
      ultimo = s;
      ponte.postMessage(msg);
    }
  });
}

ligarFavicon();
void iniciar();
createRoot(document.getElementById("raiz")!).render(<App />);

// Service worker: registra quando a página está ociosa (não disputa a abertura) e fora do app do Mac
// (lá o bundle já é local). Versão nova espera e só assume quando a aba volta a ficar visível.
const noMac = !!(window as { webkit?: { messageHandlers?: { tasker?: unknown } } }).webkit?.messageHandlers?.tasker;
if ("serviceWorker" in navigator && location.protocol === "https:" && !noMac) {
  const registrar = () =>
    navigator.serviceWorker.register("./sw.js").then((reg) => {
      const aplicar = () => reg.waiting?.postMessage("SKIP_WAITING");
      document.addEventListener("visibilitychange", () => document.visibilityState === "hidden" && aplicar());
    });
  ("requestIdleCallback" in window ? requestIdleCallback : setTimeout)(() => void registrar());
  let recarregou = false;
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    // Troca "na porta": só recarrega se a página estiver escondida; senão a próxima abertura pega.
    if (!recarregou && document.visibilityState === "hidden") {
      recarregou = true;
      location.reload();
    }
  });
}
