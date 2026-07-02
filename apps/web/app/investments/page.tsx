"use client";

import { useState } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { insertRow, softDelete } from "../../src/write";
import { getDb } from "../../src/powersync";

interface Holding {
  id: string;
  account_id: string;
  symbol: string;
  quantity: number;
  avg_cost: number | null;
  currency: string;
  auto_fetch: number;
}

export default function InvestmentsPage() {
  const base = useBaseCurrency();
  const { data: holdings = [] } = useQuery<Holding>("SELECT * FROM holdings WHERE deleted_at IS NULL ORDER BY created_at");
  const { data: invAccounts = [] } = useQuery<{ id: string; name: string; currency: string }>(
    "SELECT id, name, currency FROM accounts WHERE deleted_at IS NULL AND type IN ('stocks','mutual_funds')",
  );

  const [symbol, setSymbol] = useState(""); const [qty, setQty] = useState(""); const [cost, setCost] = useState("");
  const [acc, setAcc] = useState<string | null>(null);

  const investedValue = holdings.reduce((s, h) => s + (h.avg_cost ?? 0) * h.quantity, 0);

  async function addHolding() {
    const account = acc ?? invAccounts[0]?.id;
    if (!account || !symbol.trim() || !qty) return;
    await insertRow("holdings", {
      account_id: account, symbol: symbol.trim().toUpperCase(), quantity: Number(qty),
      avg_cost: cost ? fromMajor(Number(cost), base).amount : null, currency: base, auto_fetch: 0,
    });
    setSymbol(""); setQty(""); setCost("");
  }

  async function toggleFetch(h: Holding) {
    const db = getDb();
    if (!db) return;
    await db.execute("UPDATE holdings SET auto_fetch = ?, updated_at = ? WHERE id = ?", [h.auto_fetch ? 0 : 1, new Date().toISOString(), h.id]);
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1>Investments</h1>

      <section className="card" style={{ padding: 20 }}>
        <div className="muted" style={{ fontSize: 13 }}>Invested value (at cost)</div>
        <div style={{ fontSize: 30, fontWeight: 750 }}>{format(money(Math.round(investedValue), base), "en-US")}</div>
        <div className="muted" style={{ fontSize: 12 }}>Enable daily price fetch per holding to track live gains/losses.</div>
      </section>

      <div style={{ display: "grid", gap: 10 }}>
        {holdings.map((h) => (
          <div key={h.id} className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div><strong>{h.symbol}</strong><div className="muted" style={{ fontSize: 12 }}>{h.quantity} @ {h.avg_cost ? format(money(h.avg_cost, h.currency), "en-US") : "—"}</div></div>
            <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
              <label style={{ fontSize: 13, display: "flex", gap: 6, alignItems: "center" }} className="muted">
                <input type="checkbox" checked={!!h.auto_fetch} onChange={() => toggleFetch(h)} /> daily fetch
              </label>
              <button className="chip" onClick={() => softDelete("holdings", h.id)}>×</button>
            </div>
          </div>
        ))}
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
          <div style={{ display: "flex", gap: 8 }}>
            <input className="input" placeholder="Symbol" value={symbol} onChange={(e) => setSymbol(e.target.value)} />
            <input className="input" inputMode="decimal" placeholder="Qty" value={qty} onChange={(e) => setQty(e.target.value.replace(/[^0-9.]/g, ""))} />
            <input className="input" inputMode="decimal" placeholder="Avg cost" value={cost} onChange={(e) => setCost(e.target.value.replace(/[^0-9.]/g, ""))} />
          </div>
          <button className="btn" onClick={addHolding} disabled={!symbol.trim() || !qty}>Add</button>
        </div>
      )}
    </div>
  );
}
