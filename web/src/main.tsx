import { mudarPrefs } from "./dados/acoes";
import { createRoot } from "react-dom/client";
import { ligarEfeitos } from "./ui/efeitos";
import { ligarFavicon } from "./ui/favicon";
import "./estilo/base.css";
import "./estilo/sistema.css";
import { iniciar, concluirLoginDoMac, ponteMac, recarregarDoEspelho, puxar, vindoDeFora } from "./dados/sync";
import { assinar, ler } from "./dados/armazem";
import { contagemHoje } from "./dados/consultas";
import { App } from "./ui/App";
import { selecionar } from "./ui/rota";
import { importarDoMac } from "./dados/importar";
import { aplicarTema } from "./ui/hoje";

aplicarTema();
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", aplicarTema);

// Ponte com o app do Mac: o Swift chama estas funções.
Object.assign(window, {
  taskerLoginDoMac: concluirLoginDoMac,
  taskerTema: aplicarTema,
  taskerRecarregar: () => void recarregarDoEspelho().then(() => puxar()),
  taskerNovaTarefa: () => window.dispatchEvent(new Event("tasker:nova")),
  taskerMenuAbriu: () => window.dispatchEvent(new Event("tasker:menuAbriu")),
  taskerSelecionar: (id: string) => selecionar(id),
  taskerImportarDoMac: importarDoMac,
});

// O Mac mostra o número de hoje e o cronômetro na barra de menus: manda só quando muda.
const ponte = ponteMac();
if (ponte) {
  let ultimo = "";
  let dadosAntes: unknown[] = [];
  let aviso: ReturnType<typeof setTimeout> | null = null;
  assinar(() => {
    const e = ler();
    const t = e.cronometro.tarefaId ? e.tarefas[e.cronometro.tarefaId] : null;
    const msg = {
      acao: "estado",
      modo: e.modo,
      hoje: e.modo === "carregando" || e.modo === "entrar" || e.prefs.energiaBaixa ? 0 : contagemHoje(e),
      cronometro: e.cronometro.inicio && t ? { inicio: e.cronometro.inicio, segundosAntes: e.tempos[t.id] ?? 0, titulo: t.titulo } : null,
    };
    const s = JSON.stringify(msg);
    if (s !== ultimo) {
      ultimo = s;
      ponte.postMessage(msg);
    }
    // Dados mudaram aqui (não vindos de outra janela): depois de gravar, as outras releem.
    const dados = [e.tarefas, e.listas, e.despejo, e.notas, e.etiquetas, e.etiquetasDaTarefa, e.tempos, e.cronometro, e.anexos, e.prefs];
    const mudou = dados.some((d, i) => d !== dadosAntes[i]);
    dadosAntes = dados;
    if (!mudou || vindoDeFora || e.modo === "carregando") return;
    if (aviso) clearTimeout(aviso);
    aviso = setTimeout(() => ponte.postMessage({ acao: "mudou" }), 700);
  });
}

ligarFavicon();
ligarEfeitos();
// O tema viaja com a conta: quando as preferências chegam de outro aparelho, a cópia local acompanha.
// (Uma vez: o tema escolhido antes disso existir sobe para a conta, em vez de ser trocado pelo padrão.)
let temaConferido = false;
assinar(() => {
  if (ler().modo === "carregando" || ler().modo === "entrar") return;
  if (!temaConferido) {
    temaConferido = true;
    try {
      const local = localStorage.getItem("tasker.tema");
      if (local && local !== "sistema" && ler().prefs.tema === "sistema" && !localStorage.getItem("tasker.temaNaConta")) mudarPrefs(() => ({ tema: local as "claro" | "escuro" }));
      localStorage.setItem("tasker.temaNaConta", "1");
    } catch { /* nada */ }
    return;
  }
  const t = ler().prefs.tema;
  try {
    if (t && localStorage.getItem("tasker.tema") !== t) { localStorage.setItem("tasker.tema", t); aplicarTema(); }
  } catch { /* nada */ }
});
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
