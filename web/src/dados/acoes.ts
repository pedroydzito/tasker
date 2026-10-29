import { definir, ler } from "./armazem";
import { comDesfazer, sucesso } from "./avisos";
import { listaPadrao, pendentesDaNota, tempoDe } from "./consultas";
import { apagarArquivo, guardarArquivo } from "./espelho";
import { enfileirar, quandoTrocarId } from "./fila";
import type { Anexo, EstadoDespejo, Etiqueta, ItemDespejo, Nota, Preferencias, Tarefa } from "./tipos";
import { hojeISO, juntarHorario, linhas, lerCriacaoRapida, PALETA, separarHorario, uuid } from "./util";

// Tudo o que a pessoa faz: muda a tela na hora (otimista, §4.4) e entra na fila para subir.

const T = "https://tasks.googleapis.com/tasks/v1";
const urlTarefas = (lista: string) => `${T}/lists/${encodeURIComponent(lista)}/tasks`;
const urlTarefa = (lista: string, id: string) => `${urlTarefas(lista)}/${encodeURIComponent(id)}`;
const agoraISO = () => new Date().toISOString();
const prazoGoogle = (dia: string | null) => (dia ? `${dia}T00:00:00.000Z` : null);
const posicaoNoTopo = () => String(Number.MAX_SAFE_INTEGER - Date.now()).padStart(20, "0");

// MARK: Ids provisórios → definitivos (a tarefa criada offline continua a mesma para quem a usa)

quandoTrocarId((prov, def) => {
  definir((e) => {
    const tarefas = { ...e.tarefas };
    const t = tarefas[prov];
    if (t) {
      delete tarefas[prov];
      tarefas[def] = { ...t, id: def, provisoria: false };
    }
    for (const [id, x] of Object.entries(tarefas)) if (x.mae === prov) tarefas[id] = { ...x, mae: def };
    const listas = e.listas.map((l) => (l.id === prov ? { ...l, id: def } : l));
    for (const [id, x] of Object.entries(tarefas)) if (x.listaId === prov) tarefas[id] = { ...x, listaId: def };
    const trocar = <V,>(r: Record<string, V>) => {
      if (!(prov in r)) return r;
      const n = { ...r };
      n[def] = n[prov];
      delete n[prov];
      return n;
    };
    return {
      tarefas,
      listas,
      tempos: trocar(e.tempos),
      etiquetasDaTarefa: trocar(e.etiquetasDaTarefa),
      cronometro: e.cronometro.tarefaId === prov ? { ...e.cronometro, tarefaId: def } : e.cronometro,
      anexos: e.anexos.map((a) => (a.tarefaId === prov ? { ...a, tarefaId: def } : a)),
      prefs: e.prefs.listaPadrao === prov ? { ...e.prefs, listaPadrao: def } : e.prefs,
    };
  });
});

function porId(id: string): Tarefa | undefined {
  return ler().tarefas[id];
}

function gravarTarefa(t: Tarefa) {
  definir((e) => ({ tarefas: { ...e.tarefas, [t.id]: t } }));
}

// MARK: Tarefas

export interface NovaTarefa {
  titulo: string;
  listaId?: string | null;
  prazo?: string | null;
  horario?: string | null;
  notas?: string;
  etiquetas?: string[];
  mae?: string | null;
  silencioso?: boolean;
}

export function criarTarefa(n: NovaTarefa): string | null {
  const titulo = n.titulo.trim();
  const e = ler();
  const listaId = n.listaId ?? listaPadrao(e);
  if (!titulo || !listaId) return null;
  const prazo = n.prazo ?? null;
  const notas = juntarHorario(n.notas ?? "", prazo ? (n.horario ?? null) : null);
  const id = `tmp-${uuid()}`;
  const t: Tarefa = {
    id, listaId, titulo, notas, concluida: false, prazo, concluidaEm: null, mae: n.mae ?? null,
    posicao: n.mae ? "~" + Date.now() : posicaoNoTopo(), atualizadaEm: agoraISO(), provisoria: e.modo === "conta",
  };
  gravarTarefa(t);
  if (n.etiquetas?.length) definirEtiquetas(id, n.etiquetas);
  if (!n.silencioso) sucesso(n.mae ? "Subtarefa adicionada" : "Tarefa adicionada", n.mae ? "subtarefas adicionadas" : "tarefas adicionadas");
  const corpo: Record<string, unknown> = { title: titulo };
  if (notas) corpo.notes = notas;
  if (prazo) corpo.due = prazoGoogle(prazo);
  const url = n.mae ? `${urlTarefas(listaId)}?parent=${encodeURIComponent(n.mae)}` : urlTarefas(listaId);
  void enfileirar({ tipo: "google", metodo: "POST", url, corpo, provisorio: id });
  return id;
}

