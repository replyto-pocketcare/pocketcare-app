// Minimal, safe service worker for PWA installability.
//
// IMPORTANT: only intercept top-level PAGE NAVIGATIONS. Everything else — JS
// chunks, the PowerSync SQLite WASM + web worker, and all cross-origin API calls
// (Supabase, PowerSync) — is left to the browser untouched. Intercepting those
// and (previously) falling back to the HTML shell on any failure caused the
// installed PWA to hang: the DB worker/WASM would be served the wrong response
// and PowerSync never finished initializing.
const CACHE = "pocketcare-v2";

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.add("/")).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (e) => {
  const { request } = e;
  // Only handle same-origin top-level navigations. Let the browser natively
  // handle scripts, wasm, workers, images, and every cross-origin request.
  if (request.method !== "GET" || request.mode !== "navigate") return;
  if (new URL(request.url).origin !== self.location.origin) return;

  e.respondWith(
    fetch(request)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put("/", copy)).catch(() => {});
        return res;
      })
      // Offline: fall back to the cached app shell (SPA still works via local SQLite).
      .catch(() => caches.match("/").then((r) => r || Response.error())),
  );
});
