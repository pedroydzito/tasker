import type { SupabaseClient } from "@supabase/supabase-js";

// Conexão com o Supabase. O pacote só é baixado quando há conta (modo sem conta nunca o carrega).

export const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL as string | undefined;
export const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_KEY as string | undefined;

/** Variáveis faltando: diz o que se perde, sem derrubar o app (operação §2.1). */
export function conferirAmbiente(): string[] {
  const faltam: string[] = [];
  if (!SUPABASE_URL) faltam.push("VITE_SUPABASE_URL (essencial): sem ela não há login nem sincronização — só o modo sem conta funciona.");
  if (!SUPABASE_KEY) faltam.push("VITE_SUPABASE_KEY (essencial): sem ela não há login nem sincronização — só o modo sem conta funciona.");
  for (const f of faltam) console.warn("[Tasker]", f);
  return faltam;
}

let cliente: Promise<SupabaseClient> | null = null;

export function supabase(): Promise<SupabaseClient> {
  cliente ??= import("@supabase/supabase-js").then(({ createClient }) =>
    createClient(SUPABASE_URL ?? "", SUPABASE_KEY ?? "", {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: "pkce" },
    }),
  );
  return cliente;
}

/** Sem rede (vai para a fila e tenta de novo). */
export class ErroDeRede extends Error {}
/** Pedido recusado por motivo do cliente (não adianta repetir). */
export class ErroDoPedido extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}
/** O Google precisa ser conectado de novo (acesso revogado ou nunca salvo). */
export class ErroReconectar extends Error {}

export function ehErroDeRede(e: unknown): boolean {
  return e instanceof ErroDeRede || (e instanceof TypeError && /fetch|network|load failed/i.test(e.message));
}

/** Chama a API do Google pela função do servidor (que guarda e renova o token). */
export async function google<T = unknown>(metodo: string, url: string, corpo?: unknown): Promise<T> {
  const sb = await supabase();
  let resposta: Response;
  try {
    const { data } = await sb.auth.getSession();
    const token = data.session?.access_token;
    // Todo pedido que a pessoa espera tem prazo (operação §5.1): leitura 12 s, escrita 25 s.
    const controle = new AbortController();
    const prazo = setTimeout(() => controle.abort(), metodo === "GET" ? 12_000 : 25_000);
    resposta = await fetch(`${SUPABASE_URL}/functions/v1/google`, {
      signal: controle.signal,
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: SUPABASE_KEY ?? "", Authorization: `Bearer ${token ?? SUPABASE_KEY}` },
      body: JSON.stringify({ metodo, url, corpo }),
    }).finally(() => clearTimeout(prazo));
  } catch (e) {
    throw new ErroDeRede(String(e));
  }
  if (resposta.status === 412) throw new ErroReconectar("reconectar");
  if (resposta.status >= 500) throw new ErroDeRede(`servidor ${resposta.status}`);
  const json = (await resposta.json().catch(() => null)) as { status?: number; dados?: unknown; erro?: string } | null;
  if (!resposta.ok || !json) throw new ErroDoPedido(json?.erro ?? `erro ${resposta.status}`, resposta.status);
  const status = json.status ?? 0;
  if (status === 429 || status >= 500) throw new ErroDeRede(`google ${status}`);
  if (status === 404 && metodo === "DELETE") return null as T; // já não existe: era o que queríamos
  if (status >= 400) {
    const msg = (json.dados as { error?: { message?: string } } | null)?.error?.message ?? `Google ${status}`;
    throw new ErroDoPedido(msg, status);
  }
  return json.dados as T;
}

/** Ações da função do servidor que não são repasse ao Google. */
export async function funcaoGoogle(acao: "salvar_token" | "status" | "desconectar", extra: Record<string, unknown> = {}) {
  const sb = await supabase();
  const { data, error } = await sb.functions.invoke("google", { body: { acao, ...extra } });
  if (error) throw error;
  return data as { ok?: boolean; conectado?: boolean };
}

/** Promessa com prazo: estourou, vira falha de rede (e quem chamou cai no que há no aparelho). */
export function comPrazo<T>(p: PromiseLike<T>, ms: number): Promise<T> {
  return Promise.race([
    Promise.resolve(p),
    new Promise<T>((_, rej) => setTimeout(() => rej(new ErroDeRede(`prazo de ${ms} ms`)), ms)),
  ]);
}
