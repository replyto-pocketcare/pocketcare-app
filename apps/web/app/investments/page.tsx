"use client";

import { useTranslation } from "react-i18next";
import { useState } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { insertRow, updateRow, softDelete } from "../../src/write";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { useMoneyFmt } from "../../src/ui/Money";
import { useConfirm } from "../../src/ui/Confirm";
import { ListSkeleton } from "../../src/ui/Skeleton";
import { InstrumentPicker, ExchangeSelect } from "../../src/instruments/InstrumentPicker";
import type { Instrument } from "../../src/instruments/catalog";
import { useCatalog } from "../../src/instruments/hooks";
import { CatalogProgress } from "../../src/instruments/CatalogProgress";
import { useMarketData, type Quote } from "../../src/market/hooks";

interface Holding {
  id: string;
  account_id: string;
  symbol: string;
  exchange: string | null;
  quantity: number;
  avg_cost: number | null;
  currency: string;
  auto_fetch: number;
}

export default function InvestmentsPage() {
  const { t } = useTranslation();
  const fmt = useMoneyFmt();
  const base = useBaseCurrency();
  const { data: holdings = [], isLoading: holdingsLoading } = useQuery<Holding>("SELECT * FROM holdings WHERE deleted_at IS NULL ORDER BY created_at");
  const { data: invAccounts = [] } = useQuery<{ id: string; name: string; currency: string }>(
    "SELECT id, name, currency FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND type IN ('stocks','mutual_funds')",
  );

  const [instrument, setInstrument] = useState<Instrument | null>(null);
  const [exFilter, setExFilter] = useState<string | null>(null);
  const [qty, setQty] = useState(""); const [cost, setCost] = useState("");
  const [acc, setAcc] = useState<string | null>(null);

  // Only download the global ticker DB for people who actually track investments,
  // and only the first time they open this screen (with a progress bar).
  const cat = useCatalog(invAccounts.length > 0);
  const downloading = cat.phase === "loading" || cat.phase === "checking";

  const market = useMarketData();
  const investedValue = holdings.reduce((s, h) => s + (h.avg_cost ?? 0) * h.quantity, 0);
  // Current value uses the latest EOD quote where we have one, else falls back to cost.
  const marketValue = holdings.reduce((s, h) => {
    const q = market.quote(h.symbol, h.exchange);
    return s + (q ? q.price * h.quantity : (h.avg_cost ?? 0) * h.quantity);
  }, 0);
  const gain = marketValue - investedValue;
  const gainPct = investedValue > 0 ? (gain / investedValue) * 100 : 0;

  async function addHolding() {
    const account = acc ?? invAccounts[0]?.id;
    if (!account || !instrument || !qty) return;
    const cur = instrument.currency || base;
    await insertRow("holdings", {
      account_id: account, symbol: instrument.symbol, exchange: instrument.exchange, quantity: Number(qty),
      avg_cost: cost ? fromMajor(Number(cost), cur).amount : null, currency: cur, auto_fetch: 0,
    });
    setInstrument(null); setQty(""); setCost("");
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1>{t("pages.investments", "Investments")}</h1>

      <section className="card" style={{ padding: 20, display: "grid", gap: 12 }}>
        <div style={{ display: "flex", gap: 24, flexWrap: "wrap" }}>
          <div>
            <div className="muted" style={{ fontSize: 13 }}>Current value</div>
            <div style={{ fontSize: 30, fontWeight: 750 }}>{fmt(money(Math.round(marketValue), base), "en-US")}</div>
          </div>
          <div>
            <div className="muted" style={{ fontSize: 13 }}>Invested (cost)</div>
            <div style={{ fontSize: 22, fontWeight: 700 }}>{fmt(money(Math.round(investedValue), base), "en-US")}</div>
          </div>
          <div>
            <div className="muted" style={{ fontSize: 13 }}>Total gain / loss</div>
            <div style={{ fontSize: 22, fontWeight: 700, color: gain >= 0 ? "var(--positive)" : "var(--negative)" }}>
              {gain >= 0 ? "+" : "−"}{fmt(money(Math.round(Math.abs(gain)), base), "en-US")} <span style={{ fontSize: 14 }}>({gain >= 0 ? "+" : "−"}{Math.abs(gainPct).toFixed(1)}%)</span>
            </div>
          </div>
        </div>
        <div className="muted" style={{ fontSize: 12 }}>
          {market.hasData
            ? `Prices are end-of-day${market.latestAsOf ? `, as of ${market.latestAsOf}` : ""}. Updated daily.`
            : "Live prices appear here once the daily market sync has run (or fall back to your cost basis)."}
        </div>
      </section>

      <div className="list-grid">
        {holdings.map((h) => (
          <HoldingRow key={h.id} h={h}
            quote={market.quote(h.symbol, h.exchange)}
            divYield={market.overview(h.symbol, h.exchange)?.dividend_yield ?? null}
            nextExDate={market.nextDividend(h.symbol, h.exchange)?.ex_date ?? null} />
        ))}
        {holdings.length === 0 && (holdingsLoading ? <ListSkeleton rows={3} /> : <p className="muted">No holdings yet.</p>)}
      </div>

      {invAccounts.length === 0 ? (
        <p className="muted">Create a Stocks or Mutual Funds account to add holdings.</p>
      ) : (
        <div className="card" style={{ padding: 20, display: "grid", gap: 10, maxWidth: 520 }}>
          <h2>Add holding</h2>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            {invAccounts.map((a) => <button key={a.id} className="chip" data-active={(acc ?? invAccounts[0]?.id) === a.id} onClick={() => setAcc(a.id)}>{a.name}</button>)}
          </div>
          <CatalogProgress phase={cat.phase} pct={cat.pct} onRetry={cat.retry} />
          <div style={{ display: "grid", gap: 8, opacity: downloading ? 0.5 : 1, pointerEvents: downloading ? "none" : "auto" }}>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              <div style={{ width: 160, flexShrink: 0 }}><ExchangeSelect value={exFilter} onChange={setExFilter} /></div>
              <div style={{ flex: 1, minWidth: 200 }}>
                <InstrumentPicker value={instrument} exchange={exFilter} onChange={setInstrument} />
              </div>
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <FloatingInput label="Qty" inputMode="decimal" value={qty} onChange={(v) => setQty(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
              <FloatingInput label={`Avg cost${instrument ? ` (${instrument.currency})` : ""}`} inputMode="decimal" value={cost} onChange={(v) => setCost(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
            </div>
          </div>
          <button className="btn" onClick={addHolding} disabled={!instrument || !qty}>Add</button>
        </div>
      )}
    </div>
  );
}

function HoldingRow({ h, quote, divYield, nextExDate }: { h: Holding; quote: Quote | undefined; divYield: number | null; nextExDate: string | null }) {
  const fmt = useMoneyFmt();
  const confirm = useConfirm();
  const [editing, setEditing] = useState(false);
  const [pick, setPick] = useState<Instrument | null>(null);
  const [qty, setQty] = useState(String(h.quantity));
  const [cost, setCost] = useState(h.avg_cost ? String(toMajor(money(h.avg_cost, h.currency))) : "");

  async function save() {
    const cur = pick?.currency ?? h.currency;
    await updateRow("holdings", h.id, {
      symbol: pick?.symbol ?? h.symbol,
      exchange: pick?.exchange ?? h.exchange,
      currency: cur,
      quantity: Number(qty) || 0,
      avg_cost: cost ? fromMajor(Number(cost), cur).amount : null,
    });
    setEditing(false);
  }

  if (editing) {
    return (
      <div className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
        <div className="muted" style={{ fontSize: 12 }}>Currently: {h.symbol}{h.exchange ? ` · ${h.exchange}` : ""}</div>
        <InstrumentPicker value={pick ? { symbol: pick.symbol, exchange: pick.exchange } : (h.exchange ? { symbol: h.symbol, exchange: h.exchange } : null)} exchange={null} onChange={setPick} placeholder="Change stock (optional)…" />
        <div style={{ display: "flex", gap: 8 }}>
          <FloatingInput label="Qty" inputMode="decimal" value={qty} onChange={(v) => setQty(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
          <FloatingInput label={`Avg cost (${pick?.currency ?? h.currency})`} inputMode="decimal" value={cost} onChange={(v) => setCost(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
        </div>
        <div style={{ display: "flex", gap: 8 }}><button className="btn" onClick={save}>Save</button><button className="chip" onClick={() => setEditing(false)}>Cancel</button></div>
      </div>
    );
  }
  const costTotal = (h.avg_cost ?? 0) * h.quantity;
  const value = quote ? quote.price * h.quantity : costTotal;
  const gain = value - costTotal;
  const gainPct = costTotal > 0 ? (gain / costTotal) * 100 : 0;
  const hint = [
    divYield != null ? `${(divYield * 100).toFixed(2)}% yield` : null,
    nextExDate ? `ex-div ${nextExDate}` : null,
  ].filter(Boolean).join(" · ");

  return (
    <div className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12 }}>
      <div style={{ minWidth: 0 }}>
        <strong>{h.symbol}</strong>{h.exchange && <span className="muted" style={{ fontSize: 12 }}> · {h.exchange}</span>}
        <div className="muted" style={{ fontSize: 12 }}>
          {h.quantity} @ {h.avg_cost ? fmt(money(h.avg_cost, h.currency), "en-US") : "—"}
          {quote && <> · now {fmt(money(quote.price, quote.currency), "en-US")}{quote.change_pct != null && <span style={{ color: quote.change_pct >= 0 ? "var(--positive)" : "var(--negative)" }}> ({quote.change_pct >= 0 ? "+" : ""}{quote.change_pct.toFixed(1)}%)</span>}</>}
        </div>
        {hint && <div className="muted" style={{ fontSize: 11 }}>{hint}</div>}
      </div>
      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontWeight: 700 }}>{fmt(money(Math.round(value), h.currency), "en-US")}</div>
          {h.avg_cost != null && (
            <div style={{ fontSize: 12, color: gain >= 0 ? "var(--positive)" : "var(--negative)" }}>
              {gain >= 0 ? "+" : "−"}{Math.abs(gainPct).toFixed(1)}%
            </div>
          )}
        </div>
        <button className="chip" onClick={() => setEditing(true)}>Edit</button>
        <button className="chip" onClick={async () => { if (await confirm({ title: "Remove this holding?", message: `“${h.symbol || "This holding"}” will be removed from your portfolio.`, confirmLabel: "Remove" })) softDelete("holdings", h.id); }} aria-label="Remove">×</button>
      </div>
    </div>
  );
}
