// Capturas da web com os mesmos dados de exemplo do app Mac (Capturas.swift → semear),
// no mesmo tamanho de janela (1180×760), para comparar lado a lado com as capturas do Mac.
import { createRequire } from "node:module";
import { spawn, execSync } from "node:child_process";
import { mkdirSync } from "node:fs";
const require = createRequire(import.meta.url);
let playwright;
try { playwright = require("playwright"); } catch { playwright = require(execSync("npm root -g").toString().trim() + "/playwright"); }

const PORTA = 4183;
const servidor = spawn("npx", ["vite", "preview", "--port", String(PORTA), "--strictPort"], { stdio: "ignore" });
const BASE = `http://localhost:${PORTA}/`;
const saida = process.argv[2] ?? "e2e/capturas/celular";
mkdirSync(saida, { recursive: true });

function dia(d) { const x = new Date(); x.setDate(x.getDate() + d); return x.toISOString().slice(0, 10).replace(/.*/, () => { const p = (n) => String(n).padStart(2, "0"); return `${x.getFullYear()}-${p(x.getMonth() + 1)}-${p(x.getDate())}`; }); }
function semente() {
  const L = "local-inbox";
  const agora = new Date().toISOString();
  let n = 0;
  const tarefas = {};
  const t = (titulo, prazo, extra = {}) => { const id = "t" + ++n; tarefas[id] = { id, listaId: L, titulo, notas: "", concluida: false, prazo, concluidaEm: null, mae: null, posicao: String(100 - n).padStart(5, "0"), atualizadaEm: agora, ...extra }; return id; };
  t("Enviar proposta para a Taís", dia(0), { notas: "Horário: 10:00" });
  t("Comprar presente de aniversário", dia(0));
  const tcc = t("Revisar capítulo 2 do TCC", dia(1));
  t("Pagar boleto da internet", dia(-2));
  t("Organizar fotos da viagem", null);
  t("Reescrever a conclusão", null, { mae: tcc, concluida: true, concluidaEm: agora, posicao: "00001" });
  t("Ajustar referências", null, { mae: tcc, posicao: "00002" });
  t("Ler comentários da orientadora", null, { mae: tcc, posicao: "00003" });
  const tempos = {};
  [["Responder e-mails", 0], ["Preparar slides", -1], ["Ler artigo", -2], ["Treino", -4], ["Planejar semana", -6]].forEach(([titulo, d], i) => {
    const quando = new Date(); quando.setDate(quando.getDate() + d);
    const id = t(titulo, dia(d), { concluida: true, concluidaEm: quando.toISOString() });
    tempos[id] = 900 * (i + 1);
  });
  tempos[tcc] = 2700;
  const desp = (texto, estado = "caixa") => ({ id: "d" + ++n, texto, estado, foto: null, criadoEm: agora, movidoEm: null });
  return {
    modo: "local", email: null, nome: null, avatar: null, googlePendente: false,
    listas: [{ id: L, titulo: "Minhas tarefas" }], listaFixa: L, tarefas, agendas: [], eventos: [], etiquetas: [], etiquetasDaTarefa: {},
    notas: [
      { id: "n1", titulo: "", dia: dia(0), foto: null, criadaEm: agora, editadaEm: agora, texto: "Semana puxada, mas dá. Foco no TCC de manhã.\n\n[ ] marcar médico\n[ ] separar roupas da academia\n→ enviar proposta" },
      { id: "n2", titulo: "Ideias do app", dia: null, foto: null, criadaEm: agora, editadaEm: agora, texto: "Reunião com Ana sobre o despejo e as notas.\n\n- triagem um a um\n- busca em tudo" },
    ],
    despejo: [
      ...["marcar consulta no dentista", "ideia: app de receitas da semana", "ver preço da passagem pra dezembro", "devolver o livro da biblioteca", "mandar mensagem pra vó", "print da agenda da clínica"].map((x) => desp(x)),
      desp("estudar compulsão alimentar", "depois"), desp("posicionamento da marca", "depois"), desp("comprar luminária nova", "nao"), desp("fazer curso de cerâmica", "nao"),
    ],
    tempos, cronometro: { tarefaId: tcc, inicio: new Date(Date.now() - 754_000).toISOString() }, anexos: [],
    prefs: { listaPadrao: L, coresListas: { [L]: "#C255C9" }, iconesListas: {}, ordemListas: [], ordemEtiquetas: [], agendasVisiveis: {}, energiaBaixa: false, mostrarEventosNoMenu: true, mostrarAtrasadasNoMenu: true, contarAtrasadas: true, somAoConcluir: false },
    ultimaSync: agora,
  };
}

const CENAS = [
  ["hoje", "#/hoje"], ["amanha", "#/amanha"], ["proximas", "#/proximas"], ["calendario", "#/calendario"], ["todas", "#/todas"],
  ["concluidas", "#/concluidas"], ["lista", "#/lista/local-inbox"], ["despejo", "#/despejo"], ["notas", "#/notas"], ["ajustes", "#/ajustes"],
  ["mais", "#/hoje", async (p) => { await p.getByLabel("Mais telas").click(); }],
  ["digitando", "#/hoje", async (p) => { await p.getByPlaceholder("Adicionar tarefa").first().fill("ligar pro banco amanhã #urgente"); }],
  ["ajustes-aparencia", "#/ajustes", async (p) => { await p.getByRole("button", { name: /Aparência/ }).click(); await p.waitForTimeout(300); await p.locator(".pagina").evaluate((el) => el.scrollTo(0, 400)); }],
  ["calendario-baixo", "#/calendario", async (p) => { await p.locator(".pagina").first().evaluate((el) => el.scrollTo(0, 600)); }],
  ["detalhe", "#/hoje", async (p) => { await p.locator("[data-tarefa]").first().click(); }],
  ["nota-aberta", "#/notas", async (p) => { await p.getByText("Ideias do app").click(); }],
];

try {
  for (let i = 0; i < 50; i++) { try { await fetch(BASE); break; } catch { await new Promise((r) => setTimeout(r, 200)); } }
  const nav = await playwright.chromium.launch();
  for (const tema of ["claro"]) {
    const ctx = await nav.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, colorScheme: tema === "escuro" ? "dark" : "light" });
    const p = await ctx.newPage();
    await p.goto(BASE);
    const estado = semente();
    await p.evaluate(async (estado) => {
      localStorage.setItem("tasker.modo", "local");
      await new Promise((ok, erro) => {
        const r = indexedDB.open("tasker", 1);
        r.onupgradeneeded = () => { const db = r.result; db.createObjectStore("estado"); db.createObjectStore("fila", { keyPath: "id" }); db.createObjectStore("arquivos"); };
        r.onsuccess = () => { const tx = r.result.transaction("estado", "readwrite"); tx.objectStore("estado").put(estado, "local"); tx.oncomplete = () => { r.result.close(); ok(); }; tx.onerror = erro; };
        r.onerror = erro;
      });
    }, estado);
    for (const [nome, rota, roteiro] of CENAS) {
      await p.goto(BASE + rota);
      await p.reload();
      await p.waitForTimeout(500);
      if (roteiro) { await roteiro(p); await p.waitForTimeout(400); }
      await p.screenshot({ path: `${saida}/${nome}-${tema}.png` });
    }
    await ctx.close();
  }
  await nav.close();
} finally {
  servidor.kill();
}