/** Texto do campo de criação rápida: entende data, ~lista e #etiqueta. Várias linhas = várias tarefas. */
export function criarDoTexto(texto: string, padrao: { prazo?: string | null; listaId?: string | null; etiqueta?: string | null; horario?: string | null }) {
  const e = ler();
  const hoje = hojeISO();
  const itens = linhas(texto);
  let criadas = 0;
  for (const linha of itens.length > 1 ? itens : [texto]) {
    const lido = lerCriacaoRapida(linha, e.listas, hoje);
    const titulo = lido.titulo.trim();
    if (!titulo) continue;
    const etiquetas = resolverEtiquetas(lido.etiquetas);
    if (padrao.etiqueta && !etiquetas.includes(padrao.etiqueta)) etiquetas.push(padrao.etiqueta);
    const prazo = lido.prazo !== undefined ? lido.prazo : (padrao.prazo ?? null);
    criarTarefa({
      titulo, listaId: lido.listaId ?? padrao.listaId ?? null, prazo,
      horario: lido.prazo === undefined ? padrao.horario : null, etiquetas,
    });
    criadas++;
  }
  return criadas;
}

function patch(t: Tarefa, campos: Record<string, unknown>) {
  void enfileirar({ tipo: "google", metodo: "PATCH", url: urlTarefa(t.listaId, t.id), corpo: campos });
}

export function concluir(id: string, feito: boolean) {
  const t = porId(id);
  if (!t) return;
  if (feito && ler().cronometro.tarefaId === id) pausarCronometro();
  gravarTarefa({ ...t, concluida: feito, concluidaEm: feito ? agoraISO() : null, atualizadaEm: agoraISO() });
  patch(t, feito ? { status: "completed" } : { status: "needsAction", completed: null });
}

/** Salva título, notas (com horário) e data de uma vez — só o que mudou. */
export function salvarTarefa(id: string, campos: { titulo?: string; notasVisiveis?: string; horario?: string | null; prazo?: string | null }) {
  const t = porId(id);
  if (!t) return;
  const atual = separarHorario(t.notas);
  const titulo = campos.titulo?.trim() || t.titulo;
  const prazo = campos.prazo !== undefined ? campos.prazo : t.prazo;
  const horario = prazo ? (campos.horario !== undefined ? campos.horario : atual.horario) : null;
  const notas = juntarHorario(campos.notasVisiveis ?? atual.texto, horario);
  const corpo: Record<string, unknown> = {};
  if (titulo !== t.titulo) corpo.title = titulo;
  if (notas !== t.notas) corpo.notes = notas;
  if (prazo !== t.prazo) corpo.due = prazoGoogle(prazo);
  if (!Object.keys(corpo).length) return;
  gravarTarefa({ ...t, titulo, notas, prazo, atualizadaEm: agoraISO() });
  patch(t, corpo);
}

export function definirPrazo(id: string, prazo: string | null) {
  salvarTarefa(id, { prazo });
}

export function moverTarefa(id: string, destino: string) {
  const t = porId(id);
  if (!t || t.listaId === destino) return;
  gravarTarefa({ ...t, listaId: destino, mae: null });
  // Subtarefas vão junto (o Google as move com a mãe).
  for (const f of Object.values(ler().tarefas)) if (f.mae === id) gravarTarefa({ ...f, listaId: destino });
  void enfileirar({
    tipo: "google", metodo: "POST",
    url: `${urlTarefa(t.listaId, t.id)}/move?destinationTasklist=${encodeURIComponent(destino)}`,
  });
}

