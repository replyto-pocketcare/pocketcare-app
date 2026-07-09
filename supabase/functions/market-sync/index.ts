// PocketCare — collective Alpha Vantage market-data sync.
//
// Runs once a day (see MARKET_DATA_PLAN.md for scheduling). Spends a shared
// 25-call/day budget on the DEDUPLICATED union of symbols held across ALL users,
// ordered by how stale each one is, and writes the results into global tables
// that every client reads. The API key never leaves the server.
//
// Secrets: ALPHAVANTAGE_API_KEY (required), optional AV_DAILY_BUDGET (default 25).
// Deploy: supabase functions deploy market-sync
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const AV = "https://www.alphavantage.co/query";

// Exchange code -> Alpha Vantage symbol suffix. US venues use the bare ticker.
const AV_SUFFIX: Record<string, string> = {
  NASDAQ: "", NYSE: "", "NYSE ARCA": "", "NYSE MKT": "", "NYSE AMERICAN": "", AMEX: "", BATS: "", OTC: "",
  LSE: ".LON", XETRA: ".DEX", FSE: ".FRK", BSE_IN: ".BSE", NSE_IN: ".BSE", TSX: ".TRT", TSXV: ".TRV",
  ASX: ".AX", SIX: ".SWI", SWX: ".SWI",
};
const CCY_BY_EXCHANGE: Record<string, string> = {
  NASDAQ: "USD", NYSE: "USD", "NYSE ARCA": "USD", AMEX: "USD", OTC: "USD",
  LSE: "GBP", XETRA: "EUR", FSE: "EUR", BSE_IN: "INR", NSE_IN: "INR", TSX: "CAD", TSXV: "CAD",
  ASX: "AUD", SWX: "CHF", SIX: "CHF",
};

function avSymbol(symbol: string, exchange: string): string {
  const suffix = AV_SUFFIX[exchange.toUpperCase()];
  // Unknown venue → send the bare ticker (works for most US listings).
  return suffix === undefined ? symbol : symbol + suffix;
}
function toMinor(major: number): number {
  return Math.round(major * 100);
}
// Alpha Vantage signals throttling / errors via these keys instead of HTTP codes.
function throttled(payload: Record<string, unknown>): boolean {
  return typeof payload["Note"] === "string" || typeof payload["Information"] === "string";
}

async function avGet(fn: string, symbol: string, key: string, extra: Record<string, string> = {}) {
  const params = new URLSearchParams({ function: fn, symbol, apikey: key, ...extra });
  const res = await fetch(`${AV}?${params.toString()}`);
  if (!res.ok) return { ok: false as const, throttled: false, data: {} as Record<string, unknown> };
  const data = (await res.json()) as Record<string, unknown>;
  return { ok: true as const, throttled: throttled(data), data };
}

