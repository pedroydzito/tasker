import type { Session } from "@supabase/supabase-js";
import { definir, espelhoAtual, ESTADO_INICIAL, gravarAgora, ler, substituir, usarEspelho } from "./armazem";
import { confirmarPendente } from "./avisos";
import { lerEstado, limparTudo } from "./espelho";
import { carregarFila, descartarFila, esperandoFila, idsComPendencia, processarFila } from "./fila";
import { conferirAmbiente, ehErroDeRede, ErroReconectar, funcaoGoogle, google, SUPABASE_URL, supabase } from "./nuvem";
import { comPrazo } from "./nuvem";
import { PREFERENCIAS_PADRAO, type Agenda, type Anexo, type Estado, type Evento, type ItemDespejo, type Lista, type Nota, type Tarefa } from "./tipos";
import { diaISO } from "./util";

// Sessão e sincronização. A tela nunca espera a rede: abre com o espelho local e confere atrás.

const T = "https://tasks.googleapis.com/tasks/v1";
const C = "https://www.googleapis.com/calendar/v3";
const ESCOPOS = "https://www.googleapis.com/auth/tasks https://www.googleapis.com/auth/calendar.readonly";
const JANELA_FRESCOR = 20_000; // §4.7
const JANELA_EVENTOS = 90_000;

let ultimaPuxada = 0;
let ultimosEventos = 0;
let puxando: Promise<void> | null = null;
let repetir = false;

const marcas = (): Record<string, string> => {
  try {
    return JSON.parse(localStorage.getItem(`tasker.marcas.${usuarioAtual()}`) ?? "{}");
  } catch {
    return {};
  }
};
const gravarMarcas = (m: Record<string, string>) => {
  try {
    localStorage.setItem(`tasker.marcas.${usuarioAtual()}`, JSON.stringify(m));
  } catch {
    /* nada */
  }
};
const usuarioAtual = () => localStorage.getItem("tasker.usuario") ?? "";

/** Ponte com o app do Mac (WKWebView), quando existe. */
type Ponte = { postMessage: (m: unknown) => void };
export const ponteMac = (): Ponte | null =>
  (window as unknown as { webkit?: { messageHandlers?: { tasker?: Ponte } } }).webkit?.messageHandlers?.tasker ?? null;

// MARK: Abertura

export async function iniciar() {
  conferirAmbiente();
  window.addEventListener("online", () => {
    definir({ online: true });
    void processarFila();
    void puxar(true);
  });
  window.addEventListener("offline", () => definir({ online: false }));
  // Voltar ao app depois de ~15 s fora confere a lista (§4.16).
  let saiuEm = 0;
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
      saiuEm = Date.now();
      gravarAgora();
      return;
    }
    if (saiuEm && Date.now() - saiuEm > 15_000 && navigator.onLine) void puxar(true);
    // A fila não depende só do evento "online": cada volta ao app tenta de novo (operação §5.1).
    void processarFila();
    saiuEm = 0;
  });
  window.addEventListener("pagehide", gravarAgora);
  // Enquanto visível, confere de tempos em tempos (respeitando a janela de frescor).
  setInterval(() => {
    if (document.visibilityState === "visible") void puxar(false);
  }, 30_000);

  const modo = localStorage.getItem("tasker.modo");
  if (modo === "local") return abrirLocal();
  if (!SUPABASE_URL) return definir({ modo: "entrar" });

  // Abre JÁ com o espelho da última conta (offline inclusive); a sessão é conferida atrás.
  const ultimo = usuarioAtual();
  if (ultimo) await abrirEspelho(ultimo);

  const sb = await supabase();
  sb.auth.onAuthStateChange((evento, sessao) => {
    // Fora do callback: chamar o cliente dentro dele trava a renovação do token.
    setTimeout(() => {
      if (sessao) return void entrouNaConta(sessao);
      if (evento === "SIGNED_OUT") return void sairLocalmente();
      if (evento === "INITIAL_SESSION") void confirmarSemSessao();
    }, 0);
  });
}

