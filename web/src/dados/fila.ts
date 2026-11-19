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
  for (const o of filaEmMemoria) gravadas.add(o.id);
  definir({ pendencias: filaEmMemoria.length });
}

function idsDaOperacao(op: Operacao, ids = new Set<string>()): Set<string> {
  const re = /(?:tasks\/|lists\/)([^/?"]+)/g;
  if (op.provisorio) ids.add(op.provisorio);
  for (const m of (op.url ?? "").matchAll(re)) ids.add(decodeURIComponent(m[1]));
  const l = op.linha ?? op.chave;
  if (l) for (const k of ["id", "tarefa_id"]) if (typeof l[k] === "string") ids.add(l[k] as string);
  return ids;
}

/** Quando cada id foi mexido aqui por último (alteração feita ou acabada de subir). */
const tocados = new Map<string, number>();
const tocar = (ids: Iterable<string>) => { const agora = Date.now(); for (const id of ids) tocados.set(id, agora); };

/**
 * Ids que a sincronização não pode sobrescrever: os que têm algo esperando para subir e os
 * mexidos depois que a conferida começou. Sem o segundo grupo, uma resposta do Google pedida
 * antes da alteração chegava depois dela e desfazia na tela por alguns segundos (a tarefa
 * sumia e voltava, a data ia e voltava).
 */
export function idsComPendencia(desde = Infinity): Set<string> {
  const ids = new Set<string>();
  for (const op of filaEmMemoria) idsDaOperacao(op, ids);
  for (const [id, quando] of tocados) {
    if (quando >= desde - 1000) ids.add(id);
    else if (Date.now() - quando > 120_000) tocados.delete(id);
  }
  return ids;
}

export async function enfileirar(op: Omit<Operacao, "id" | "criadaEm" | "tentativas">) {
  if (ler().modo !== "conta") return;
  const completa: Operacao = { ...op, id: uuid(), criadaEm: Date.now() + filaEmMemoria.length / 1000, tentativas: 0 };
  filaEmMemoria.push(completa);
  tocar(idsDaOperacao(completa));
  definir({ pendencias: filaEmMemoria.length });
  try {
    await gravarOperacao(completa);
    gravadas.add(completa.id);
    canal?.postMessage("nova");
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

/** Junta o que outra janela (janela e popover do Mac, outra aba) gravou ou já subiu. */
async function recarregarFila() {
  const doDisco = await lerFila();
  const ids = new Set(doDisco.map((o) => o.id));
  const soEmMemoria = filaEmMemoria.filter((o) => !ids.has(o.id) && !gravadas.has(o.id));
  filaEmMemoria = [...doDisco, ...soEmMemoria].sort((a, b) => a.criadaEm - b.criadaEm);
  definir({ pendencias: filaEmMemoria.length });
}
/** Ids que chegaram ao disco: se somem de lá, outra janela já os enviou. */
const gravadas = new Set<string>();
const canal = typeof BroadcastChannel !== "undefined" ? new BroadcastChannel("tasker-fila") : null;
// Outra janela avisa: operação nova na fila, ou um id provisório que ela trocou pelo do Google.
// Sem o segundo aviso, a tarefa criada no popover e subida pela janela (ou o contrário) ficava
// duplicada: a de verdade e uma cópia apagada que nunca mais subia.
canal?.addEventListener("message", (ev: MessageEvent) => {
  const m = ev.data as string | { troca: [string, string] };
  if (typeof m === "object" && m?.troca) {
    tocar(m.troca);
    aoTrocarId(m.troca[0], m.troca[1]);
    return;
  }
  void processarFila();
});

/** Relê a fila do disco (o que outra janela fez) e diz quais ids ela ainda segura. */
export async function idsNaFila(): Promise<Set<string>> {
  // Só lê: trocar a fila em memória aqui, no meio de uma subida, faria uma operação já enviada voltar.
  const ids = new Set<string>();
  for (const op of [...filaEmMemoria, ...(await lerFila())]) idsDaOperacao(op, ids);
  return ids;
}

export async function processarFila(): Promise<void> {
  if (processando || ler().modo !== "conta" || !navigator.onLine) return;
  processando = true;
  // Uma janela por vez sobe a fila: duas ao mesmo tempo duplicariam criações.
  const travas = (navigator as Navigator & { locks?: LockManager }).locks;
  try {
    if (travas) await travas.request("tasker-fila", () => subirFila());
    else await subirFila();
  } finally {
    processando = false;
  }
}

async function subirFila(): Promise<void> {
  await recarregarFila();
  while (filaEmMemoria.length) {
    const op = filaEmMemoria[0];
    try {
      await executar(op);
      tocar(idsDaOperacao(op));
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
}

async function executar(op: Operacao) {
  switch (op.tipo) {
    case "google": {
      // Repetir não pode duplicar (operação §5.1): uma criação que já foi tentada pode ter chegado
      // ao Google sem a resposta voltar. Antes de criar de novo, procura a tarefa recém-criada.
      const criaTarefa = op.metodo === "POST" && !!op.provisorio && /\/lists\/[^/]+\/tasks/.test(op.url ?? "");
      if (criaTarefa && (op.tentativas > 0 || op.jaEnviada)) {
        const ja = await jaCriada(op);
        if (ja) {
          if (op.provisorio && ja !== op.provisorio) await trocarId(op.provisorio, ja);
          return;
        }
      }
      // Marca antes de mandar: se a página cair no meio (Mac dormindo, recarga), a próxima
      // tentativa procura antes de criar de novo.
      if (criaTarefa && !op.jaEnviada) {
        op.jaEnviada = true;
        await gravarOperacao(op).catch(() => {});
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
  tocar([provisorio, definitivo]);
  aoTrocarId(provisorio, definitivo);
  canal?.postMessage({ troca: [provisorio, definitivo] });
}

export async function descartarFila() {
  filaEmMemoria = [];
  definir({ pendencias: 0 });
}

/** Uma tarefa com o mesmo título criada a partir de um pouco antes da primeira tentativa. */
async function jaCriada(op: Operacao): Promise<string | null> {
  // Sem try: se não der para conferir, o erro sobe e a fila tenta depois (criar de novo às cegas duplicaria).
  const corpo = (op.corpo ?? {}) as { title?: string; notes?: string };
  const base = (op.url ?? "").split("?")[0];
  const desde = new Date(op.criadaEm - 60_000).toISOString();
  const r = await google<{ items?: { id: string; title?: string; notes?: string }[] }>("GET", `${base}?showCompleted=true&showHidden=true&updatedMin=${encodeURIComponent(desde)}&maxResults=100`);
  const achada = (r?.items ?? []).find((t) => t.title === corpo.title && (t.notes ?? "") === (corpo.notes ?? ""));
  return achada?.id ?? null;
}