/** Some na hora (com as subtarefas); só é apagada de verdade se não houver "Desfazer" em 3 s. */
export function excluirTarefa(id: string) {
  const t = porId(id);
  if (!t) return;
  const filhas = Object.values(ler().tarefas).filter((x) => x.mae === id);
  definir((e) => {
    const tarefas = { ...e.tarefas };
    delete tarefas[id];
    for (const f of filhas) delete tarefas[f.id];
    return { tarefas };
  });
  comDesfazer(
    filhas.length ? "Tarefa e subtarefas excluídas" : "Tarefa excluída",
    () => definir((e) => ({ tarefas: { ...e.tarefas, [t.id]: t, ...Object.fromEntries(filhas.map((f) => [f.id, f])) } })),
    () => {
      void enfileirar({ tipo: "google", metodo: "DELETE", url: urlTarefa(t.listaId, t.id) });
      definir((e) => {
        const tarefas = { ...e.tarefas };
        delete tarefas[id];
        const et = { ...e.etiquetasDaTarefa };
        delete et[id];
        return { tarefas, etiquetasDaTarefa: et };
      });
    },
  );
}

export function adiarAtrasadas() {
  const hoje = hojeISO();
  for (const t of Object.values(ler().tarefas)) if (!t.concluida && t.prazo && t.prazo < hoje) definirPrazo(t.id, hoje);
}

// MARK: Listas

export function criarLista(titulo: string, extra: { icone?: string | null; cor?: string | null } = {}): string | null {
  const nome = titulo.trim();
  if (!nome) return null;
  const id = `tmp-${uuid()}`;
  definir((e) => ({ listas: [...e.listas, { id, titulo: nome }] }));
  if (extra.icone || extra.cor) {
    mudarPrefs((p) => ({
      iconesListas: extra.icone ? { ...p.iconesListas, [id]: extra.icone } : p.iconesListas,
      coresListas: extra.cor ? { ...p.coresListas, [id]: extra.cor } : p.coresListas,
    }));
  }
  sucesso("Lista criada", "listas criadas");
  void enfileirar({ tipo: "google", metodo: "POST", url: `${T}/users/@me/lists`, corpo: { title: nome }, provisorio: id });
  return id;
}

export function renomearLista(id: string, titulo: string) {
  const nome = titulo.trim();
  if (!nome) return;
  definir((e) => ({ listas: e.listas.map((l) => (l.id === id ? { ...l, titulo: nome } : l)) }));
  void enfileirar({ tipo: "google", metodo: "PATCH", url: `${T}/users/@me/lists/${encodeURIComponent(id)}`, corpo: { title: nome } });
}

export function excluirLista(id: string) {
  const e = ler();
  if (id === e.listaFixa) return;
  const lista = e.listas.find((l) => l.id === id);
  if (!lista) return;
  const indice = e.listas.indexOf(lista);
  const tarefas = Object.values(e.tarefas).filter((t) => t.listaId === id);
  definir((x) => {
    const ts = { ...x.tarefas };
    for (const t of tarefas) delete ts[t.id];
    return { listas: x.listas.filter((l) => l.id !== id), tarefas: ts };
  });
  comDesfazer(
    `Lista “${lista.titulo}” excluída`,
    () =>
      definir((x) => {
        const listas = [...x.listas];
        listas.splice(Math.min(indice, listas.length), 0, lista);
        return { listas, tarefas: { ...x.tarefas, ...Object.fromEntries(tarefas.map((t) => [t.id, t])) } };
      }),
    () => {
      void enfileirar({ tipo: "google", metodo: "DELETE", url: `${T}/users/@me/lists/${encodeURIComponent(id)}` });
      mudarPrefs((p) => {
        const cores = { ...p.coresListas }, icones = { ...p.iconesListas };
        delete cores[id];
        delete icones[id];
        return { coresListas: cores, iconesListas: icones, ordemListas: p.ordemListas.filter((x) => x !== id), listaPadrao: p.listaPadrao === id ? null : p.listaPadrao };
      });
    },
  );
}

