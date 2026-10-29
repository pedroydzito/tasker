import { openDB, type IDBPDatabase } from "idb";

// Banco local (IndexedDB): o espelho de tudo o que a tela mostra, a fila do que ainda não subiu
// e os arquivos que esperam a rede. Uma conexão só, compartilhada pelo módulo (desempenho §8.2).

export interface Operacao {
  id: string;
  /** "google": pedido à API do Google; "tabela": linha no Supabase; "arquivo": subir um arquivo. */
  tipo: "google" | "tabela" | "arquivo" | "apagar_arquivo";
  criadaEm: number;
  tentativas: number;
  // google
  metodo?: string;
  url?: string;
  corpo?: unknown;
  /** Id provisório que a resposta troca pelo definitivo (criar tarefa/lista). */
  provisorio?: string;
  // tabela
  tabela?: string;
  acao?: "upsert" | "delete";
  linha?: Record<string, unknown>;
  chave?: Record<string, unknown>;
  // arquivo
  bucket?: string;
  caminho?: string;
  arquivoId?: string;
  tipoArquivo?: string;
}

type Banco = IDBPDatabase<unknown>;
let conexao: Promise<Banco> | null = null;

function abrir(): Promise<Banco> {
  conexao ??= openDB("tasker", 1, {
    upgrade(db) {
      db.createObjectStore("estado");
      db.createObjectStore("fila", { keyPath: "id" });
      db.createObjectStore("arquivos");
    },
    // Outra aba com versão nova do banco: fecha esta conexão para não travar a outra.
    blocking() {
      void conexao?.then((db) => db.close());
      conexao = null;
    },
  }).catch((e) => {
    conexao = null; // não guarda a falha: a próxima chamada tenta de novo
    throw e;
  });
  return conexao;
}

export async function lerEstado<T>(chave: string): Promise<T | undefined> {
  try {
    return (await (await abrir()).get("estado", chave)) as T | undefined;
  } catch {
    return undefined;
  }
}

export async function gravarEstado(chave: string, valor: unknown): Promise<void> {
  try {
    await (await abrir()).put("estado", valor, chave);
  } catch {
    /* sem espaço ou aba anônima: o app segue só em memória */
  }
}

export async function apagarEstado(chave: string): Promise<void> {
  try {
    await (await abrir()).delete("estado", chave);
  } catch {
    /* nada a fazer */
  }
}

export async function lerFila(): Promise<Operacao[]> {
  try {
    const todas = (await (await abrir()).getAll("fila")) as Operacao[];
    return todas.sort((a, b) => a.criadaEm - b.criadaEm);
  } catch {
    return [];
  }
}

export async function gravarOperacao(op: Operacao): Promise<void> {
  await (await abrir()).put("fila", op);
}

export async function apagarOperacao(id: string): Promise<void> {
  await (await abrir()).delete("fila", id);
}

export async function limparFila(): Promise<void> {
  try {
    await (await abrir()).clear("fila");
  } catch {
    /* nada */
  }
}

export async function guardarArquivo(id: string, blob: Blob): Promise<void> {
  await (await abrir()).put("arquivos", blob, id);
}

export async function lerArquivo(id: string): Promise<Blob | undefined> {
  try {
    return (await (await abrir()).get("arquivos", id)) as Blob | undefined;
  } catch {
    return undefined;
  }
}

export async function apagarArquivo(id: string): Promise<void> {
  try {
    await (await abrir()).delete("arquivos", id);
  } catch {
    /* nada */
  }
}

/** Logout: nada da conta anterior fica no aparelho (desempenho §4.3). */
export async function limparTudo(): Promise<void> {
  try {
    const db = await abrir();
    await Promise.all([db.clear("estado"), db.clear("fila"), db.clear("arquivos")]);
  } catch {
    /* nada */
  }
}
