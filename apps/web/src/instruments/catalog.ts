/**
 * Instruments catalog — the searchable universe of stocks/ETFs behind the
 * investments picker.
 *
 * PocketCare is offline-first, so the catalog is designed around a *local*
 * cache that never touches PowerSync (it is global reference data, not user
 * data, and can be tens of thousands of rows). The cache lives in IndexedDB and
 * is refreshed at most once a day from a configurable JSON source. A bundled
 * seed of the most-traded symbols ships with the app so the picker works
 * immediately — even on a brand-new install with no network.
 */

export interface Instrument {
  symbol: string; // ticker, upper-cased (e.g. "AAPL", "RELIANCE")
  name: string; // company / fund name
  exchange: string; // MIC-ish label (e.g. "NASDAQ", "NSE", "LSE")
  currency: string; // ISO 4217 the instrument trades in
}

/** Stable key so the same ticker on two exchanges stays distinct. */
export const instrumentKey = (i: Pick<Instrument, "symbol" | "exchange">) =>
  `${i.symbol.toUpperCase()}|${i.exchange.toUpperCase()}`;

// ---- bundled seed (always available offline) --------------------------------
// A compact, high-coverage starter set across the exchanges most PocketCare
// users hold. The daily fetch augments/replaces this with the full universe.
export const SEED: Instrument[] = [
  // United States — NASDAQ
  { symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "MSFT", name: "Microsoft Corp.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "NVDA", name: "NVIDIA Corp.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "AMZN", name: "Amazon.com Inc.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "GOOGL", name: "Alphabet Inc. Class A", exchange: "NASDAQ", currency: "USD" },
  { symbol: "META", name: "Meta Platforms Inc.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "TSLA", name: "Tesla Inc.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "AVGO", name: "Broadcom Inc.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "COST", name: "Costco Wholesale Corp.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "NFLX", name: "Netflix Inc.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "AMD", name: "Advanced Micro Devices Inc.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "PEP", name: "PepsiCo Inc.", exchange: "NASDAQ", currency: "USD" },
  { symbol: "QQQ", name: "Invesco QQQ Trust", exchange: "NASDAQ", currency: "USD" },
  // United States — NYSE
  { symbol: "BRK.B", name: "Berkshire Hathaway Inc. Class B", exchange: "NYSE", currency: "USD" },
  { symbol: "JPM", name: "JPMorgan Chase & Co.", exchange: "NYSE", currency: "USD" },
  { symbol: "V", name: "Visa Inc.", exchange: "NYSE", currency: "USD" },
  { symbol: "MA", name: "Mastercard Inc.", exchange: "NYSE", currency: "USD" },
  { symbol: "JNJ", name: "Johnson & Johnson", exchange: "NYSE", currency: "USD" },
  { symbol: "WMT", name: "Walmart Inc.", exchange: "NYSE", currency: "USD" },
  { symbol: "XOM", name: "Exxon Mobil Corp.", exchange: "NYSE", currency: "USD" },
  { symbol: "PG", name: "Procter & Gamble Co.", exchange: "NYSE", currency: "USD" },
  { symbol: "KO", name: "Coca-Cola Co.", exchange: "NYSE", currency: "USD" },
  { symbol: "DIS", name: "Walt Disney Co.", exchange: "NYSE", currency: "USD" },
  { symbol: "BAC", name: "Bank of America Corp.", exchange: "NYSE", currency: "USD" },
  { symbol: "SPY", name: "SPDR S&P 500 ETF Trust", exchange: "NYSE", currency: "USD" },
  { symbol: "VOO", name: "Vanguard S&P 500 ETF", exchange: "NYSE", currency: "USD" },
  // India — NSE
  { symbol: "RELIANCE", name: "Reliance Industries Ltd.", exchange: "NSE", currency: "INR" },
  { symbol: "TCS", name: "Tata Consultancy Services Ltd.", exchange: "NSE", currency: "INR" },
  { symbol: "HDFCBANK", name: "HDFC Bank Ltd.", exchange: "NSE", currency: "INR" },
  { symbol: "INFY", name: "Infosys Ltd.", exchange: "NSE", currency: "INR" },
  { symbol: "ICICIBANK", name: "ICICI Bank Ltd.", exchange: "NSE", currency: "INR" },
  { symbol: "BHARTIARTL", name: "Bharti Airtel Ltd.", exchange: "NSE", currency: "INR" },
  { symbol: "SBIN", name: "State Bank of India", exchange: "NSE", currency: "INR" },
  { symbol: "ITC", name: "ITC Ltd.", exchange: "NSE", currency: "INR" },
  { symbol: "LT", name: "Larsen & Toubro Ltd.", exchange: "NSE", currency: "INR" },
  { symbol: "HINDUNILVR", name: "Hindustan Unilever Ltd.", exchange: "NSE", currency: "INR" },
  { symbol: "NIFTYBEES", name: "Nippon India Nifty 50 BeES ETF", exchange: "NSE", currency: "INR" },
  // India — BSE (dual-listed names commonly held)
  { symbol: "500325", name: "Reliance Industries Ltd.", exchange: "BSE", currency: "INR" },
  { symbol: "532540", name: "Tata Consultancy Services Ltd.", exchange: "BSE", currency: "INR" },
  // United Kingdom — LSE
  { symbol: "HSBA", name: "HSBC Holdings plc", exchange: "LSE", currency: "GBP" },
  { symbol: "AZN", name: "AstraZeneca plc", exchange: "LSE", currency: "GBP" },
  { symbol: "SHEL", name: "Shell plc", exchange: "LSE", currency: "GBP" },
  { symbol: "ULVR", name: "Unilever plc", exchange: "LSE", currency: "GBP" },
  { symbol: "BP", name: "BP plc", exchange: "LSE", currency: "GBP" },
  { symbol: "VUSA", name: "Vanguard S&P 500 UCITS ETF", exchange: "LSE", currency: "GBP" },
  // Europe
  { symbol: "ASML", name: "ASML Holding N.V.", exchange: "AMS", currency: "EUR" },
  { symbol: "MC", name: "LVMH Moët Hennessy Louis Vuitton", exchange: "EPA", currency: "EUR" },
  { symbol: "SAP", name: "SAP SE", exchange: "XETRA", currency: "EUR" },
  { symbol: "SIE", name: "Siemens AG", exchange: "XETRA", currency: "EUR" },
  { symbol: "NESN", name: "Nestlé S.A.", exchange: "SWX", currency: "CHF" },
  // Asia-Pacific
  { symbol: "7203", name: "Toyota Motor Corp.", exchange: "TSE", currency: "JPY" },
  { symbol: "9984", name: "SoftBank Group Corp.", exchange: "TSE", currency: "JPY" },
  { symbol: "0700", name: "Tencent Holdings Ltd.", exchange: "HKEX", currency: "HKD" },
  { symbol: "9988", name: "Alibaba Group Holding Ltd.", exchange: "HKEX", currency: "HKD" },
  { symbol: "BHP", name: "BHP Group Ltd.", exchange: "ASX", currency: "AUD" },
  { symbol: "CBA", name: "Commonwealth Bank of Australia", exchange: "ASX", currency: "AUD" },
  // Canada
  { symbol: "RY", name: "Royal Bank of Canada", exchange: "TSX", currency: "CAD" },
  { symbol: "SHOP", name: "Shopify Inc.", exchange: "TSX", currency: "CAD" },
];

/** All distinct exchanges present in the current catalog (seed + cache). */
export function knownExchanges(list: Instrument[]): string[] {
  return Array.from(new Set(list.map((i) => i.exchange))).sort();
}

// ---- IndexedDB cache --------------------------------------------------------
const DB_NAME = "pocketcare-instruments";
const STORE = "catalog";
const META = "meta";
const REFRESH_MS = 24 * 60 * 60 * 1000; // once a day
// Point this at a CORS-enabled JSON endpoint that returns Instrument[] (or a
// superset with symbol/name/exchange/currency fields). Left empty by default so
// installs stay fully offline until a source is configured.
const SOURCE_URL = process.env.NEXT_PUBLIC_INSTRUMENTS_URL ?? "";

function openDb(): Promise<IDBDatabase | null> {
  return new Promise((resolve) => {
    if (typeof indexedDB === "undefined") return resolve(null);
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE, { keyPath: "key" });
      if (!db.objectStoreNames.contains(META)) db.createObjectStore(META);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => resolve(null);
  });
}

