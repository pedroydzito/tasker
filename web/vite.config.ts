import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

/** Gera o sw.js com a lista do que é a casca e uma versão que muda a cada build (operação: SW versionado). */
function serviceWorker(): Plugin {
  return {
    name: "tasker-sw",
    apply: "build",
    generateBundle(_, bundle) {
      const arquivos = [...new Set(["./", "./index.html", "./manifest.webmanifest", "./fonts/geist.woff2", "./fonts/bricolage-700.woff2", "./icones/icone.svg", "./icones/icone-192.png",
        ...Object.keys(bundle).filter((f) => !f.endsWith(".map")).map((f) => "./" + f)])];
      const versao = createHash("sha1").update(arquivos.join("|")).digest("hex").slice(0, 10);
      const modelo = readFileSync(new URL("./src/sw-modelo.js", import.meta.url), "utf8");
      this.emitFile({ type: "asset", fileName: "sw.js", source: modelo.replace("__VERSAO__", versao).replace("__ARQUIVOS__", JSON.stringify(arquivos)) });
    },
  };
}

// Caminhos relativos: o mesmo build roda na Vercel, como PWA e empacotado dentro do app do Mac (sem servidor).
export default defineConfig({
  base: "./",
  // A versão que a interface mostra é a do package.json (o build cobra pela nota de novidades).
  define: { "import.meta.env.VITE_VERSAO": JSON.stringify(JSON.parse(readFileSync(new URL("./package.json", import.meta.url), "utf8")).version) },
  plugins: [react(), serviceWorker()],
  build: {
    target: "es2022",
    sourcemap: false,
    rollupOptions: {
      output: {
        manualChunks: {
          supabase: ["@supabase/supabase-js"],
        },
      },
    },
  },
  test: { environment: "node", include: ["src/**/*.test.ts"] },
});
