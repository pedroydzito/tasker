// Datas, horário nas notas, durações e a criação rápida — as mesmas regras do app Mac.

/** Dia local em AAAA-MM-DD (nunca UTC: 23h de um dia não pode virar o dia seguinte). */
export function diaISO(d: Date): string {
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const dia = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${m}-${dia}`;
}

/** "AAAA-MM-DD..." → meia-noite local daquele dia. */
export function deISO(s: string): Date {
  const [a, m, d] = s.slice(0, 10).split("-").map(Number);
  return new Date(a, (m ?? 1) - 1, d ?? 1);
}

export function hojeISO(): string {
  return diaISO(new Date());
}

export function somarDias(iso: string, dias: number): string {
  const d = deISO(iso);
  d.setDate(d.getDate() + dias);
  return diaISO(d);
}

export function diasEntre(de: string, ate: string): number {
  return Math.round((deISO(ate).getTime() - deISO(de).getTime()) / 86_400_000);
}

const fmtSemana = new Intl.DateTimeFormat("pt-BR", { weekday: "long" });
const fmtDiaMes = new Intl.DateTimeFormat("pt-BR", { day: "numeric", month: "short" });
const fmtDiaMesAno = new Intl.DateTimeFormat("pt-BR", { day: "numeric", month: "short", year: "numeric" });
const fmtLongo = new Intl.DateTimeFormat("pt-BR", { weekday: "long", day: "numeric", month: "short" });

export const primeiraMaiuscula = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);

const memo = new Map<string, string>();

/** "Hoje", "Amanhã", "Ontem", "Quarta-feira" ou "26 de out." (memorizado por hoje+dia). */
export function rotuloCurto(dia: string, hoje: string): string {
  const chave = hoje + dia;
  const pronto = memo.get(chave);
  if (pronto) return pronto;
  const diff = diasEntre(hoje, dia);
  let r: string;
  if (diff === 0) r = "Hoje";
  else if (diff === 1) r = "Amanhã";
  else if (diff === -1) r = "Ontem";
  else if (diff >= 2 && diff <= 6) r = primeiraMaiuscula(fmtSemana.format(deISO(dia)));
  else r = (dia.slice(0, 4) === hoje.slice(0, 4) ? fmtDiaMes : fmtDiaMesAno).format(deISO(dia)).replace(/\.$/, ".");
  if (memo.size > 2000) memo.clear();
  memo.set(chave, r);
  return r;
}

/** Como o curto, mas data passada diz há quantos dias: "12 dias atrás · 15 de out.". */
export function rotuloComAtraso(dia: string, hoje: string): string {
  const atras = diasEntre(dia, hoje);
  if (atras <= 1) return rotuloCurto(dia, hoje);
  return `${atras} dias atrás · ${fmtDiaMes.format(deISO(dia))}`;
}

/** "Segunda-feira, 26 de out." */
export function rotuloLongo(dia: string): string {
  return primeiraMaiuscula(fmtLongo.format(deISO(dia)));
}

// MARK: Horário nas notas ("Horário: 14:30" na última linha — vai junto para o Google Tasks)

const PREFIXO = "Horário: ";

export function separarHorario(notas: string | null | undefined): { texto: string; horario: string | null } {
  if (!notas) return { texto: "", horario: null };
  const linhas = notas.split("\n");
  while (linhas.length && !linhas[linhas.length - 1].trim()) linhas.pop();
  const ultima = linhas[linhas.length - 1]?.trim() ?? "";
  if (!ultima.startsWith(PREFIXO)) return { texto: notas, horario: null };
  const hora = ultima.slice(PREFIXO.length).trim();
  if (!/^\d\d:\d\d$/.test(hora)) return { texto: notas, horario: null };
  linhas.pop();
  while (linhas.length && !linhas[linhas.length - 1].trim()) linhas.pop();
  return { texto: linhas.join("\n"), horario: hora };
}

export function juntarHorario(texto: string, horario: string | null): string {
  const limpo = texto.trim();
  if (!horario) return limpo;
  return limpo ? `${limpo}\n\n${PREFIXO}${horario}` : PREFIXO + horario;
}

/** Aceita "9", "930", "9:30", "09h30". */
export function lerHora(texto: string): string | null | undefined {
  const d = texto.replace(/\D/g, "");
  if (!d) return null;
  let h = 0, m = 0;
  if (d.length <= 2) h = Number(d);
  else if (d.length === 3) { h = Number(d[0]); m = Number(d.slice(1)); }
  else { h = Number(d.slice(0, 2)); m = Number(d.slice(2, 4)); }
  if (h > 23 || m > 59) return undefined;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

// MARK: Duração

export function relogio(segundos: number): string {
  const s = Math.max(0, Math.floor(segundos));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  const p = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${p(m)}:${p(sec)}` : `${p(m)}:${p(sec)}`;
}

export function duracaoCurta(segundos: number): string {
  const s = Math.max(0, Math.floor(segundos));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  if (h > 0) return m > 0 ? `${h}h ${m}m` : `${h}h`;
  if (m > 0) return `${m}m`;
  return `${s}s`;
}

/** Número sozinho = minutos. Aceita "1h", "1h20", "1h 20m", "90m", "45s", "1:20" (h:min), "1:20:30". */
export function lerDuracao(texto: string): number | null {
  const t = texto.toLowerCase().replace(/\s/g, "").replace(",", ".");
  if (!t) return null;
  if (t.includes(":")) {
    const p = t.split(":").map(Number);
    if (p.some((n) => Number.isNaN(n)) || p.length < 2 || p.length > 3) return null;
    return p.length === 2 ? p[0] * 3600 + p[1] * 60 : p[0] * 3600 + p[1] * 60 + p[2];
  }
  if (/^\d+(\.\d+)?$/.test(t)) return Number(t) * 60;
  let total = 0, numero = "", achou = false;
  for (const ch of t) {
    if (/[\d.]/.test(ch)) { numero += ch; continue; }
    const v = Number(numero);
    if (!numero || Number.isNaN(v)) return null;
    if (ch === "h") total += v * 3600;
    else if (ch === "m") total += v * 60;
    else if (ch === "s") total += v;
    else return null;
    numero = "";
    achou = true;
  }
  if (numero) {
    if (!achou) return null;
    total += Number(numero) * 60;
  }
  return achou ? total : null;
}