function idbGetAll(db: IDBDatabase): Promise<Instrument[]> {
  return new Promise((resolve) => {
    const req = db.transaction(STORE, "readonly").objectStore(STORE).getAll();
    req.onsuccess = () => resolve((req.result as Array<Instrument & { key: string }>).map(({ key: _k, ...rest }) => rest));
    req.onerror = () => resolve([]);
  });
}

function idbMeta<T>(db: IDBDatabase, key: string): Promise<T | undefined> {
  return new Promise((resolve) => {
    const req = db.transaction(META, "readonly").objectStore(META).get(key);
    req.onsuccess = () => resolve(req.result as T | undefined);
    req.onerror = () => resolve(undefined);
  });
}

function idbReplace(db: IDBDatabase, rows: Instrument[], fetchedAt: number): Promise<void> {
  return new Promise((resolve) => {
    const tx = db.transaction([STORE, META], "readwrite");
    const store = tx.objectStore(STORE);
    store.clear();
    for (const r of rows) store.put({ ...r, key: instrumentKey(r) });
    tx.objectStore(META).put(fetchedAt, "fetchedAt");
    tx.oncomplete = () => resolve();
    tx.onerror = () => resolve();
  });
}

// In-memory working copy (seed merged with whatever the cache holds).
let memo: Instrument[] | null = null;

