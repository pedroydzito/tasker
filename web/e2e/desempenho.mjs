// Varredura de desempenho por tela num 4G fraco (desempenho §11.9): rede estrangulada pelo
// protocolo de depuração (1,6 Mbps de descida, 750 kbps de subida, 150 ms), service worker
// desligado (senão o byte de JS mente), "tempo até o conteúdo" por seletor de cada rota,
// pedidos contados, e duas rodadas: a primeira abertura e a volta.
import { createRequire } from "node:module";
import { spawn, execSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
const require = createRequire(import.meta.url);
let playwright;
try { playwright = require("playwright"); } catch { playwright = require(execSync("npm root -g").toString().trim() + "/playwright"); }

const PORTA = 4190;
const BASE = `http://localhost:${PORTA}/`;
const servidor = spawn("npx", ["vite", "preview", "--port", String(PORTA), "--strictPort"], { stdio: "ignore" });
const ROTAS = [
  ["Hoje", "#/hoje", ".cabecalho-tela h1"],
  ["Calendário", "#/calendario", ".dia-cal"],
  ["Todas", "#/todas", ".cabecalho-tela h1"],
  ["Concluídas", "#/concluidas", ".cabecalho-tela h1"],
  ["Despejo", "#/despejo", ".campo-despejo"],
  ["Notas", "#/notas", ".lista-notas h1"],
  ["Ajustes", "#/ajustes", ".pasta"],
];

const linhas = [];
try {
  for (let i = 0; i < 50; i++) { try { await fetch(BASE); break; } catch { await new Promise((r) => setTimeout(r, 200)); } }
  const nav = await playwright.chromium.launch();
  const ctx = await nav.newContext({ serviceWorkers: "block", viewport: { width: 390, height: 844 } });
  const p = await ctx.newPage();
  const cdp = await ctx.newCDPSession(p);
  await cdp.send("Network.enable");
  await cdp.send("Network.emulateNetworkConditions", { offline: false, latency: 150, downloadThroughput: (1.6 * 1024 * 1024) / 8, uploadThroughput: (750 * 1024) / 8 });
  // Entra sem conta uma vez (a primeira abertura de verdade é a da tela de entrar).
  await p.goto(BASE);
  await p.getByRole("button", { name: "Começar" }).click();
  for (const rodada of ["primeira", "volta"]) {
    for (const [nome, rota, seletor] of ROTAS) {
      if (rodada === "primeira") await cdp.send("Network.clearBrowserCache");
      let pedidos = 0, bytes = 0;
      const contar = (r) => { pedidos++; };
      const pesar = (e) => { bytes += e.encodedDataLength ?? 0; };
      p.on("request", contar);
      cdp.on("Network.loadingFinished", pesar);
      const t0 = Date.now();
      await p.goto(BASE + rota);
      await p.reload();
      await p.locator(seletor).first().waitFor({ timeout: 60_000 });
      const ms = Date.now() - t0;
      p.off("request", contar);
      cdp.off("Network.loadingFinished", pesar);
      linhas.push({ rodada, nome, ms, pedidos, kb: Math.round(bytes / 1024) });
      console.log(`${rodada.padEnd(9)} ${nome.padEnd(12)} ${String(ms).padStart(6)} ms  ${pedidos} pedidos  ${Math.round(bytes / 1024)} KB`);
    }
  }
  await nav.close();
} finally {
  servidor.kill();
}
mkdirSync("e2e/capturas", { recursive: true });
const tabela = ["| Rodada | Tela | Tempo até o conteúdo | Pedidos | KB |", "| --- | --- | ---: | ---: | ---: |",
  ...linhas.map((l) => `| ${l.rodada} | ${l.nome} | ${(l.ms / 1000).toFixed(2)} s | ${l.pedidos} | ${l.kb} |`)].join("\n");
writeFileSync("e2e/capturas/desempenho.md", `# Desempenho no 4G fraco\n\n${tabela}\n`);