export function reordenarListas(ids: string[]) {
  definir((e) => {
    const pos = new Map(ids.map((id, i) => [id, i]));
    const listas = [...e.listas].sort((a, b) => {
      if (a.id === e.listaFixa) return -1;
      if (b.id === e.listaFixa) return 1;
      return (pos.get(a.id) ?? 999) - (pos.get(b.id) ?? 999);
    });
    return { listas };
  });
  mudarPrefs(() => ({ ordemListas: ler().listas.map((l) => l.id) }));
}

// MARK: Preferências (viajam com a conta)

let prefsTimer: ReturnType<typeof setTimeout> | null = null;
export function mudarPrefs(fn: (p: Preferencias) => Partial<Preferencias>) {
  definir((e) => ({ prefs: { ...e.prefs, ...fn(e.prefs) } }));
  if (prefsTimer) clearTimeout(prefsTimer);
  prefsTimer = setTimeout(() => {
    void enfileirar({ tipo: "tabela", tabela: "preferencias", acao: "upsert", linha: { dados: ler().prefs } });
  }, 300);
}

// MARK: Etiquetas (só no Tasker)

export function criarEtiqueta(nome: string, cor?: string): Etiqueta {
  const limpo = nome.trim();
  const e = ler();
  const existente = e.etiquetas.find((t) => t.nome.toLowerCase() === limpo.toLowerCase());
  if (existente) return existente;
  const nova: Etiqueta = { id: uuid(), nome: limpo, cor: cor ?? PALETA[e.etiquetas.length % PALETA.length], ordem: e.etiquetas.length };
  definir((x) => ({ etiquetas: [...x.etiquetas, nova] }));
  void enfileirar({ tipo: "tabela", tabela: "etiquetas", acao: "upsert", linha: { id: nova.id, nome: nova.nome, cor: nova.cor, ordem: nova.ordem } });
  return nova;
}

export function editarEtiqueta(id: string, campos: { nome?: string; cor?: string }) {
  const t = ler().etiquetas.find((x) => x.id === id);
  if (!t) return;
  const nova = { ...t, ...campos };
  definir((e) => ({ etiquetas: e.etiquetas.map((x) => (x.id === id ? nova : x)) }));
  void enfileirar({ tipo: "tabela", tabela: "etiquetas", acao: "upsert", linha: { id, nome: nova.nome, cor: nova.cor, ordem: nova.ordem } });
}

export function excluirEtiqueta(id: string) {
  const e = ler();
  const t = e.etiquetas.find((x) => x.id === id);
  if (!t) return;
  const antes = e.etiquetasDaTarefa;
  definir((x) => {
    const et: Record<string, string[]> = {};
    for (const [k, v] of Object.entries(x.etiquetasDaTarefa)) {
      const r = v.filter((i) => i !== id);
      if (r.length) et[k] = r;
    }
    return { etiquetas: x.etiquetas.filter((y) => y.id !== id), etiquetasDaTarefa: et };
  });
  comDesfazer(
    `Etiqueta “${t.nome}” excluída`,
    () => definir((x) => ({ etiquetas: [...x.etiquetas, t], etiquetasDaTarefa: antes })),
    () => void enfileirar({ tipo: "tabela", tabela: "etiquetas", acao: "delete", chave: { id } }),
  );
}

/** Resolve nomes digitados (#casa) em ids, criando o que não existe. */
export function resolverEtiquetas(nomes: string[]): string[] {
  return nomes.map((n) => criarEtiqueta(n).id);
}

export function definirEtiquetas(tarefaId: string, ids: string[]) {
  const antes = ler().etiquetasDaTarefa[tarefaId] ?? [];
  definir((e) => {
    const et = { ...e.etiquetasDaTarefa };
    if (ids.length) et[tarefaId] = ids;
    else delete et[tarefaId];
    return { etiquetasDaTarefa: et };
  });
  for (const id of antes.filter((x) => !ids.includes(x)))
    void enfileirar({ tipo: "tabela", tabela: "etiquetas_tarefas", acao: "delete", chave: { tarefa_id: tarefaId, etiqueta_id: id } });
  for (const id of ids.filter((x) => !antes.includes(x)))
    void enfileirar({ tipo: "tabela", tabela: "etiquetas_tarefas", acao: "upsert", linha: { tarefa_id: tarefaId, etiqueta_id: id } });
}

