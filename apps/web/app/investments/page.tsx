"use client";

import { useTranslation } from "react-i18next";
import { useMemo, useState } from "react";
import { useQuery } from "@powersync/react";
import { money, fromMajor, toMajor } from "@pocketcare/money";
import { useBaseCurrency, useAccountBalances } from "../../src/hooks";
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
import Link from "next/link";

interface Holding {
  id: string;
  account_id: string;
  symbol: string;
  exchange: string | null;
  quantity: number;
  avg_cost: number | null;
  currency: string;
  auto_fetch: number;
  instrument_type: string | null; // 'stock' | 'mf'
  off_list: number;
  name: string | null;
}

const DEMAT_TYPES = ["demat", "stocks", "mutual_funds"];

export default function InvestmentsPage() {
  const { t } = useTranslation();
  const fmt = useMoneyFmt();
  const base = useBaseCurrency();
  const { data: holdings = [], isLoading: holdingsLoading } = useQuery<Holding>("SELECT * FROM holdings WHERE deleted_at IS NULL ORDER BY created_at");
  const balances = useAccountBalances();
  const invAccounts = useMemo(() => balances.filter((b) => DEMAT_TYPES.includes(b.account.type)), [balances]);
  const balanceOf = (id: string) => invAccounts.find((b) => b.account.id === id)?.balance.amount ?? 0;
  const deployedOf = (id: string) => holdings.filter((h) => h.account_id === id).reduce((s, h) => s + (h.avg_cost ?? 0) * h.quantity, 0);

  const cat = useCatalog(invAccounts.length > 0);
  const downloading = cat.phase === "loading" || cat.phase === "checking";
  const market = useMarketData();

  const investedValue = holdings.reduce((s, h) => s + (h.avg_cost ?? 0) * h.quantity, 0);
  const marketValue = holdings.reduce((s, h) => {
    if (h.off_list) return s + (h.avg_cost ?? 0) * h.quantity; // untracked → held at cost
    const q = market.quote(h.symbol, h.exchange);
    return s + (q ? q.price * h.quantity : (h.avg_cost ?? 0) * h.quantity);
  }, 0);
  const gain = marketValue - investedValue;
  const gainPct = investedValue > 0 ? (gain / investedValue) * 100 : 0;
  const hasOffList = holdings.some((h) => h.off_list);

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1>{t("pages.investments", "Investments")}</h1>

      {/* Portfolio summary */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 12 }}>
        <div style={{ display: "flex", gap: 24, flexWrap: "wrap" }}>
          <Stat label="Current value" value={fmt(money(Math.round(marketValue), base))} big />
          <Stat label="Invested (cost)" value={fmt(money(Math.round(investedValue), base))} />
          <Stat label="Total gain / loss" value={`${gain >= 0 ? "+" : "−"}${fmt(money(Math.round(Math.abs(gain)), base))} (${gain >= 0 ? "+" : "−"}${Math.abs(gainPct).toFixed(1)}%)`} color={gain >= 0 ? "var(--positive)" : "var(--negative)"} />
        </div>
        <div className="muted" style={{ fontSize: 12 }}>
          {market.hasData
            ? `Listed prices are end-of-day${market.latestAsOf ? `, as of ${market.latestAsOf}` : ""}. Updated daily.`
            : "Live prices appear here once the daily market sync has run (or fall back to your cost basis)."}
          {hasOffList && " Off-list holdings are shown at cost — gains/losses aren't tracked until we can price them."}
        </div>
      </section>

      {/* Demat accounts: invested amount deployed across holdings */}
      {invAccounts.length === 0 ? (
        <div className="card" style={{ padding: 24, textAlign: "center", display: "grid", gap: 8, justifyItems: "center" }}>
          <div style={{ fontSize: 26 }}>▲</div>
          <h2 style={{ margin: 0 }}>No demat account yet</h2>
          <p className="muted" style={{ margin: 0, maxWidth: 380 }}>Create a <strong>Demat</strong> account with your invested amount, then deploy it across stocks and mutual funds here.</p>
          <Link href="/accounts/new" className="btn">+ Add demat account</Link>
        </div>
      ) : (
        <section style={{ display: "grid", gap: 12 }}>
          <div className="eyebrow">Your demat accounts</div>
          <div className="list-grid">
            {invAccounts.map((b) => {
              const invested = b.balance.amount;
              const deployed = deployedOf(b.account.id);
              const available = invested - deployed;
              const pct = invested > 0 ? Math.min(100, (deployed / invested) * 100) : 0;
              return (
                <div key={b.account.id} className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
                    <strong>{b.account.name}</strong>
                    <span className="muted" style={{ fontSize: 12 }}>{fmt(money(invested, b.account.currency))} invested</span>
                  </div>
                  <div style={{ height: 8, borderRadius: 999, background: "var(--surface-2)", overflow: "hidden" }}>
                    <div style={{ width: `${pct}%`, height: "100%", background: available < 0 ? "var(--negative)" : "var(--accent)" }} />
                  </div>
                  <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12 }}>
                    <span className="muted">Deployed {fmt(money(deployed, b.account.currency))}</span>
                    <span style={{ color: available < 0 ? "var(--negative)" : "var(--text-2)" }}>Available {fmt(money(available, b.account.currency))}</span>
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Holdings */}
      {holdings.length > 0 && (
        <div className="list-grid">
          {holdings.map((h) => (
            <HoldingRow key={h.id} h={h} accountName={invAccounts.find((b) => b.account.id === h.account_id)?.account.name ?? ""}
              quote={h.off_list ? undefined : market.quote(h.symbol, h.exchange)} />
          ))}
        </div>
      )}
      {holdings.length === 0 && holdingsLoading && <ListSkeleton rows={3} />}

      {invAccounts.length > 0 && (
        <AddHolding accounts={invAccounts.map((b) => ({ id: b.account.id, name: b.account.name, currency: b.account.currency, available: balanceOf(b.account.id) - deployedOf(b.account.id) }))}
          catPhase={cat.phase} catPct={cat.pct} catRetry={cat.retry} downloading={downloading} base={base} />
      )}
    </div>
  );
}

function Stat({ label, value, color, big }: { label: string; value: string; color?: string; big?: boolean }) {
  return (
    <div>
      <div className="muted" style={{ fontSize: 13 }}>{label}</div>
      <div style={{ fontSize: big ? 30 : 22, fontWeight: big ? 750 : 700, color }}>{value}</div>
    </div>
  );
}

function AddHolding({ accounts, catPhase, catPct, catRetry, downloading, base }: {
  accounts: { id: string; name: string; currency: string; available: number }[];
  catPhase: string; catPct: number; catRetry: () => void; downloading: boolean; base: string;
}) {
  const fmt = useMoneyFmt();
  const [accId, setAccId] = useState(accounts[0]?.id ?? "");
  const [kind, setKind] = useState<"stock" | "mf">("stock");
  const [listed, setListed] = useState(true);
  const [instrument, setInstrument] = useState<Instrument | null>(null);
  const [exFilter, setExFilter] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [qty, setQty] = useState("");
  const [cost, setCost] = useState("");

  const acc = accounts.find((a) => a.id === accId) ?? accounts[0];
  const cur = listed ? (instrument?.currency || base) : (acc?.currency || base);
  const costTotal = (Number(qty) || 0) > 0 && cost ? fromMajor(Number(cost), cur).amount * Number(qty) : 0;
  const over = acc ? costTotal > acc.available : false;
  const nameOk = listed ? !!instrument : !!name.trim();
  const canAdd = !!acc && nameOk && !!qty && !over;

  async function add() {
    if (!canAdd || !acc) return;
    await insertRow("holdings", {
      account_id: acc.id,
      symbol: listed ? instrument!.symbol : "",
      exchange: listed ? instrument!.exchange : null,
      name: listed ? (instrument!.symbol) : name.trim(),
      quantity: Number(qty),
      avg_cost: cost ? fromMajor(Number(cost), cur).amount : null,
      currency: cur,
      instrument_type: kind,
      off_list: listed ? 0 : 1,
      auto_fetch: listed ? 1 : 0,
    });
    setInstrument(null); setName(""); setQty(""); setCost("");
  }

  return (
    <div className="card" style={{ padding: 20, display: "grid", gap: 12, maxWidth: 560 }}>
      <h2 style={{ margin: 0 }}>Add holding</h2>

      {accounts.length > 1 && (
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {accounts.map((a) => <button key={a.id} className="chip" data-active={a.id === accId} onClick={() => setAccId(a.id)}>{a.name}</button>)}
        </div>
      )}
      {acc && <div className="muted" style={{ fontSize: 12, marginTop: -4 }}>Available to invest in {acc.name}: <strong style={{ color: acc.available < 0 ? "var(--negative)" : "var(--text)" }}>{fmt(money(acc.available, acc.currency))}</strong></div>}

      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
        <div style={{ display: "flex", gap: 6 }}>
          <button className="chip" data-active={kind === "stock"} onClick={() => setKind("stock")}>Stock</button>
          <button className="chip" data-active={kind === "mf"} onClick={() => setKind("mf")}>Mutual fund</button>
        </div>
        <div style={{ display: "flex", gap: 6, marginLeft: "auto" }}>
          <button className="chip" data-active={listed} onClick={() => setListed(true)}>In our list</button>
          <button className="chip" data-active={!listed} onClick={() => setListed(false)}>Not listed</button>
        </div>
      </div>

      {listed ? (
        <>
          <CatalogProgress phase={catPhase as never} pct={catPct} onRetry={catRetry} />
          <div style={{ display: "grid", gap: 8, opacity: downloading ? 0.5 : 1, pointerEvents: downloading ? "none" : "auto" }}>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              <div style={{ width: 160, flexShrink: 0 }}><ExchangeSelect value={exFilter} onChange={setExFilter} /></div>
              <div style={{ flex: 1, minWidth: 200 }}><InstrumentPicker value={instrument} exchange={exFilter} onChange={setInstrument} /></div>
            </div>
          </div>
        </>
      ) : (
        <>
          <FloatingInput label={kind === "mf" ? "Fund name" : "Stock name / symbol"} value={name} onChange={setName} />
          <div style={{ padding: "9px 12px", borderRadius: 10, fontSize: 12, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)", color: "var(--text-2)" }}>
            ⚠ We can't price this yet, so <strong style={{ color: "var(--text)" }}>gains/losses won't be tracked</strong> — it's held at cost until we add it to our system.
          </div>
        </>
      )}

      <div style={{ display: "flex", gap: 8 }}>
        <FloatingInput label={kind === "mf" ? "Units" : "Qty"} inputMode="decimal" value={qty} onChange={(v) => setQty(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
        <FloatingInput label={`${kind === "mf" ? "NAV / avg cost" : "Avg cost"} (${cur})`} inputMode="decimal" value={cost} onChange={(v) => setCost(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
      </div>

      {over && <div style={{ fontSize: 12.5, color: "var(--negative)" }}>This would deploy {fmt(money(costTotal, cur))}, more than the {fmt(money(acc!.available, acc!.currency))} available in this demat account. Reduce the amount or top up the account.</div>}
      <button className="btn" onClick={add} disabled={!canAdd}>Add holding</button>
    </div>
  );
}

function HoldingRow({ h, quote, accountName }: { h: Holding; quote: Quote | undefined; accountName: string }) {
  const fmt = useMoneyFmt();
  const confirm = useConfirm();
  const [editing, setEditing] = useState(false);
  const [qty, setQty] = useState(String(h.quantity));
  const [cost, setCost] = useState(h.avg_cost ? String(toMajor(money(h.avg_cost, h.currency))) : "");

  const label = h.off_list ? (h.name || "Holding") : (h.symbol || h.name || "Holding");
  const isMf = h.instrument_type === "mf";
  const unitWord = isMf ? "units" : "";

  async function save() {
    await updateRow("holdings", h.id, {
      quantity: Number(qty) || 0,
      avg_cost: cost ? fromMajor(Number(cost), h.currency).amount : null,
    });
    setEditing(false);
  }

  if (editing) {
    return (
      <div className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
        <div className="muted" style={{ fontSize: 12 }}>{label}{h.exchange ? ` · ${h.exchange}` : ""}</div>
        <div style={{ display: "flex", gap: 8 }}>
          <FloatingInput label={isMf ? "Units" : "Qty"} inputMode="decimal" value={qty} onChange={(v) => setQty(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
          <FloatingInput label={`${isMf ? "NAV" : "Avg cost"} (${h.currency})`} inputMode="decimal" value={cost} onChange={(v) => setCost(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
        </div>
        <div style={{ display: "flex", gap: 8 }}><button className="btn" onClick={save}>Save</button><button className="chip" onClick={() => setEditing(false)}>Cancel</button></div>
      </div>
    );
  }

  const costTotal = (h.avg_cost ?? 0) * h.quantity;
  const value = quote ? quote.price * h.quantity : costTotal;
  const gain = value - costTotal;
  const gainPct = costTotal > 0 ? (gain / costTotal) * 100 : 0;

  return (
    <div className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12 }}>
      <div style={{ minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <strong>{label}</strong>
          <span className="chip" style={{ padding: "1px 7px", fontSize: 10, textTransform: "uppercase" }}>{isMf ? "MF" : "Stock"}</span>
          {h.off_list ? <span className="chip" style={{ padding: "1px 7px", fontSize: 10, background: "var(--accent-ghost)", borderColor: "var(--accent-soft)", color: "var(--accent)" }}>Untracked</span> : null}
        </div>
        <div className="muted" style={{ fontSize: 12 }}>
          {h.quantity} {unitWord} @ {h.avg_cost ? fmt(money(h.avg_cost, h.currency)) : "—"}
          {quote && <> · now {fmt(money(quote.price, quote.currency))}{quote.change_pct != null && <span style={{ color: quote.change_pct >= 0 ? "var(--positive)" : "var(--negative)" }}> ({quote.change_pct >= 0 ? "+" : ""}{quote.change_pct.toFixed(1)}%)</span>}</>}
        </div>
        {accountName && <div className="muted" style={{ fontSize: 11 }}>{accountName}</div>}
      </div>
      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontWeight: 700 }}>{fmt(money(Math.round(value), h.currency))}</div>
          {h.off_list ? (
            <div style={{ fontSize: 11, color: "var(--text-3)" }}>at cost</div>
          ) : h.avg_cost != null ? (
            <div style={{ fontSize: 12, color: gain >= 0 ? "var(--positive)" : "var(--negative)" }}>{gain >= 0 ? "+" : "−"}{Math.abs(gainPct).toFixed(1)}%</div>
          ) : null}
        </div>
        <button className="chip" onClick={() => setEditing(true)}>Edit</button>
        <button className="chip" onClick={async () => { if (await confirm({ title: "Remove this holding?", message: `“${label}” will be removed from your portfolio.`, confirmLabel: "Remove" })) softDelete("holdings", h.id); }} aria-label="Remove">×</button>
      </div>
    </div>
  );
}
