import { definir, ler } from "./armazem";
import { avisar } from "./avisos";
import { apagarOperacao, gravarOperacao, lerArquivo, lerFila, type Operacao } from "./espelho";
import { ErroDeRede, ErroDoPedido, ErroReconectar, comPrazo, ehErroDeRede, google, supabase } from "./nuvem";
import { uuid } from "./util";

// A fila: o que foi feito no aparelho e ainda não subiu (desempenho §8.3).
// Uma operação por vez, em ordem, parando na primeira falha de rede. Só falha de rede fica;
// erro do pedido sai da fila com um aviso. Cinco falhas de rede seguidas: desiste e avisa (§7.4).

let processando = false;
let proximaVolta: ReturnType<typeof setTimeout> | null = null;
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
          // Falha de rede nunca descarta: é o offline chegando atrasado. Espera crescente
          // (20 s, 40 s, 80 s… até 5 min), mesmo com o aparelho dizendo "online" (operação §5.1).
          op.tentativas += 1;
          await gravarOperacao(op).catch(() => {});
          const espera = Math.min(300_000, 20_000 * 2 ** Math.min(op.tentativas - 1, 4)) + Math.random() * 1500;
          if (proximaVolta) clearTimeout(proximaVolta);
          proximaVolta = setTimeout(() => { proximaVolta = null; void processarFila(); }, espera);
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
      // Repetir não pode duplicar (operação §5.1): uma criação que já foi tentada pode ter chegado
      // ao Google sem a resposta voltar. Antes de criar de novo, procura a tarefa recém-criada.
      if (op.metodo === "POST" && op.provisorio && op.tentativas > 0) {
        const ja = await jaCriada(op);
        if (ja) {
          if (ja !== op.provisorio) await trocarId(op.provisorio, ja);
          return;
        }
      }
      const resposta = await google<{ id?: string }>(op.metodo ?? "GET", op.url ?? "", op.corpo);
      if (op.provisorio && resposta?.id && resposta.id !== op.provisorio) await trocarId(op.provisorio, resposta.id);
      return;
    }
    case "tabela": {
      const sb = await supabase();
      const q = sb.from(op.tabela ?? "");
      // Toda escrita tem prazo e confere o erro (operação §5.1).
      const { error } = await comPrazo(op.acao === "delete" ? q.delete().match(op.chave ?? {}) : q.upsert(op.linha ?? {}), 15_000);
      if (error) throw erroSupabase(error);
      return;
    }
    case "arquivo": {
      const blob = await lerArquivo(op.arquivoId ?? "");
      if (!blob) return; // o arquivo saiu do aparelho antes de subir: nada a fazer
      const sb = await supabase();
      // O prazo conta o tamanho: ~40 KB/s de envio num 4G ruim, mais uma folga.
      const { error } = await comPrazo(sb.storage
        .from(op.bucket ?? "")
        .upload(op.caminho ?? "", blob, { upsert: true, contentType: op.tipoArquivo ?? blob.type }), 15_000 + (blob.size / 40_000) * 1000);
      if (error) throw erroSupabase(error);
      return;
    }
    case "apagar_arquivo": {
      const sb = await supabase();
      const { error } = await comPrazo(sb.storage.from(op.bucket ?? "").remove([op.caminho ?? ""]), 15_000);
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

/** Uma tarefa com o mesmo título criada a partir de um pouco antes da primeira tentativa. */
async function jaCriada(op: Operacao): Promise<string | null> {
  const corpo = (op.corpo ?? {}) as { title?: string; notes?: string };
  const base = (op.url ?? "").split("?")[0];
  const desde = new Date(op.criadaEm - 60_000).toISOString();
  try {
    const r = await google<{ items?: { id: string; title?: string; notes?: string }[] }>("GET", `${base}?showCompleted=true&showHidden=true&updatedMin=${encodeURIComponent(desde)}&maxResults=100`);
    const achada = (r?.items ?? []).find((t) => t.title === corpo.title && (t.notes ?? "") === (corpo.notes ?? ""));
    return achada?.id ?? null;
  } catch {
    return null;
  }
}
