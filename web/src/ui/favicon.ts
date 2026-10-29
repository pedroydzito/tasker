import { assinar, ler } from "../dados/armazem";
import { contagemHoje } from "../dados/consultas";

// O favicon é o ícone do app (fixo, em index.html). O número de hoje vai só no título da aba
// (sem energia, nenhum número cobra).
export function ligarFavicon() {
  let ultimo = -1;
  const atualizar = () => {
    const e = ler();
    const n = e.modo === "carregando" || e.modo === "entrar" || e.prefs.energiaBaixa ? 0 : contagemHoje(e);
    if (n === ultimo) return;
    ultimo = n;
    document.title = n > 0 ? `(${n}) Tasker` : "Tasker";
  };
  assinar(atualizar);
  atualizar();
  // Virada do dia muda o que é "hoje".
  setInterval(atualizar, 60_000);
}
