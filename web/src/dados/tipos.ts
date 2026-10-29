/** Lista do Google Tasks. */
export interface Lista {
  id: string;
  titulo: string;
}

/** Tarefa do Google Tasks (espelho local). `prazo` é só a data (AAAA-MM-DD). */
export interface Tarefa {
  id: string;
  listaId: string;
  titulo: string;
  /** Notas como o Google guarda (o horário vai na última linha: "Horário: 14:30"). */
  notas: string;
  concluida: boolean;
  prazo: string | null;
  concluidaEm: string | null;
  mae: string | null;
  posicao: string;
  atualizadaEm: string;
  link?: string | null;
  /** Criada aqui e ainda não confirmada pelo Google. */
  provisoria?: boolean;
}

export interface Agenda {
  id: string;
  titulo: string;
  cor: string;
  principal: boolean;
  selecionadaNoGoogle: boolean;
}

export interface Evento {
  id: string;
  agendaId: string;
  titulo: string;
  inicio: string;
  fim: string;
  diaTodo: boolean;
  cor: string;
  link: string | null;
}

export interface Etiqueta {
  id: string;
  nome: string;
  cor: string;
  ordem: number;
}

export interface Nota {
  id: string;
  titulo: string;
  texto: string;
  /** Nota do dia (AAAA-MM-DD) ou null numa nota solta. */
  dia: string | null;
  foto: string | null;
  criadaEm: string;
  editadaEm: string;
}

export type EstadoDespejo = "caixa" | "depois" | "nao";

export interface ItemDespejo {
  id: string;
  texto: string;
  estado: EstadoDespejo;
  foto: string | null;
  criadoEm: string;
  movidoEm: string | null;
}

export interface Anexo {
  id: string;
  tarefaId: string;
  nome: string;
  /** Caminho no bucket "anexos" (<user>/<id>-<nome>). */
  caminho: string;
  tamanho: number;
  tipo: string;
  criadoEm: string;
  /** Ainda só no aparelho (subindo). */
  pendente?: boolean;
}

export interface Cronometro {
  tarefaId: string | null;
  inicio: string | null;
}

export type Tema = "sistema" | "claro" | "escuro";

/** Preferências que viajam com a conta (aparência das listas, ordem...). */
export interface Preferencias {
  listaPadrao: string | null;
  coresListas: Record<string, string>;
  iconesListas: Record<string, string>;
  ordemListas: string[];
  ordemEtiquetas: string[];
  agendasVisiveis: Record<string, boolean>;
  energiaBaixa: boolean;
  mostrarEventosNoMenu: boolean;
  mostrarAtrasadasNoMenu: boolean;
  contarAtrasadas: boolean;
  somAoConcluir: boolean;
  /** Dicas de primeira vez já vistas (valem na conta, em todo aparelho). */
  dicasVistas: string[];
  /** Tema escolhido (viaja com a conta; o aparelho guarda a cópia para pintar antes do JS). */
  tema: "sistema" | "claro" | "escuro";
  /** Escolhas de tela que a pessoa considera dela. */
  eventosRecolhidos: boolean;
  todasPorLista: boolean;
  periodoConcluidas: "semana" | "mes" | "ano";
}

export const PREFERENCIAS_PADRAO: Preferencias = {
  listaPadrao: null,
  coresListas: {},
  iconesListas: {},
  ordemListas: [],
  ordemEtiquetas: [],
  agendasVisiveis: {},
  energiaBaixa: false,
  mostrarEventosNoMenu: true,
  mostrarAtrasadasNoMenu: true,
  contarAtrasadas: true,
  somAoConcluir: false,
  dicasVistas: [],
  tema: "sistema",
  eventosRecolhidos: false,
  todasPorLista: false,
  periodoConcluidas: "semana",
};

/** Tudo o que o app mostra. Vive em memória (módulo) e espelhado no IndexedDB. */
export interface Estado {
  modo: "carregando" | "entrar" | "local" | "conta";
  email: string | null;
  nome: string | null;
  avatar: string | null;
  /** Conta Supabase sem o Google conectado (precisa reconectar). */
  googlePendente: boolean;
  listas: Lista[];
  listaFixa: string | null;
  tarefas: Record<string, Tarefa>;
  agendas: Agenda[];
  eventos: Evento[];
  etiquetas: Etiqueta[];
  /** tarefaId → ids de etiqueta */
  etiquetasDaTarefa: Record<string, string[]>;
  notas: Nota[];
  despejo: ItemDespejo[];
  tempos: Record<string, number>;
  cronometro: Cronometro;
  anexos: Anexo[];
  prefs: Preferencias;
  ultimaSync: string | null;
  sincronizando: boolean;
  erro: string | null;
  /** Operações esperando subir (fila offline). */
  pendencias: number;
  online: boolean;
}
