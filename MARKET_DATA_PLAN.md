# Market data (Alpha Vantage) — plan & reference

Goal: enrich investments with **end-of-day prices, dividends, and fundamentals**, then use those for portfolio valuation, dividend tracking, and future-wealth projection — all on Alpha Vantage's **free tier**.

## The constraint that shapes everything

Alpha Vantage free tier = **25 API requests / day**, **end-of-day only** (realtime & 15-min US quotes are premium). One API key. So we do NOT fetch per-user or per-device. Instead:

> **Collective server-side sync.** One daily job spends the 25-call budget on the *deduplicated union* of symbols held across **all** users, ordered by demand, and stores the results in **global tables** that every client reads (via PowerSync). 25 calls thus cover everyone's overlapping holdings.

The key lives only on the server (Supabase function secret `ALPHAVANTAGE_API_KEY`) — never shipped to the browser.

## Daily 25-call budget (per run)

| Bucket | Calls | Endpoint | Why |
|---|---|---|---|
| Prices | up to 20 | `TIME_SERIES_DAILY` (compact) | latest close **and** ~100-day history in one call; round-robin by `last_price_sync` |
| Dividends | up to 3 | `DIVIDENDS` | ex/pay dates + amounts; changes rarely → round-robin by `last_dividend_sync` |
| Fundamentals | up to 2 | `OVERVIEW` | yield, EPS, PE, sector, ex-date; round-robin by `last_overview_sync` |

Buckets shrink if there are fewer symbols; unused price budget spills into dividends/overview. Symbols are ordered `last_*_sync ASC NULLS FIRST`, so the least-recently-updated always go first — every symbol is refreshed on a rotating cadence. With N held symbols, each price refreshes every `ceil(N/20)` days. The job stops early if Alpha Vantage returns a throttle note.

## Symbol mapping

Alpha Vantage uses US tickers plain (`AAPL`) and suffixes for some venues (`RELIANCE.BSE`, `TESCO.LON`). `market_symbols.av_symbol` stores the exact string to send; `CCY_BY_EXCHANGE` in the client already maps exchange→currency. Coverage for non-US venues on free tier is partial — misses are recorded and skipped, not retried tightly.

## Schema (migration 0020) — all global reference data

- `market_symbols` (internal, service-role only): demand registry + round-robin timestamps (`holders`, `last_price_sync`, `last_dividend_sync`, `last_overview_sync`, `av_symbol`).
- `market_quotes` (synced): latest EOD `price` (minor units), `change_abs`, `change_pct`, `as_of` per `(symbol, exchange)`.
- `price_snapshots` (existing, synced): daily close history keyed `(symbol, as_of)`.
- `market_dividends` (synced): `(symbol, exchange, ex_date)` → `amount` (per-share minor units), `pay_date`.
- `market_overview` (synced): name, sector, currency, `pe`, `eps`, `dividend_yield`, `dividend_per_share`, `ex_dividend_date`.

Reference tables get the standard read-only RLS (`select` for authenticated); `market_symbols` has RLS with no policy (service-role only). Client distribution is via new **global sync streams** (`market_data`) that synthesize a text `id` from the composite key.

## Deploy

1. `supabase secrets set ALPHAVANTAGE_API_KEY=…`
2. Apply migration `0020`; add the market tables to the `powersync` publication.
3. Redeploy `sync-streams.yaml` (new `market_data` streams).
4. `supabase functions deploy market-sync`.
5. Schedule daily (pg_cron + pg_net), e.g. 01:30 UTC after most markets close:
   ```sql
   select cron.schedule('market-sync-daily','30 1 * * *', $$
     select net.http_post(
       url := 'https://<project>.functions.supabase.co/market-sync',
       headers := jsonb_build_object('Authorization','Bearer '|| current_setting('app.service_key'), 'Content-Type','application/json'),
       body := '{}'::jsonb);
   $$);
   ```
   (Or trigger `market-sync` from any external scheduler.) The function is idempotent and safe to run more than once a day.

## Phases (build order)

1. **Portfolio valuation** *(this slice)* — investments page shows market value, cost basis, and gain/loss % per holding and in total, plus "as of" date and a dividend hint. Reads `market_quotes` + `market_overview`.
2. **Dividend tracking** — upcoming ex-dividend dates; annual dividend income; **earnings-by-period** graphs (week/month/quarter/year/all) on insights, from `market_dividends` × holdings.
3. **Projected future wealth** — projection graph from current value + expected contributions + dividend reinvestment + a growth assumption, on insights.
