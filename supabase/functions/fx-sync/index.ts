// PocketCare — daily FX rate sync.
//
// Populates the global `exchange_rates` table so the app can convert every
// account's native currency into the user's base currency (net worth,
// subscriptions, planned cashflow, dashboard). Without this, unknown pairs fall
// back to par (1:1) and "changing base currency only changes the sign".
//
// Fetches USD-based rates from a free provider (open.er-api.com — no key needed;
// swap for a keyed provider via FX_PROVIDER_URL if you prefer) and upserts every
// cross pair among the supported currencies for today's date.
//
// Deploy:   supabase functions deploy fx-sync
// Schedule: run once daily (e.g. Supabase scheduled function / cron → POST here).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });

// Currencies the app offers (keep in sync with the account-creation picker).
const CURRENCIES = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const providerUrl = Deno.env.get("FX_PROVIDER_URL") ?? "https://open.er-api.com/v6/latest/USD";
    const res = await fetch(providerUrl);
    if (!res.ok) return json({ error: `FX provider ${res.status}` }, 502);
    const data = await res.json();
    // open.er-api.com → { result:'success', rates: { USD:1, INR:83.1, EUR:0.92, ... } }
    const usd: Record<string, number> = data.rates ?? data.conversion_rates ?? {};
    if (!usd.USD) return json({ error: "unexpected FX payload", sample: Object.keys(usd).slice(0, 5) }, 502);

    const asOf = new Date().toISOString().slice(0, 10);
    const rows: { base_currency: string; quote_currency: string; rate: number; as_of: string }[] = [];
    for (const from of CURRENCIES) {
      for (const to of CURRENCIES) {
        if (from === to) continue;
        const rf = usd[from], rt = usd[to];
        if (!rf || !rt) continue;
        // from → to = (USD→to) / (USD→from)
        rows.push({ base_currency: from, quote_currency: to, rate: rt / rf, as_of: asOf });
      }
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { db: { schema: "pocketcare" } },
    );
    const { error } = await supabase
      .from("exchange_rates")
      .upsert(rows, { onConflict: "base_currency,quote_currency,as_of" });
    if (error) return json({ error: error.message }, 500);

    return json({ ok: true, as_of: asOf, pairs: rows.length });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