export function alternarEtiqueta(tarefaId: string, etiquetaId: string) {
  const ids = ler().etiquetasDaTarefa[tarefaId] ?? [];
  definirEtiquetas(tarefaId, ids.includes(etiquetaId) ? ids.filter((i) => i !== etiquetaId) : [...ids, etiquetaId]);
}

// MARK: Tempo

function gravarTempo(id: string, segundos: number) {
  definir((e) => {
    const tempos = { ...e.tempos };
    if (segundos > 0) tempos[id] = segundos;
    else delete tempos[id];
    return { tempos };
  });
  void enfileirar(
    segundos > 0
      ? { tipo: "tabela", tabela: "tempos", acao: "upsert", linha: { tarefa_id: id, segundos } }
      : { tipo: "tabela", tabela: "tempos", acao: "delete", chave: { tarefa_id: id } },
  );
}

function gravarCronometro(tarefaId: string | null, inicio: string | null) {
  definir({ cronometro: { tarefaId, inicio } });
  void enfileirar({ tipo: "tabela", tabela: "cronometro", acao: "upsert", linha: { tarefa_id: tarefaId, inicio } });
}

export function pausarCronometro(agora = Date.now()) {
  const e = ler();
  const id = e.cronometro.tarefaId;
  if (!id) return;
  gravarTempo(id, tempoDe(e, id, agora));
  gravarCronometro(null, null);
}

/** Play/pausa. Dar play numa tarefa pausa a que estava rodando. */
export function alternarCronometro(id: string, agora = Date.now()) {
  if (ler().cronometro.tarefaId === id) return pausarCronometro(agora);
  pausarCronometro(agora);
  gravarCronometro(id, new Date(agora).toISOString());
}

export function definirTempo(id: string, segundos: number) {
  gravarTempo(id, Math.max(0, segundos));
  if (ler().cronometro.tarefaId === id) gravarCronometro(id, new Date().toISOString());
}

// MARK: Despejo

function linhaDespejo(i: ItemDespejo) {
  return { id: i.id, texto: i.texto, estado: i.estado, foto: i.foto, criado_em: i.criadoEm, movido_em: i.movidoEm };
}

function gravarDespejo(i: ItemDespejo) {
  definir((e) => ({ despejo: e.despejo.some((x) => x.id === i.id) ? e.despejo.map((x) => (x.id === i.id ? i : x)) : [...e.despejo, i] }));
  void enfileirar({ tipo: "tabela", tabela: "despejo", acao: "upsert", linha: linhaDespejo(i) });
}

/** Joga na caixa. Várias linhas = um item por linha. Com foto, é um item só (o texto é o porquê). */
export function despejar(texto: string, foto?: string | null): number {
  const agora = Date.now();
  if (foto) {
    gravarDespejo({ id: uuid(), texto: texto.trim(), estado: "caixa", foto, criadoEm: new Date(agora).toISOString(), movidoEm: null });
    sucesso("Foto guardada no despejo");
    return 1;
  }
  const itens = linhas(texto);
  itens.forEach((t, i) =>
    gravarDespejo({ id: uuid(), texto: t, estado: "caixa", foto: null, criadoEm: new Date(agora + i).toISOString(), movidoEm: null }),
  );
  if (itens.length) sucesso(itens.length === 1 ? "Guardado no despejo" : `${itens.length} itens no despejo`);
  return itens.length;
}

export function editarDespejo(id: string, texto: string) {
  const i = ler().despejo.find((x) => x.id === id);
  if (!i) return;
  const limpo = texto.trim();
  if (!limpo && !i.foto) return apagarDespejo(id);
  gravarDespejo({ ...i, texto: limpo });
}

export function moverDespejo(id: string, estado: EstadoDespejo) {
  const i = ler().despejo.find((x) => x.id === id);
  if (!i || i.estado === estado) return;
  const anterior = i.estado;
  gravarDespejo({ ...i, estado, movidoEm: new Date().toISOString() });
  if (estado === "caixa") return sucesso("De volta à caixa de entrada");
  comDesfazer(
    estado === "depois" ? "Guardado para depois" : "Você decidiu não carregar isso",
    () => { const x = ler().despejo.find((y) => y.id === id); if (x) gravarDespejo({ ...x, estado: anterior }); },
    () => {},
  );
}

