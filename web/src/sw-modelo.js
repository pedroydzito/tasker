// Service worker do Tasker (gerado no build: versão e lista da casca entram aqui).
// Regras (appdocs operação): casca cache-first e versionada; navegação devolve o index.html do cache
// (abre offline); nunca guarda resposta redirecionada; API, Supabase e Google nunca passam pelo cache;
// a versão nova espera "na porta" e só assume quando a página pede (SKIP_WAITING).
const VERSAO = "tasker-__VERSAO__";
const CASCA = __ARQUIVOS__;

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(VERSAO).then((c) => c.addAll(CASCA)));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((ks) => Promise.all(ks.filter((k) => k.startsWith("tasker-") && k !== VERSAO).map((k) => caches.delete(k)))).then(() => self.clients.claim()),
  );
});

self.addEventListener("message", (e) => {
  if (e.data === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // Supabase, Google: sempre rede
  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then((r) => (r.ok && !r.redirected ? r : caches.match("./index.html").then((c) => c || r)))
        .catch(() => caches.match("./index.html", { ignoreSearch: true })),
    );
    return;
  }
  e.respondWith(
    caches.match(req).then(
      (c) =>
        c ||
        fetch(req).then((r) => {
          if (r.ok && !r.redirected && r.type === "basic" && /\/(assets|fonts|icones)\//.test(url.pathname)) {
            const copia = r.clone();
            caches.open(VERSAO).then((cache) => cache.put(req, copia));
          }
          return r;
        }),
    ),
  );
});
