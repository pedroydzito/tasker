import { definir, ler } from "./armazem";
import { avisar } from "./avisos";
import { apagarOperacao, gravarOperacao, lerArquivo, lerFila, type Operacao } from "./espelho";
import { ErroDeRede, ErroDoPedido, ErroReconectar, ehErroDeRede, google, supabase } from "./nuvem";
import { uuid } from "./util";

// A fila: o que foi feito no aparelho e ainda não subiu (desempenho §8.3).
// Uma operação por vez, em ordem, parando na primeira falha de rede. Só falha de rede fica;
// erro do pedido sai da fila com um aviso. Cinco falhas de rede seguidas: desiste e avisa (§7.4).

const MAX_TENTATIVAS = 5;
let processando = false;
let filaEmMemoria: Operacao[] = [];
/** Quem quer saber quando um id provisório vira definitivo (o armazém troca nas tarefas). */
let aoTrocarId: (provisorio: string, definitivo: string) => void = () => {};

export function quandoTrocarId(fn: typeof aoTrocarId) {
  aoTrocarId = fn;
}

export async function carregarFila() {
  filaEmMemoria = await lerFila();
  definir({ pendencias: filaEmMemoria.length });
}

/** Ids que têm algo esperando para subir: a sincronização não os sobrescreve. */
export function idsComPendencia(): Set<string> {
  const ids = new Set<string>();
  const re = /(?:tasks\/|lists\/)([^/?"]+)/g;
  for (const op of filaEmMemoria) {
    if (op.provisorio) ids.add(op.provisorio);
    for (const m of (op.url ?? "").matchAll(re)) ids.add(decodeURIComponent(m[1]));
    const l = op.linha ?? op.chave;
    if (l) for (const k of ["id", "tarefa_id"]) if (typeof l[k] === "string") ids.add(l[k] as string);
  }
  return ids;
}

export async function enfileirar(op: Omit<Operacao, "id" | "criadaEm" | "tentativas">) {
  if (ler().modo !== "conta") return;
  const completa: Operacao = { ...op, id: uuid(), criadaEm: Date.now() + filaEmMemoria.length / 1000, tentativas: 0 };
  filaEmMemoria.push(completa);
  definir({ pendencias: filaEmMemoria.length });
  try {
    await gravarOperacao(completa);
  } catch {
    /* sem IndexedDB: a operação segue só em memória até subir */
  }
  void processarFila();
}

export function esperandoFila(): Promise<void> {
  return new Promise((ok) => {
    const olhar = () => (!processando && filaEmMemoria.length === 0 ? ok() : setTimeout(olhar, 50));
    olhar();
  });
}

export async function processarFila(): Promise<void> {
  if (processando || ler().modo !== "conta" || !navigator.onLine) return;
  processando = true;
  try {
    while (filaEmMemoria.length) {
      const op = filaEmMemoria[0];
      try {
        await executar(op);
        filaEmMemoria.shift();
        await apagarOperacao(op.id).catch(() => {});
        definir({ pendencias: filaEmMemoria.length });
      } catch (e) {
        if (e instanceof ErroReconectar) {
          definir({ googlePendente: true });
          break;
        }
        if (ehErroDeRede(e)) {
          op.tentativas += 1;
          if (op.tentativas >= MAX_TENTATIVAS) {
            filaEmMemoria.shift();
            await apagarOperacao(op.id).catch(() => {});
            definir({ pendencias: filaEmMemoria.length });
            avisar("Uma alteração não conseguiu subir depois de várias tentativas.", { erro: true });
            continue;
          }
          await gravarOperacao(op).catch(() => {});
          // Espera crescente com jitter antes da próxima volta (§7.4).
          setTimeout(() => void processarFila(), op.tentativas * 2000 + Math.random() * 800);
          break;
        }
        // Erro do pedido: repetir não adianta. Sai da fila e avisa.
        filaEmMemoria.shift();
        await apagarOperacao(op.id).catch(() => {});
        definir({ pendencias: filaEmMemoria.length });
        const msg = e instanceof Error ? e.message : String(e);
        avisar(`Não foi possível salvar uma alteração: ${msg}`, { erro: true });
      }
    }
  } finally {
    processando = false;
  }
}

async function executar(op: Operacao) {
  switch (op.tipo) {
    case "google": {
      const resposta = await google<{ id?: string }>(op.metodo ?? "GET", op.url ?? "", op.corpo);
      if (op.provisorio && resposta?.id && resposta.id !== op.provisorio) await trocarId(op.provisorio, resposta.id);
      return;
    }
    case "tabela": {
      const sb = await supabase();
      const q = sb.from(op.tabela ?? "");
      const { error } =
        op.acao === "delete" ? await q.delete().match(op.chave ?? {}) : await q.upsert(op.linha ?? {});
      if (error) throw erroSupabase(error);
      return;
    }
    case "arquivo": {
      const blob = await lerArquivo(op.arquivoId ?? "");
      if (!blob) return; // o arquivo saiu do aparelho antes de subir: nada a fazer
      const sb = await supabase();
      const { error } = await sb.storage
        .from(op.bucket ?? "")
        .upload(op.caminho ?? "", blob, { upsert: true, contentType: op.tipoArquivo ?? blob.type });
      if (error) throw erroSupabase(error);
      return;
    }
    case "apagar_arquivo": {
      const sb = await supabase();
      const { error } = await sb.storage.from(op.bucket ?? "").remove([op.caminho ?? ""]);
      if (error) throw erroSupabase(error);
      return;
    }
  }
}

function erroSupabase(error: { message?: string; code?: string; status?: number; statusCode?: string }): Error {
  const msg = error.message ?? "erro";
  if (/fetch|network|Load failed|timeout/i.test(msg) && !error.code) return new ErroDeRede(msg);
  const status = Number(error.status ?? error.statusCode ?? 400);
  if (status >= 500 || status === 0) return new ErroDeRede(msg);
  return new ErroDoPedido(msg, status);
}

/** O Google deu o id definitivo: troca nas operações que ainda esperam e avisa o armazém. */
async function trocarId(provisorio: string, definitivo: string) {
  for (const op of filaEmMemoria.slice(1)) {
    const texto = JSON.stringify(op);
    if (!texto.includes(provisorio)) continue;
    const nova = JSON.parse(texto.split(provisorio).join(definitivo)) as Operacao;
    Object.assign(op, nova);
    await gravarOperacao(op).catch(() => {});
  }
  aoTrocarId(provisorio, definitivo);
}

export async function descartarFila() {
  filaEmMemoria = [];
  definir({ pendencias: 0 });
}