interface SymRow { symbol: string; exchange: string; av_symbol: string; currency: string | null }

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey = Deno.env.get("ALPHAVANTAGE_API_KEY");
  if (!url || !serviceKey) return json({ error: "Supabase env not configured." }, 500);
  if (!apiKey) return json({ error: "ALPHAVANTAGE_API_KEY not set." }, 500);

  const budget = Math.max(1, Number(Deno.env.get("AV_DAILY_BUDGET") ?? "25"));
  const db = createClient(url, serviceKey, { db: { schema: "pocketcare" } });

  // 1) Refresh demand: which symbols does anyone hold, and how many holders?
  const { data: holds } = await db.from("holdings").select("symbol, exchange").is("deleted_at", null);
  const demand = new Map<string, { symbol: string; exchange: string; holders: number }>();
  for (const h of holds ?? []) {
    const symbol = String((h as { symbol?: string }).symbol ?? "").toUpperCase();
    const exchange = String((h as { exchange?: string }).exchange ?? "").toUpperCase();
    if (!symbol) continue;
    const k = `${symbol}|${exchange}`;
    const cur = demand.get(k) ?? { symbol, exchange, holders: 0 };
    cur.holders++;
    demand.set(k, cur);
  }
  for (const d of demand.values()) {
    await db.from("market_symbols").upsert(
      {
        symbol: d.symbol, exchange: d.exchange, av_symbol: avSymbol(d.symbol, d.exchange),
        currency: CCY_BY_EXCHANGE[d.exchange] ?? null, holders: d.holders, active: true, updated_at: new Date().toISOString(),
      },
      { onConflict: "symbol,exchange" },
    );
  }

  // 2) Budget split (prices prioritised; spare spills to dividends/overview).
  let priceN = Math.min(20, Math.ceil(budget * 0.8));
  let divN = Math.min(3, Math.max(0, Math.floor(budget * 0.12)));
  let ovN = Math.max(0, budget - priceN - divN);

  const pick = async (col: string, n: number): Promise<SymRow[]> => {
    if (n <= 0) return [];
    const { data } = await db.from("market_symbols")
      .select("symbol, exchange, av_symbol, currency")
      .eq("active", true)
      .order(col, { ascending: true, nullsFirst: true })
      .order("holders", { ascending: false })
      .limit(n);
    return (data ?? []) as SymRow[];
  };

  let used = 0;
  let stop = false;
  const results = { prices: 0, dividends: 0, overview: 0, throttled: false, symbols: demand.size };

  // 3) Prices — TIME_SERIES_DAILY gives latest close + recent history in one call.
  for (const s of await pick("last_price_sync", priceN)) {
    if (used >= budget || stop) break;
    used++;
    const r = await avGet("TIME_SERIES_DAILY", s.av_symbol, apiKey, { outputsize: "compact" });
    if (r.throttled) { stop = true; results.throttled = true; break; }
    const series = r.data["Time Series (Daily)"] as Record<string, Record<string, string>> | undefined;
    if (series) {
      const days = Object.keys(series).sort().reverse();
      const latest = days[0], prev = days[1];
      if (latest) {
        const close = toMinor(Number(series[latest]?.["4. close"] ?? 0));
        const prevClose = prev ? toMinor(Number(series[prev]?.["4. close"] ?? 0)) : null;
        const currency = s.currency ?? "USD";
        await db.from("market_quotes").upsert({
          symbol: s.symbol, exchange: s.exchange, price: close, currency,
          change_abs: prevClose != null ? close - prevClose : null,
          change_pct: prevClose ? ((close - prevClose) / prevClose) * 100 : null,
          as_of: latest, updated_at: new Date().toISOString(),
        }, { onConflict: "symbol,exchange" });
        // Keep a compact price-history trail (upsert recent closes).
        for (const day of days.slice(0, 30)) {
          const px = toMinor(Number(series[day]?.["4. close"] ?? 0));
          if (px > 0) await db.from("price_snapshots").upsert({ symbol: s.symbol, price: px, currency, as_of: day }, { onConflict: "symbol,as_of" });
        }
      }
    }
    await db.from("market_symbols").update({ last_price_sync: new Date().toISOString() }).eq("symbol", s.symbol).eq("exchange", s.exchange);
    results.prices++;
    await sleep(1200);
  }
  // spare price budget spills forward
  ovN += Math.max(0, priceN - results.prices);

  // 4) Dividends.
  if (!stop) for (const s of await pick("last_dividend_sync", divN)) {
    if (used >= budget || stop) break;
    used++;
    const r = await avGet("DIVIDENDS", s.av_symbol, apiKey);
    if (r.throttled) { stop = true; results.throttled = true; break; }
    const rows = (r.data["data"] as Array<Record<string, string>> | undefined) ?? [];
    const currency = s.currency ?? "USD";
    for (const d of rows.slice(0, 40)) {
      const ex = d["ex_dividend_date"];
      const amt = Number(d["amount"]);
      if (!ex || !Number.isFinite(amt) || amt <= 0) continue;
      await db.from("market_dividends").upsert({
        symbol: s.symbol, exchange: s.exchange, ex_date: ex, pay_date: d["payment_date"] || null,
        amount: toMinor(amt), currency, updated_at: new Date().toISOString(),
      }, { onConflict: "symbol,exchange,ex_date" });
    }
    await db.from("market_symbols").update({ last_dividend_sync: new Date().toISOString() }).eq("symbol", s.symbol).eq("exchange", s.exchange);
    results.dividends++;
    await sleep(1200);
  }

  // 5) Fundamentals (OVERVIEW).
  if (!stop) for (const s of await pick("last_overview_sync", ovN)) {
    if (used >= budget || stop) break;
    used++;
    const r = await avGet("OVERVIEW", s.av_symbol, apiKey);
    if (r.throttled) { stop = true; results.throttled = true; break; }
    const d = r.data;
    if (d && d["Symbol"]) {
      const num = (k: string) => { const v = Number(d[k]); return Number.isFinite(v) ? v : null; };
      await db.from("market_overview").upsert({
        symbol: s.symbol, exchange: s.exchange,
        name: (d["Name"] as string) || null, sector: (d["Sector"] as string) || null, industry: (d["Industry"] as string) || null,
        currency: (d["Currency"] as string) || s.currency || null,
        pe: num("PERatio"), eps: num("EPS"),
        dividend_yield: num("DividendYield"), dividend_per_share: num("DividendPerShare"),
        ex_dividend_date: (d["ExDividendDate"] && d["ExDividendDate"] !== "None") ? (d["ExDividendDate"] as string) : null,
        updated_at: new Date().toISOString(),
      }, { onConflict: "symbol,exchange" });
    }
    await db.from("market_symbols").update({ last_overview_sync: new Date().toISOString() }).eq("symbol", s.symbol).eq("exchange", s.exchange);
    results.overview++;
    await sleep(1200);
  }

  return json({ ok: true, used, budget, ...results });
});
