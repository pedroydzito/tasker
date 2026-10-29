// Service worker do Tasker (gerado no build: versão e lista da casca entram aqui).
// Regras (appdocs operação): casca cache-first e versionada; navegação devolve o index.html do cache
// (abre offline); nunca guarda resposta redirecionada; API, Supabase e Google nunca passam pelo cache;
// a versão nova espera "na porta" e só assume quando a página pede (SKIP_WAITING).
const VERSAO = "tasker-__VERSAO__";
const CASCA = __ARQUIVOS__;

self.addEventListener("install", (e) => {
  // Um arquivo que falhe não derruba a instalação inteira (§8.7): cada um é tentado sozinho.
  e.waitUntil(caches.open(VERSAO).then((c) => Promise.all(CASCA.map((u) => c.add(u).catch(() => {})))));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((ks) => Promise.all(ks.filter((k) => k.startsWith("tasker-") && k !== VERSAO).map((k) => caches.delete(k)))).then(() => self.clients.claim()).catch(() => {}),
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
    // A casca guardada responde NA HORA (a abertura não espera a rede); a rede atualiza o cache
    // atrás, e a próxima abertura já vem nova. Resposta redirecionada nunca entra no cache.
    e.respondWith(
      caches.match("./index.html").then((guardada) => {
        const daRede = fetch(req)
          .then((r) => {
            if (r.ok && !r.redirected && r.type === "basic") {
              const copia = r.clone();
              caches.open(VERSAO).then((c) => c.put("./index.html", copia)).catch(() => {});
            }
            return r;
          })
          .catch(() => guardada);
        if (guardada) {
          e.waitUntil(daRede.catch(() => {}));
          return guardada;
        }
        return daRede;
      }),
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
