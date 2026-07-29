// Minimal, safe service worker for PWA installability.
//
// IMPORTANT: only intercept top-level PAGE NAVIGATIONS. Everything else — JS
// chunks, the PowerSync SQLite WASM + web worker, and all cross-origin API calls
// (Supabase, PowerSync) — is left to the browser untouched. Intercepting those
// and (previously) falling back to the HTML shell on any failure caused the
// installed PWA to hang: the DB worker/WASM would be served the wrong response
// and PowerSync never finished initializing.
const CACHE = "pocketcare-v5";

// Static assets that must survive going offline. The icon font is the important
// one: it's self-hosted precisely so the navigation still renders icons with no
// network, and the fetch handler below serves it cache-first.
const ASSETS = ["/fonts/pocketcare-icons.woff2", "/vendor/qrcode.min.js"];

// Top-level app routes precached so they load (offline) as their OWN page
// instead of bouncing to the dashboard. Dynamic routes (e.g. /transactions/[id])
// aren't precached; those need a connection the first time.
const ROUTES = [
  "/", "/accounts", "/transactions", "/transactions/new", "/search", "/cards",
  "/budgets", "/insights", "/statements", "/goals", "/subscriptions", "/loans",
  "/investments", "/settings",
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) =>
      Promise.all(
        [...ROUTES, ...ASSETS].map((r) => fetch(r, { credentials: "same-origin" })
          .then((res) => { if (res.ok) return c.put(r, res); })
          .catch(() => {})),
      ),
    ).then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

// --- Web Push ---------------------------------------------------------------
// The edge function sends a JSON payload { title, body, href, tag }. We show it
// as an OS notification even when the app is fully closed (browser must be
// running in the background — "lock the app in the background to get alerts").
self.addEventListener("push", (e) => {
  let payload = {};
  try { payload = e.data ? e.data.json() : {}; } catch { payload = { title: "PocketCare", body: e.data && e.data.text ? e.data.text() : "" }; }
  const title = payload.title || "PocketCare";
  const options = {
    body: payload.body || "",
    tag: payload.tag || payload.dedupe_key || undefined,
    data: { href: payload.href || "/notifications" },
    icon: "/icon-192.png",
    badge: "/icon-192.png",
    renotify: !!payload.tag,
  };
  e.waitUntil(self.registration.showNotification(title, options));
});

// Focus an existing tab (or open one) and navigate to the notification's link.
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const href = (e.notification.data && e.notification.data.href) || "/notifications";
  e.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if ("focus" in c) { c.navigate(href).catch(() => {}); return c.focus(); }
      }
      return self.clients.openWindow(href);
    }),
  );
});

self.addEventListener("fetch", (e) => {
  const { request } = e;
  if (request.method !== "GET") return;
  if (new URL(request.url).origin !== self.location.origin) return;

  // Self-hosted static assets (icon font, QR encoder): cache-first, so the
  // nav renders icons and a payment QR can be drawn with no network.
  // Scoped tightly to /fonts/ — scripts, wasm and the DB worker must NOT be
  // intercepted (doing so previously hung the installed PWA).
  const path = new URL(request.url).pathname;
  if (path.startsWith("/fonts/") || path.startsWith("/vendor/")) {
    e.respondWith(
      caches.match(request).then((hit) => hit || fetch(request).then((res) => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(request, copy)).catch(() => {}); }
        return res;
      })),
    );
    return;
  }

  // Otherwise only handle top-level navigations. Let the browser natively
  // handle scripts, wasm, workers, images, and every cross-origin request.
  if (request.mode !== "navigate") return;

  e.respondWith(
    fetch(request)
      .then((res) => {
        // Cache each page under its OWN url so offline navigation serves the
        // right page (not always the dashboard). SPA data comes from local SQLite.
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(request, copy)).catch(() => {});
        return res;
      })
      // Offline: serve this page's cached shell; fall back to the app root.
      .catch(() => caches.match(request, { ignoreSearch: true }).then((r) => r || caches.match("/")).then((r) => r || Response.error())),
  );
});