/** Sem sessão na abertura: pede uma segunda opinião antes de expulsar (§8.4). Offline, ninguém sai. */
async function confirmarSemSessao() {
  if (!navigator.onLine && ler().modo === "conta") return;
  await new Promise((r) => setTimeout(r, 1000));
  const sb = await supabase();
  const { data } = await sb.auth.getSession();
  if (data.session) return entrouNaConta(data.session);
  if (!navigator.onLine && ler().modo === "conta") return;
  substituir({ ...ESTADO_INICIAL, modo: "entrar" });
  usarEspelho(null);
}

async function abrirEspelho(usuario: string) {
  const salvo = await lerEstado<Partial<Estado>>(`conta:${usuario}`);
  usarEspelho(`conta:${usuario}`);
  substituir({ ...ESTADO_INICIAL, ...(salvo ?? {}), prefs: { ...PREFERENCIAS_PADRAO, ...(salvo?.prefs ?? {}) }, modo: "conta", online: navigator.onLine });
  await carregarFila();
}

async function entrouNaConta(sessao: Session) {
  const uid = sessao.user.id;
  if (usuarioAtual() !== uid || ler().modo !== "conta") {
    localStorage.setItem("tasker.usuario", uid);
    localStorage.setItem("tasker.modo", "conta");
    await abrirEspelho(uid);
  }
  const meta = sessao.user.user_metadata ?? {};
  definir({
    email: sessao.user.email ?? null,
    nome: (meta.full_name as string) ?? (meta.name as string) ?? null,
    avatar: (meta.avatar_url as string) ?? (meta.picture as string) ?? null,
  });
  // Logo depois do login, o Supabase entrega o refresh token do Google uma única vez: vai para o servidor.
  if (sessao.provider_refresh_token) {
    try {
      await funcaoGoogle("salvar_token", { refresh_token: sessao.provider_refresh_token, access_token: sessao.provider_token });
      definir({ googlePendente: false });
    } catch {
      /* tenta de novo no próximo login */
    }
  }
  void processarFila();
  void puxar(true);
}

async function abrirLocal() {
  usarEspelho("local");
  const salvo = await lerEstado<Partial<Estado>>("local");
  const base: Estado = { ...ESTADO_INICIAL, ...(salvo ?? {}), prefs: { ...PREFERENCIAS_PADRAO, ...(salvo?.prefs ?? {}) }, modo: "local", online: navigator.onLine };
  if (!base.listas.length) {
    base.listas = [{ id: "local-inbox", titulo: "Minhas tarefas" }];
    base.listaFixa = "local-inbox";
  }
  substituir(base);
  gravarAgora();
}

// MARK: Entrar e sair

export async function entrarComGoogle() {
  const sb = await supabase();
  const ponte = ponteMac();
  const redirectTo = ponte ? "tasker://login" : location.origin + location.pathname;
  const { data, error } = await sb.auth.signInWithOAuth({
    provider: "google",
    options: {
      scopes: ESCOPOS,
      redirectTo,
      // offline + consent: o Google entrega o refresh token (vai para o servidor, nunca fica no aparelho).
      queryParams: { access_type: "offline", prompt: "consent" },
      skipBrowserRedirect: !!ponte,
    },
  });
  if (error) throw error;
  // No app do Mac o login abre no navegador do sistema (o Google não deixa logar dentro de WebView).
  if (ponte && data.url) ponte.postMessage({ acao: "login", url: data.url });
}

/** O app do Mac devolve aqui o endereço de retorno do login. */
export async function concluirLoginDoMac(urlRetorno: string) {
  const codigo = new URL(urlRetorno).searchParams.get("code");
  if (!codigo) return;
  const sb = await supabase();
  await sb.auth.exchangeCodeForSession(codigo);
}

export function usarSemConta() {
  localStorage.setItem("tasker.modo", "local");
  void abrirLocal();
}

