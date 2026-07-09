"use client";

import { useTranslation } from "react-i18next";
import { useState } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { insertRow, updateRow, softDelete } from "../../src/write";
import { getDb } from "../../src/powersync";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { useMoneyFmt } from "../../src/ui/Money";
import { InstrumentPicker, ExchangeSelect } from "../../src/instruments/InstrumentPicker";
import type { Instrument } from "../../src/instruments/catalog";
import { useCatalog } from "../../src/instruments/hooks";
import { CatalogProgress } from "../../src/instruments/CatalogProgress";

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
  const { data: holdings = [] } = useQuery<Holding>("SELECT * FROM holdings WHERE deleted_at IS NULL ORDER BY created_at");
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

  const investedValue = holdings.reduce((s, h) => s + (h.avg_cost ?? 0) * h.quantity, 0);

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

  async function toggleFetch(h: Holding) {
    const db = getDb();
    if (!db) return;
    await db.execute("UPDATE holdings SET auto_fetch = ?, updated_at = ? WHERE id = ?", [h.auto_fetch ? 0 : 1, new Date().toISOString(), h.id]);
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1>{t("pages.investments", "Investments")}</h1>

      <section className="card" style={{ padding: 20 }}>
        <div className="muted" style={{ fontSize: 13 }}>Invested value (at cost)</div>
        <div style={{ fontSize: 30, fontWeight: 750 }}>{fmt(money(Math.round(investedValue), base), "en-US")}</div>
        <div className="muted" style={{ fontSize: 12 }}>Enable daily price fetch per holding to track live gains/losses.</div>
      </section>

      <div style={{ display: "grid", gap: 10 }}>
        {holdings.map((h) => <HoldingRow key={h.id} h={h} onToggle={() => toggleFetch(h)} />)}
        {holdings.length === 0 && <p className="muted">No holdings yet.</p>}
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

function HoldingRow({ h, onToggle }: { h: Holding; onToggle: () => void }) {
  const fmt = useMoneyFmt();
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
  return (
    <div className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
      <div><strong>{h.symbol}</strong>{h.exchange && <span className="muted" style={{ fontSize: 12 }}> · {h.exchange}</span>}<div className="muted" style={{ fontSize: 12 }}>{h.quantity} @ {h.avg_cost ? fmt(money(h.avg_cost, h.currency), "en-US") : "—"}</div></div>
      <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
        <label style={{ fontSize: 13, display: "flex", gap: 6, alignItems: "center" }} className="muted">
          <input type="checkbox" checked={!!h.auto_fetch} onChange={onToggle} /> daily fetch
        </label>
        <button className="chip" onClick={() => setEditing(true)}>Edit</button>
        <button className="chip" onClick={() => softDelete("holdings", h.id)}>×</button>
      </div>
    </div>
  );
}