export function apagarDespejo(id: string) {
  const i = ler().despejo.find((x) => x.id === id);
  if (!i) return;
  definir((e) => ({ despejo: e.despejo.filter((x) => x.id !== id) }));
  comDesfazer(
    "Item apagado",
    () => definir((e) => ({ despejo: [...e.despejo, i].sort((a, b) => (a.criadoEm < b.criadoEm ? -1 : 1)) })),
    () => {
      void enfileirar({ tipo: "tabela", tabela: "despejo", acao: "delete", chave: { id } });
      if (i.foto) void enfileirar({ tipo: "apagar_arquivo", bucket: "fotos", caminho: i.foto });
    },
  );
}

export function esvaziarNao() {
  const itens = ler().despejo.filter((x) => x.estado === "nao");
  if (!itens.length) return;
  definir((e) => ({ despejo: e.despejo.filter((x) => x.estado !== "nao") }));
  comDesfazer(
    `${itens.length} ${itens.length === 1 ? "item apagado" : "itens apagados"}`,
    () => definir((e) => ({ despejo: [...e.despejo, ...itens] })),
    () => {
      for (const i of itens) {
        void enfileirar({ tipo: "tabela", tabela: "despejo", acao: "delete", chave: { id: i.id } });
        if (i.foto) void enfileirar({ tipo: "apagar_arquivo", bucket: "fotos", caminho: i.foto });
      }
    },
  );
}

/** Agora: vira tarefa para hoje, na lista padrão. */
export function fazerAgora(id: string) {
  const i = ler().despejo.find((x) => x.id === id);
  if (!i) return;
  despejoParaTarefa(id, { titulo: i.texto || "Foto", prazo: hojeISO() });
}

export function despejoParaTarefa(id: string, n: Omit<NovaTarefa, "titulo"> & { titulo: string }) {
  const i = ler().despejo.find((x) => x.id === id);
  if (!i || !n.titulo.trim()) return;
  // A foto não vai para o Google: fica numa nota com o mesmo nome.
  if (i.foto) novaNota({ titulo: n.titulo, texto: `Foto guardada junto da tarefa “${n.titulo}”.`, foto: i.foto, silencioso: true });
  criarTarefa(n);
  definir((e) => ({ despejo: e.despejo.filter((x) => x.id !== id) }));
  void enfileirar({ tipo: "tabela", tabela: "despejo", acao: "delete", chave: { id } });
}

export function despejoParaNota(id: string): string | null {
  const i = ler().despejo.find((x) => x.id === id);
  if (!i) return null;
  const nota = novaNota({ titulo: i.texto || "Foto", foto: i.foto });
  definir((e) => ({ despejo: e.despejo.filter((x) => x.id !== id) }));
  void enfileirar({ tipo: "tabela", tabela: "despejo", acao: "delete", chave: { id } });
  return nota;
}

// MARK: Notas

const linhaNota = (n: Nota) => ({ id: n.id, titulo: n.titulo, texto: n.texto, dia: n.dia, foto: n.foto, criada_em: n.criadaEm, editada_em: n.editadaEm });
const notaTimers = new Map<string, ReturnType<typeof setTimeout>>();

/** Grava a nota 1,2 s depois de parar de digitar (§7.2). */
function subirNota(id: string) {
  const t = notaTimers.get(id);
  if (t) clearTimeout(t);
  notaTimers.set(id, setTimeout(() => {
    notaTimers.delete(id);
    const n = ler().notas.find((x) => x.id === id);
    if (n) void enfileirar({ tipo: "tabela", tabela: "notas", acao: "upsert", linha: linhaNota(n) });
  }, 1200));
}

export function novaNota(n: { titulo?: string; texto?: string; foto?: string | null; silencioso?: boolean } = {}): string {
  const agora = new Date().toISOString();
  const nota: Nota = { id: uuid(), titulo: n.titulo ?? "", texto: n.texto ?? "", dia: null, foto: n.foto ?? null, criadaEm: agora, editadaEm: agora };
  definir((e) => ({ notas: [...e.notas, nota] }));
  void enfileirar({ tipo: "tabela", tabela: "notas", acao: "upsert", linha: linhaNota(nota) });
  if (!n.silencioso) sucesso("Nota criada", "notas criadas");
  return nota.id;
}