export async function sair() {
  confirmarPendente();
  if (ler().modo === "conta") {
    // Dá uma chance de subir o que falta (até 4 s).
    await Promise.race([esperandoFila(), new Promise((r) => setTimeout(r, 4000))]);
    try {
      const sb = await supabase();
      await sb.auth.signOut();
    } catch {
      /* offline: sai localmente mesmo assim */
    }
  }
  await sairLocalmente();
}

async function sairLocalmente() {
  await descartarFila();
  await limparTudo();
  usarEspelho(null);
  for (const k of Object.keys(localStorage)) if (k.startsWith("tasker.") && k !== "tasker.tema") localStorage.removeItem(k);
  substituir({ ...ESTADO_INICIAL, modo: "entrar" });
}

export async function reconectarGoogle() {
  await entrarComGoogle();
}

// MARK: Puxar do servidor

/** Confere o servidor. Dentro da janela de frescor, não pergunta nada (a não ser `forcar`). */
let tentativasDeRede = 0;
let novaTentativa: ReturnType<typeof setTimeout> | null = null;
function agendarNovaTentativa() {
  if (novaTentativa) return;
  const espera = [4_000, 10_000, 25_000, 60_000][Math.min(tentativasDeRede, 3)];
  tentativasDeRede += 1;
  novaTentativa = setTimeout(() => {
    novaTentativa = null;
    // Só com a aba visível e o aparelho online; senão a volta ao app e o "online" cuidam disso.
    if (document.visibilityState === "visible" && navigator.onLine) void puxar(true);
  }, espera);
}

export function puxar(forcar = false): Promise<void> {
  const e = ler();
  if (e.modo !== "conta" || !navigator.onLine) return Promise.resolve();
  if (puxando) {
    if (forcar) repetir = true;
    return puxando;
  }
  if (!forcar && Date.now() - ultimaPuxada < JANELA_FRESCOR) return Promise.resolve();
  puxando = (async () => {
    definir({ sincronizando: true });
    try {
      await processarFila();
      const eventos = forcar || Date.now() - ultimosEventos > JANELA_EVENTOS;
      // Independentes: saem juntas, cada uma com o seu prazo (desempenho §4.20).
      const partes = await Promise.allSettled([comPrazo(puxarGoogle(), 45_000), comPrazo(puxarTabelas(), 15_000), eventos ? comPrazo(puxarEventos(), 20_000) : Promise.resolve()]);
      const [g] = partes;
      ultimaPuxada = Date.now();
      // Rede fraca: o que veio é do aparelho; tenta de novo sozinho em 4, 10, 25 e 60 s (§4.19).
      if (partes.some((r) => r.status === "rejected" && ehErroDeRede(r.reason))) agendarNovaTentativa();
      else tentativasDeRede = 0;
      if (g.status === "rejected" && g.reason instanceof ErroReconectar) definir({ googlePendente: true });
      else if (g.status === "rejected" && !ehErroDeRede(g.reason)) definir({ erro: String((g.reason as Error)?.message ?? g.reason) });
      else definir({ erro: null, ultimaSync: new Date().toISOString(), googlePendente: g.status === "fulfilled" ? false : ler().googlePendente });
    } finally {
      definir({ sincronizando: false });
      puxando = null;
      if (repetir) {
        repetir = false;
        void puxar(true);
      }
    }
  })();
  return puxando;
}

interface GTask { id: string; title?: string; notes?: string; status?: string; due?: string; completed?: string; parent?: string; position?: string; updated?: string; deleted?: boolean; webViewLink?: string }
interface Pagina<T> { items?: T[]; nextPageToken?: string }

async function todasAsPaginas<T>(url: string): Promise<T[]> {
  const itens: T[] = [];
  let token: string | undefined;
  do {
    const sep = url.includes("?") ? "&" : "?";
    const p = await google<Pagina<T>>("GET", token ? `${url}${sep}pageToken=${encodeURIComponent(token)}` : url);
    itens.push(...(p?.items ?? []));
    token = p?.nextPageToken;
  } while (token);
  return itens;
}

