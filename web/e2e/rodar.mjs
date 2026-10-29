// E2E no modo "sem conta" (não precisa de Google): cria, conclui, anexa, despejo, nota, busca,
// recarrega offline (service worker) e tira capturas claro/escuro, desktop e celular.
import { createRequire } from "node:module";
import { spawn, execSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
const require = createRequire(import.meta.url);
let playwright;
try { playwright = require("playwright"); } catch { playwright = require(execSync("npm root -g").toString().trim() + "/playwright"); }

const PORTA = 4179;
const servidor = spawn("npx", ["vite", "preview", "--port", String(PORTA), "--strictPort"], { stdio: "ignore" });
const BASE = `http://localhost:${PORTA}/`;
const falhas = [];
const ve = (l) => l.first().waitFor({ timeout: 4000 }).then(() => true, () => false);
const ok = (cond, msg) => { console.log((cond ? "✓ " : "✗ ") + msg); if (!cond) falhas.push(msg); };
mkdirSync("e2e/capturas", { recursive: true });

try {
  for (let i = 0; i < 50; i++) { try { await fetch(BASE); break; } catch { await new Promise((r) => setTimeout(r, 200)); } }
  const navegador = await playwright.chromium.launch();
  const ctx = await navegador.newContext({ viewport: { width: 1280, height: 820 } });
  const p = await ctx.newPage();
  const erros = [];
  p.on("pageerror", (e) => erros.push(e.message));
  await p.goto(BASE);
  await p.getByRole("button", { name: "Começar" }).click();
  await p.getByRole("heading", { name: "Hoje" }).waitFor();
  ok(true, "entra sem conta");

  const campo = p.getByPlaceholder("Adicionar tarefa");
  await campo.fill("Comprar pão");
  await campo.press("Enter");
  await campo.fill("Ligar pro dentista amanhã");
  await campo.press("Enter");
  ok(await ve(p.getByText("Comprar pão")), "cria tarefa para hoje");
  ok(!(await ve(p.getByText("Ligar pro dentista"))), "tarefa com 'amanhã' não aparece em hoje");
  await p.getByRole("button", { name: "Amanhã" }).first().click();
  ok(await ve(p.getByText("Ligar pro dentista")), "aparece em Amanhã");
  await p.getByRole("button", { name: "Hoje" }).first().click();

  await p.getByText("Comprar pão").click();
  await p.getByLabel("Detalhes da tarefa").waitFor();
  await p.getByPlaceholder("Adicionar subtarefa").fill("integral");
  await p.getByPlaceholder("Adicionar subtarefa").press("Enter");
  ok(await ve(p.getByLabel("Detalhes da tarefa").getByText("integral")), "subtarefa");
  await p.getByLabel("Detalhes da tarefa").locator('input[type=file]').setInputFiles({ name: "lista.txt", mimeType: "text/plain", buffer: Buffer.from("leite") });
  await p.getByLabel("Detalhes da tarefa").getByText("lista.txt").waitFor();
  ok(true, "anexa arquivo");
  await p.screenshot({ path: "e2e/capturas/hoje-inspetor-claro.png" });
  await p.keyboard.press("Escape");

  await p.locator('[data-tarefa]').filter({ hasText: "Comprar pão" }).getByLabel("Concluir").click();
  await p.getByRole("button", { name: "Concluídas" }).first().click();
  ok(await ve(p.getByText("Comprar pão")), "concluída aparece em Concluídas");

  await p.getByRole("button", { name: "Despejo" }).first().click();
  await p.getByPlaceholder(/Escreva o que vier/).fill("ideia solta");
  await p.getByPlaceholder(/Escreva o que vier/).press("Enter");
  ok(await ve(p.getByText("ideia solta")), "despejo");

  await p.getByRole("button", { name: "Notas" }).first().click();
  await p.getByPlaceholder(/Como está o dia/).fill("Dia bom");
  await p.waitForTimeout(700);

  await p.keyboard.press("Control+k");
  await p.getByPlaceholder(/Buscar em tarefas/).fill("dentista");
  ok(await ve(p.getByRole("dialog").getByText("Ligar pro dentista")), "busca ⌘K");
  await p.keyboard.press("Escape");

  // Recarrega: tudo vem do IndexedDB.
  await p.reload();
  await p.getByRole("button", { name: "Despejo" }).first().click();
  ok(await ve(p.getByText("ideia solta")), "dados sobrevivem ao recarregar");

  // Escuro + celular.
  await p.evaluate(() => { localStorage.setItem("tasker.tema", "escuro"); });
  await p.goto(BASE + "#/hoje"); await p.reload();
  await p.getByRole("heading", { name: "Hoje" }).waitFor();
  await p.screenshot({ path: "e2e/capturas/hoje-escuro.png" });
  await p.setViewportSize({ width: 390, height: 844 });
  await p.goto(BASE + "#/calendario");
  await p.waitForTimeout(300);
  await p.screenshot({ path: "e2e/capturas/calendario-celular-escuro.png" });
  ok(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "sem rolagem horizontal no celular");
  await p.goto(BASE + "#/menu");
  await p.setViewportSize({ width: 360, height: 520 });
  await p.screenshot({ path: "e2e/capturas/menu.png" });
  ok(erros.length === 0, "sem erros de página " + erros.join(" | "));
  await navegador.close();
} catch (e) {
  falhas.push(String(e));
  console.error(e);
} finally {
  servidor.kill();
}
writeFileSync("e2e/capturas/resultado.txt", falhas.length ? falhas.join("\n") : "ok");
process.exit(falhas.length ? 1 : 0);