function mergeSeed(rows: Instrument[]): Instrument[] {
  const byKey = new Map<string, Instrument>();
  for (const r of SEED) byKey.set(instrumentKey(r), r);
  for (const r of rows) byKey.set(instrumentKey(r), r); // cache wins on conflicts
  return Array.from(byKey.values());
}

/** Load the catalog into memory (cache ∪ seed), reading IndexedDB once. */
export async function loadCatalog(): Promise<Instrument[]> {
  if (memo) return memo;
  const db = await openDb();
  const cached = db ? await idbGetAll(db) : [];
  memo = mergeSeed(cached);
  return memo;
}

/**
 * Refresh the catalog from the configured source at most once per day. Safe to
 * fire-and-forget on app open — no-ops offline, on error, or when no source is
 * configured, always leaving the seed usable.
 */
export async function refreshCatalog(force = false): Promise<void> {
  if (!SOURCE_URL) return;
  if (typeof navigator !== "undefined" && navigator.onLine === false) return;
  const db = await openDb();
  if (!db) return;
  const last = (await idbMeta<number>(db, "fetchedAt")) ?? 0;
  if (!force && Date.now() - last < REFRESH_MS) return;
  try {
    const res = await fetch(SOURCE_URL, { headers: { accept: "application/json" } });
    if (!res.ok) return;
    const raw = (await res.json()) as unknown;
    const rows = normalize(raw);
    if (rows.length === 0) return;
    await idbReplace(db, rows, Date.now());
    memo = mergeSeed(rows); // refresh in-memory copy
  } catch {
    /* offline / blocked / malformed — keep prior cache + seed */
  }
}

function normalize(raw: unknown): Instrument[] {
  if (!Array.isArray(raw)) return [];
  const out: Instrument[] = [];
  for (const r of raw as Array<Record<string, unknown>>) {
    const symbol = String(r.symbol ?? r.ticker ?? r.code ?? "").trim().toUpperCase();
    const exchange = String(r.exchange ?? r.exchangeShortName ?? r.mic ?? "").trim().toUpperCase();
    if (!symbol || !exchange) continue;
    out.push({
      symbol,
      exchange,
      name: String(r.name ?? r.companyName ?? symbol).trim(),
      currency: String(r.currency ?? r.currencyCode ?? "").trim().toUpperCase() || "USD",
    });
  }
  return out;
}

/**
 * Search the catalog. Matches symbol or name (case-insensitive), optionally
 * scoped to one exchange. Exact-symbol matches are ranked first.
 */
export async function searchInstruments(query: string, exchange: string | null, limit = 30): Promise<Instrument[]> {
  const all = await loadCatalog();
  const scoped = exchange ? all.filter((i) => i.exchange === exchange) : all;
  const q = query.trim().toLowerCase();
  if (!q) return scoped.slice(0, limit);
  const scored: Array<{ i: Instrument; s: number }> = [];
  for (const i of scoped) {
    const sym = i.symbol.toLowerCase();
    const name = i.name.toLowerCase();
    let s = -1;
    if (sym === q) s = 0;
    else if (sym.startsWith(q)) s = 1;
    else if (name.startsWith(q)) s = 2;
    else if (sym.includes(q) || name.includes(q)) s = 3;
    if (s >= 0) scored.push({ i, s });
  }
  scored.sort((a, b) => a.s - b.s || a.i.symbol.localeCompare(b.i.symbol));
  return scored.slice(0, limit).map((x) => x.i);
}