function deGoogle(g: GTask, listaId: string): Tarefa {
  return {
    id: g.id, listaId, titulo: g.title ?? "", notas: g.notes ?? "", concluida: g.status === "completed",
    prazo: g.due ? g.due.slice(0, 10) : null, concluidaEm: g.completed ?? null, mae: g.parent ?? null,
    posicao: g.position ?? "", atualizadaEm: g.updated ?? "", link: g.webViewLink ?? null,
  };
}

const mesmaTarefa = (a: Tarefa | undefined, b: Tarefa) =>
  !!a && a.atualizadaEm === b.atualizadaEm && a.titulo === b.titulo && a.notas === b.notas && a.concluida === b.concluida &&
  a.prazo === b.prazo && a.listaId === b.listaId && a.mae === b.mae && a.posicao === b.posicao;

async function puxarGoogle() {
  const remotas = await todasAsPaginas<{ id: string; title?: string }>(`${T}/users/@me/lists?maxResults=100`);
  const e = ler();
  const fixa = remotas[0]?.id ?? null;
  const ordem = new Map(e.prefs.ordemListas.map((id, i) => [id, i]));
  const provisorias = e.listas.filter((l) => l.id.startsWith("tmp-"));
  const listas: Lista[] = [
    ...remotas.map((l, i) => ({ id: l.id, titulo: l.title ?? "Sem título", i }))
      .sort((a, b) => (a.id === fixa ? -1 : b.id === fixa ? 1 : (ordem.get(a.id) ?? 1000 + a.i) - (ordem.get(b.id) ?? 1000 + b.i)))
      .map(({ id, titulo }) => ({ id, titulo })),
    ...provisorias,
  ];
  const mudouListas = listas.length !== e.listas.length || listas.some((l, i) => l.id !== e.listas[i]?.id || l.titulo !== e.listas[i]?.titulo);

  const m = marcas();
  const inicio = new Date().toISOString();
  const respostas = await Promise.all(
    remotas.map(async (l) => {
      const desde = m[l.id];
      const q = new URLSearchParams({ maxResults: "100", showCompleted: "true", showHidden: "true", showDeleted: desde ? "true" : "false" });
      // 2 min de folga para diferença de relógio.
      if (desde) q.set("updatedMin", new Date(new Date(desde).getTime() - 120_000).toISOString());
      const itens = await todasAsPaginas<GTask>(`${T}/lists/${encodeURIComponent(l.id)}/tasks?${q}`);
      return { lista: l.id, completa: !desde, itens };
    }),
  );

  const protegidos = idsComPendencia();
  const atual = ler().tarefas;
  const novas: Record<string, Tarefa> = {};
  const idsListas = new Set(remotas.map((l) => l.id));
  for (const [id, t] of Object.entries(atual)) {
    if (idsListas.has(t.listaId) || t.provisoria || protegidos.has(id) || t.listaId.startsWith("tmp-")) novas[id] = t;
  }
  let mudou = Object.keys(novas).length !== Object.keys(atual).length;
  for (const r of respostas) {
    if (r.completa) {
      const vistos = new Set(r.itens.map((g) => g.id));
      for (const [id, t] of Object.entries(novas)) {
        if (t.listaId === r.lista && !vistos.has(id) && !t.provisoria && !protegidos.has(id)) {
          delete novas[id];
          mudou = true;
        }
      }
    }
    for (const g of r.itens) {
      if (protegidos.has(g.id)) continue;
      if (g.deleted) {
        if (novas[g.id]) { delete novas[g.id]; mudou = true; }
        continue;
      }
      const t = deGoogle(g, r.lista);
      if (!mesmaTarefa(novas[g.id], t)) { novas[g.id] = t; mudou = true; }
    }
    m[r.lista] = inicio;
  }
  gravarMarcas(m);
  definir({ ...(mudouListas ? { listas, listaFixa: fixa } : {}), ...(mudou ? { tarefas: novas } : {}) });
}

interface GCal { id: string; summary?: string; summaryOverride?: string; backgroundColor?: string; primary?: boolean; selected?: boolean; hidden?: boolean }
interface GEv { id: string; status?: string; summary?: string; start?: { date?: string; dateTime?: string }; end?: { date?: string; dateTime?: string }; htmlLink?: string; attendees?: { self?: boolean; responseStatus?: string }[] }

