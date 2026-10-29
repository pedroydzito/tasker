import { createRoot } from "react-dom/client";
import "./estilo/base.css";
import { iniciar, concluirLoginDoMac } from "./dados/sync";
import { App } from "./ui/App";
import { aplicarTema } from "./ui/telas";

aplicarTema();
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", aplicarTema);

// Ponte com o app do Mac: o Swift chama estas funções.
Object.assign(window, { taskerLoginDoMac: concluirLoginDoMac, taskerTema: aplicarTema });

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