export function atualizarNota(id: string, campos: { titulo?: string; texto?: string }) {
  const n = ler().notas.find((x) => x.id === id);
  if (!n) return;
  const nova = { ...n, ...campos, editadaEm: new Date().toISOString() };
  if (nova.titulo === n.titulo && nova.texto === n.texto) return;
  definir((e) => ({ notas: e.notas.map((x) => (x.id === id ? nova : x)) }));
  subirNota(id);
}

/** Nota do dia: nasce no primeiro caractere e some quando fica vazia. */
export function escreverNoDia(dia: string, texto: string) {
  const e = ler();
  const n = e.notas.find((x) => x.dia === dia);
  const vazio = !texto.trim();
  if (n) {
    if (vazio && !n.titulo) return apagarNotaDireto(n.id);
    return atualizarNota(n.id, { texto });
  }
  if (vazio) return;
  const agora = new Date().toISOString();
  const nova: Nota = { id: uuid(), titulo: "", texto, dia, foto: null, criadaEm: agora, editadaEm: agora };
  definir((x) => ({ notas: [...x.notas, nova] }));
  subirNota(nova.id);
  sucesso("Nota do dia criada");
}

function apagarNotaDireto(id: string) {
  definir((e) => ({ notas: e.notas.filter((x) => x.id !== id) }));
  const t = notaTimers.get(id);
  if (t) clearTimeout(t);
  void enfileirar({ tipo: "tabela", tabela: "notas", acao: "delete", chave: { id } });
}

export function excluirNota(id: string) {
  const n = ler().notas.find((x) => x.id === id);
  if (!n) return;
  definir((e) => ({ notas: e.notas.filter((x) => x.id !== id) }));
  comDesfazer("Nota excluída", () => definir((e) => ({ notas: [...e.notas, n] })), () => {
    const t = notaTimers.get(id);
    if (t) clearTimeout(t);
    void enfileirar({ tipo: "tabela", tabela: "notas", acao: "delete", chave: { id } });
  });
}

export function descartarSeVazia(id: string) {
  const n = ler().notas.find((x) => x.id === id);
  if (n && !n.dia && !n.titulo.trim() && !n.texto.trim() && !n.foto) apagarNotaDireto(id);
}

/** "[ ] comprar pão" vira tarefa; a linha fica "→ comprar pão". */
export function tarefaDaLinha(notaId: string, linha: number) {
  const n = ler().notas.find((x) => x.id === notaId);
  if (!n) return;
  const ls = n.texto.split("\n");
  const p = pendentesDaNota(n.texto).find((x) => x.linha === linha);
  if (!p) return;
  const recuo = ls[linha].match(/^[ \t]*/)?.[0] ?? "";
  ls[linha] = `${recuo}→ ${p.titulo}`;
  atualizarNota(notaId, { texto: ls.join("\n") });
  criarTarefa({ titulo: p.titulo, prazo: n.dia });
}

export function revisaoDaSemana(): string {
  const e = ler();
  const hoje = new Date();
  const inicio = new Date(hoje);
  inicio.setDate(hoje.getDate() - hoje.getDay());
  const fim = new Date(inicio);
  fim.setDate(inicio.getDate() + 6);
  const fmt = new Intl.DateTimeFormat("pt-BR", { day: "numeric", month: "short" });
  const titulo = `Semana de ${fmt.format(inicio)} a ${fmt.format(fim)}`;
  const existente = e.notas.find((n) => n.titulo === titulo && !n.dia);
  if (existente) return existente.id;
  const desde = new Date(inicio.getFullYear(), inicio.getMonth(), inicio.getDate()).toISOString();
  const tarefas = Object.values(e.tarefas);
  const feitas = tarefas.filter((t) => t.concluida && (t.concluidaEm ?? "") >= desde);
  const ficou = tarefas.filter((t) => !t.concluida && t.prazo && t.prazo <= (hojeISO()));
  const tempo = feitas.reduce((s, t) => s + tempoDe(e, t.id), 0);
  const l: string[] = [];
  l.push(`Concluídas (${feitas.length})` + (tempo > 0 ? ` · ${Math.round(tempo / 60)} min registrados` : ""));
  l.push(...feitas.slice(0, 30).map((t) => `✓ ${t.titulo}`));
  if (!feitas.length) l.push("Nenhuma ainda — e tudo bem.");
  l.push("", `Ficou para depois (${ficou.length})`, ...ficou.slice(0, 15).map((t) => `• ${t.titulo}`), "");
  l.push(`Despejo: ${e.despejo.filter((d) => d.estado === "caixa").length} na caixa · ${e.despejo.filter((d) => d.estado === "depois").length} em Depois`, "");
  l.push("Como foi a semana?", "", "", "O que eu quero da próxima semana?", "[ ] ");
  return novaNota({ titulo, texto: l.join("\n") });
}