async function puxarEventos() {
  const cals = (await todasAsPaginas<GCal>(`${C}/users/me/calendarList`)).filter((c) => !c.hidden);
  const agendas: Agenda[] = cals
    .map((c) => ({ id: c.id, titulo: c.summaryOverride ?? c.summary ?? c.id, cor: c.backgroundColor ?? "#4285F4", principal: !!c.primary, selecionadaNoGoogle: !!(c.selected || c.primary) }))
    .sort((a, b) => Number(b.principal) - Number(a.principal) || a.titulo.localeCompare(b.titulo));
  const e = ler();
  const visiveis = agendas.filter((a) => e.prefs.agendasVisiveis[a.id] ?? a.selecionadaNoGoogle);
  const hoje = new Date();
  const de = new Date(hoje.getFullYear(), hoje.getMonth() - 1, 1);
  de.setDate(de.getDate() - 7);
  const ate = new Date(hoje.getFullYear(), hoje.getMonth() + 3, 14);
  const listas = await Promise.all(
    visiveis.map(async (a) => {
      const q = new URLSearchParams({ timeMin: de.toISOString(), timeMax: ate.toISOString(), singleEvents: "true", orderBy: "startTime", maxResults: "250" });
      try {
        const itens = await todasAsPaginas<GEv>(`${C}/calendars/${encodeURIComponent(a.id)}/events?${q}`);
        return itens
          .filter((ev) => ev.status !== "cancelled" && ev.attendees?.find((x) => x.self)?.responseStatus !== "declined")
          .map((ev): Evento => {
            const diaTodo = !!ev.start?.date;
            return {
              id: ev.id, agendaId: a.id, titulo: ev.summary ?? "(sem título)", diaTodo, cor: a.cor, link: ev.htmlLink ?? null,
              inicio: diaTodo ? ev.start!.date! : ev.start?.dateTime ?? "", fim: diaTodo ? ev.end?.date ?? ev.start!.date! : ev.end?.dateTime ?? "",
            };
          });
      } catch (err) {
        if (err instanceof ErroReconectar) throw err;
        return null; // não conseguir ler ≠ não ter (§6.5): mantém o que havia desta agenda
      }
    }),
  );
  const atuais = ler().eventos;
  const eventos: Evento[] = [];
  visiveis.forEach((a, i) => eventos.push(...(listas[i] ?? atuais.filter((ev) => ev.agendaId === a.id))));
  eventos.sort((a, b) => Number(b.diaTodo) - Number(a.diaTodo) || (a.inicio < b.inicio ? -1 : 1));
  ultimosEventos = Date.now();
  const igual = JSON.stringify(eventos) === JSON.stringify(atuais) && JSON.stringify(agendas) === JSON.stringify(ler().agendas);
  if (!igual) definir({ eventos, agendas });
}