// MARK: Criação rápida ("pagar conta amanhã ~casa #urgente")

export interface Lido {
  titulo: string;
  /** undefined = não escrito; null = "sem data" explícito. */
  prazo: string | null | undefined;
  listaId: string | null;
  etiquetas: string[];
}

const dobrar = (s: string) =>
  s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/^[\p{P}]+|[\p{P}]+$/gu, "");

export function nomeDeListaNormalizado(nome: string): string {
  return nome.replace(/[^\p{L}\p{N} ]/gu, "").trim();
}

const SEMANA: Record<string, number> = {
  domingo: 0, segunda: 1, "segunda-feira": 1, terca: 2, "terca-feira": 2, quarta: 3, "quarta-feira": 3,
  quinta: 4, "quinta-feira": 4, sexta: 5, "sexta-feira": 5, sabado: 6,
};

function dataNumerica(p: string, hoje: string): string | null {
  const partes = p.split("/").map(Number);
  if (partes.length < 2 || partes.length > 3 || partes.some(Number.isNaN)) return null;
  const [d, m] = partes;
  if (d < 1 || d > 31 || m < 1 || m > 12) return null;
  let ano = partes.length === 3 ? partes[2] : Number(hoje.slice(0, 4));
  if (ano < 100) ano += 2000;
  const data = new Date(ano, m - 1, d);
  if (data.getDate() !== d || data.getMonth() !== m - 1) return null; // 31/02 não vira março
  let iso = diaISO(data);
  if (partes.length === 2 && iso < hoje) iso = diaISO(new Date(ano + 1, m - 1, d));
  return iso;
}

export function lerCriacaoRapida(texto: string, listas: { id: string; titulo: string }[], hoje: string): Lido {
  let tokens = texto.split(" ").filter(Boolean);
  const etiquetas: string[] = [];
  let listaId: string | null = null;
  let prazo: string | null | undefined;

  tokens = tokens.filter((t) => {
    if (t.startsWith("#") && t.length > 1) { etiquetas.push(t.slice(1)); return false; }
    return true;
  });

  const iLista = tokens.findIndex((t) => t.startsWith("~") && t.length > 1);
  if (iLista >= 0) {
    const q = dobrar(tokens[iLista].slice(1));
    const achada = listas.find((l) => dobrar(nomeDeListaNormalizado(l.titulo)).startsWith(q));
    if (achada) { listaId = achada.id; tokens.splice(iLista, 1); }
  }

  const dobrados = tokens.map(dobrar);
  const frases: [string[], string | null][] = [
    [["depois", "de", "amanha"], somarDias(hoje, 2)],
    [["sem", "data"], null],
  ];
  for (const [frase, valor] of frases) {
    for (let i = 0; i + frase.length <= dobrados.length; i++) {
      if (frase.every((w, k) => dobrados[i + k] === w)) {
        tokens.splice(i, frase.length);
        return { titulo: tokens.join(" "), prazo: valor, listaId, etiquetas };
      }
    }
  }

  for (let i = 0; i < dobrados.length; i++) {
    const w = dobrados[i];
    let valor: string | null = null;
    if (w === "hoje") valor = hoje;
    else if (w === "amanha") valor = somarDias(hoje, 1);
    else if (w in SEMANA) {
      let diff = (SEMANA[w] - deISO(hoje).getDay() + 7) % 7;
      if (diff === 0) diff = 7;
      valor = somarDias(hoje, diff);
    } else valor = dataNumerica(tokens[i], hoje);
    if (valor) {
      let inicio = i;
      if (i > 0 && ["na", "no", "pra", "para", "em", "ate"].includes(dobrados[i - 1])) inicio = i - 1;
      tokens.splice(inicio, i - inicio + 1);
      prazo = valor;
      break;
    }
  }
  return { titulo: tokens.join(" "), prazo, listaId, etiquetas };
}

/** Lista colada: uma por linha, sem marcadores ("- ", "• ", "1. ", "[ ]"). */
export function semMarcador(linha: string): string {
  let s = linha.trim();
  for (const p of ["- [ ] ", "[ ] ", "☐ ", "- ", "• ", "* ", "– "]) {
    if (s.startsWith(p)) { s = s.slice(p.length); break; }
  }
  s = s.replace(/^\d+[.)] /, "");
  return s.trim();
}

export function linhas(texto: string): string[] {
  return texto.split(/\r?\n/).map(semMarcador).filter(Boolean);
}

export function normalizarBusca(s: string): string {
  return s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

export function uuid(): string {
  return crypto.randomUUID();
}

/** Cor estável a partir do id (mesma conta do app Mac). */
export const PALETA = ["#E8553F", "#E08A1E", "#C9A21B", "#3FA35B", "#1FA6A0", "#3B82E0", "#6E5CE6", "#C255C9", "#D9467A", "#7A7468"];
export function corDaChave(id: string): string {
  let h = 5381n;
  for (const b of new TextEncoder().encode(id)) h = (h * 33n + BigInt(b)) & 0xffffffffffffffffn;
  return PALETA[Number(((h * 3n) & 0xffffffffffffffffn) % BigInt(PALETA.length))];
}
