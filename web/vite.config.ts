import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Caminhos relativos: o mesmo build roda na Vercel, como PWA e empacotado dentro do app do Mac (sem servidor).
export default defineConfig({
  base: "./",
  plugins: [react()],
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