async function puxarTabelas() {
  const sb = await supabase();
  // Colunas explícitas: nunca select("*") (§12.1).
  const [et, etT, notas, desp, tempos, cron, prefs, anexos] = await Promise.all([
    sb.from("etiquetas").select("id, nome, cor, ordem"),
    sb.from("etiquetas_tarefas").select("tarefa_id, etiqueta_id"),
    sb.from("notas").select("id, titulo, texto, dia, foto, criada_em, editada_em"),
    sb.from("despejo").select("id, texto, estado, foto, criado_em, movido_em"),
    sb.from("tempos").select("tarefa_id, segundos"),
    sb.from("cronometro").select("tarefa_id, inicio").maybeSingle(),
    sb.from("preferencias").select("dados").maybeSingle(),
    sb.from("anexos").select("id, tarefa_id, nome, caminho, tamanho, tipo, criado_em"),
  ]);
  const protegidos = idsComPendencia();
  const e = ler();
  const mudanca: Partial<Estado> = {};
  const set = <K extends keyof Estado>(k: K, v: Estado[K]) => {
    if (JSON.stringify(v) !== JSON.stringify(e[k])) mudanca[k] = v;
  };
  // Cada tabela só substitui se a leitura deu certo ("não consegui ler" não é "não tem", §6.5).
  if (!et.error && et.data) set("etiquetas", [...et.data.filter((x) => !protegidos.has(x.id)), ...e.etiquetas.filter((x) => protegidos.has(x.id))]);
  if (!etT.error && etT.data) {
    const mapa: Record<string, string[]> = {};
    for (const r of etT.data) (mapa[r.tarefa_id] ??= []).push(r.etiqueta_id);
    for (const id of protegidos) if (e.etiquetasDaTarefa[id]) mapa[id] = e.etiquetasDaTarefa[id];
    set("etiquetasDaTarefa", mapa);
  }
  if (!notas.error && notas.data) {
    const remotas: Nota[] = notas.data.map((n) => ({ id: n.id, titulo: n.titulo, texto: n.texto, dia: n.dia, foto: n.foto, criadaEm: n.criada_em, editadaEm: n.editada_em }));
    const locais = new Map(e.notas.map((n) => [n.id, n]));
    const resultado = remotas.map((r) => {
      const l = locais.get(r.id);
      return l && (protegidos.has(r.id) || l.editadaEm > r.editadaEm) ? l : r; // o mais novo vence
    });
    for (const l of e.notas) if (!remotas.some((r) => r.id === l.id) && (protegidos.has(l.id) || Date.now() - new Date(l.editadaEm).getTime() < 5000)) resultado.push(l);
    set("notas", resultado);
  }
  if (!desp.error && desp.data) {
    const remotos: ItemDespejo[] = desp.data.map((d) => ({ id: d.id, texto: d.texto, estado: d.estado, foto: d.foto, criadoEm: d.criado_em, movidoEm: d.movido_em }));
    const r = remotos.filter((x) => !protegidos.has(x.id));
    r.push(...e.despejo.filter((x) => protegidos.has(x.id)));
    r.sort((a, b) => (a.criadoEm < b.criadoEm ? -1 : 1));
    set("despejo", r);
  }
  if (!tempos.error && tempos.data) {
    const t: Record<string, number> = {};
    for (const r of tempos.data) t[r.tarefa_id] = Number(r.segundos);
    for (const id of protegidos) if (e.tempos[id] !== undefined) t[id] = e.tempos[id];
    set("tempos", t);
  }
  if (!cron.error && !protegidos.size) set("cronometro", { tarefaId: cron.data?.tarefa_id ?? null, inicio: cron.data?.inicio ?? null });
  if (!prefs.error && prefs.data?.dados) set("prefs", { ...PREFERENCIAS_PADRAO, ...(prefs.data.dados as object) });
  if (!anexos.error && anexos.data) {
    const remotos: Anexo[] = anexos.data.map((a) => ({ id: a.id, tarefaId: a.tarefa_id, nome: a.nome, caminho: a.caminho, tamanho: Number(a.tamanho), tipo: a.tipo, criadoEm: a.criado_em }));
    remotos.push(...e.anexos.filter((a) => a.pendente && !remotos.some((r) => r.id === a.id)));
    set("anexos", remotos);
  }
  if (Object.keys(mudanca).length) definir(mudanca);
}

export const hojeDoAparelho = () => diaISO(new Date());

/** Verdadeiro enquanto o estado muda por causa de outra janela (não é para avisar as outras de volta). */
export let vindoDeFora = false;

/** Outra janela (o menu do Mac, outra aba) gravou no espelho: traz os dados de lá sem tocar na sessão. */
export async function recarregarDoEspelho() {
  const chave = espelhoAtual();
  if (!chave) return;
  const salvo = await lerEstado<Partial<Estado>>(chave);
  if (!salvo) return;
  const { modo: _m, sincronizando: _s, erro: _e, online: _o, pendencias: _p, ...dados } = salvo;
  vindoDeFora = true;
  try {
    definir(dados);
  } finally {
    vindoDeFora = false;
  }
}