// MARK: Anexos e fotos

/** Comprime no cliente antes de subir (§9.1): no máximo 1600 px, JPEG. */
export async function comprimirImagem(arquivo: Blob, maximo = 1600): Promise<Blob> {
  if (!arquivo.type.startsWith("image/") || arquivo.type === "image/gif") return arquivo;
  try {
    const bitmap = await createImageBitmap(arquivo);
    const escala = Math.min(1, maximo / Math.max(bitmap.width, bitmap.height));
    const canvas = new OffscreenCanvas(Math.round(bitmap.width * escala), Math.round(bitmap.height * escala));
    canvas.getContext("2d")?.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    bitmap.close();
    return await canvas.convertToBlob({ type: "image/jpeg", quality: 0.82 });
  } catch {
    return arquivo;
  }
}

function pastaDoUsuario(): string {
  return localStorage.getItem("tasker.usuario") ?? "local";
}

/** Guarda a foto no aparelho e agenda a subida. Devolve o caminho no bucket "fotos". */
export async function guardarFoto(arquivo: Blob): Promise<string> {
  const blob = await comprimirImagem(arquivo);
  const caminho = `${pastaDoUsuario()}/${uuid()}.jpg`;
  await guardarArquivo(`fotos/${caminho}`, blob);
  void enfileirar({ tipo: "arquivo", bucket: "fotos", caminho, arquivoId: `fotos/${caminho}`, tipoArquivo: "image/jpeg" });
  return caminho;
}

export async function anexar(tarefaId: string, arquivo: File) {
  const blob = arquivo.type.startsWith("image/") ? await comprimirImagem(arquivo, 2400) : arquivo;
  const id = uuid();
  const nomeSeguro = arquivo.name.replace(/[^\p{L}\p{N}._-]+/gu, "_").slice(-80) || "arquivo";
  const caminho = `${pastaDoUsuario()}/${id}-${nomeSeguro}`;
  const anexo: Anexo = { id, tarefaId, nome: arquivo.name, caminho, tamanho: blob.size, tipo: blob.type || arquivo.type || "application/octet-stream", criadoEm: new Date().toISOString(), pendente: ler().modo === "conta" };
  await guardarArquivo(`anexos/${caminho}`, blob);
  definir((e) => ({ anexos: [...e.anexos, anexo] }));
  sucesso("Arquivo anexado", "arquivos anexados");
  void enfileirar({ tipo: "arquivo", bucket: "anexos", caminho, arquivoId: `anexos/${caminho}`, tipoArquivo: anexo.tipo });
  void enfileirar({ tipo: "tabela", tabela: "anexos", acao: "upsert", linha: { id, tarefa_id: tarefaId, nome: anexo.nome, caminho, tamanho: anexo.tamanho, tipo: anexo.tipo } });
}

export function removerAnexo(id: string) {
  const a = ler().anexos.find((x) => x.id === id);
  if (!a) return;
  definir((e) => ({ anexos: e.anexos.filter((x) => x.id !== id) }));
  comDesfazer("Anexo removido", () => definir((e) => ({ anexos: [...e.anexos, a] })), () => {
    void enfileirar({ tipo: "tabela", tabela: "anexos", acao: "delete", chave: { id } });
    void enfileirar({ tipo: "apagar_arquivo", bucket: "anexos", caminho: a.caminho });
    void apagarArquivo(`anexos/${a.caminho}`);
  });
}
