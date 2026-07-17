"use client";

import { useTranslation } from "react-i18next";
import { useMemo, useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, fromMajor, toMajor } from "@pocketcare/money";
import { useBaseCurrency, useAccountBalances, useConvertAmount, useRates } from "../../src/hooks";
import { updateRow, softDelete } from "../../src/write";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { useMoneyFmt } from "../../src/ui/Money";
import { useConfirm } from "../../src/ui/Confirm";
import { ListSkeleton } from "../../src/ui/Skeleton";
import { useMarketData, type Quote } from "../../src/market/hooks";
import { computeDividendEvents, type DivRow } from "../../src/market/dividends";
import {
  buildGroups, portfolioTotals, valuation, assetClassOf, holdingLabel, classMeta, isListed,
  fyLabel, inCurrentFYToDate, type HoldingRow, type Group, type AssetClass,
} from "../../src/investments/model";
import { AllocationDonut, GainBars } from "../../src/investments/Charts";
import { AddInvestmentDialog } from "../../src/investments/AddDialog";

const DEMAT_TYPES = ["demat", "stocks", "mutual_funds"];

export default function InvestmentsPage() {
  const { t } = useTranslation();
  const fmt = useMoneyFmt();
  const base = useBaseCurrency();
  const convertAmount = useConvertAmount();
  const rates = useRates();
  const { data: holdings = [], isLoading } = useQuery<HoldingRow>("SELECT * FROM holdings WHERE deleted_at IS NULL ORDER BY created_at");
  const { data: dividends = [] } = useQuery<DivRow>("SELECT symbol, exchange, ex_date, pay_date, amount, currency FROM market_dividends");
  const balances = useAccountBalances();
  const invAccounts = useMemo(() => balances.filter((b) => DEMAT_TYPES.includes(b.account.type)), [balances]);
  const market = useMarketData();

  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [addCtx, setAddCtx] = useState<{ assetClass?: AssetClass; exchange?: string | null; accountId?: string } | null>(null);

  const quoteLite = (h: HoldingRow) => {
    const q = h.off_list ? undefined : market.quote(h.symbol, h.exchange);
    return q ? { price: q.price, currency: q.currency, change_pct: q.change_pct } : null;
  };

  const groups = useMemo(
    () => buildGroups(holdings, convertAmount, quoteLite),
    [holdings, convertAmount, market.hasData], // eslint-disable-line react-hooks/exhaustive-deps
  );
  const totals = portfolioTotals(groups);

  // Dividend earned so far this financial year (base currency, minor units).
  const dividendFY = useMemo(() => {
    const lite = holdings
      .filter((h) => isListed(assetClassOf(h)) && !h.off_list)
      .map((h) => ({ symbol: h.symbol, exchange: h.exchange, quantity: h.quantity, currency: h.currency }));
    const events = computeDividendEvents(lite, dividends, rates, base as never);
    return events.filter((e) => !e.upcoming && inCurrentFYToDate(e.date)).reduce((s, e) => s + e.base, 0);
  }, [holdings, dividends, rates, base]);

  const selected = groups.find((g) => g.key === selectedKey) ?? null;

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>{t("pages.investments", "Investments & savings")}</h1>
        {invAccounts.length > 0 && <button className="btn" onClick={() => setAddCtx({})}>+ Add investment</button>}
      </div>

      {/* Grand total */}
      <section className="card pc-glass" style={{ padding: 20, display: "grid", gap: 12 }}>
        <div style={{ display: "flex", gap: 24, flexWrap: "wrap" }}>
          <Stat label="Current value" value={fmt(money(Math.round(totals.value), base))} big />
          <Stat label="Invested" value={fmt(money(Math.round(totals.cost), base))} />
          <Stat label="Total gain / loss"
            value={`${totals.gain >= 0 ? "+" : "−"}${fmt(money(Math.round(Math.abs(totals.gain)), base))} (${totals.gain >= 0 ? "+" : "−"}${Math.abs(totals.gainPct).toFixed(1)}%)`}
            color={totals.gain >= 0 ? "var(--positive)" : "var(--negative)"} />
        </div>
        <div className="muted" style={{ fontSize: 12 }}>
          {market.hasData
            ? `Listed prices are end-of-day${market.latestAsOf ? `, as of ${market.latestAsOf}` : ""}. Unlisted schemes (crypto, FDs, off-list) use the current value you enter, else cost.`
            : "Live prices appear once the daily market sync runs; unlisted schemes use the value you enter, else cost."}
        </div>
      </section>

      {invAccounts.length === 0 ? (
        <div className="card" style={{ padding: 24, textAlign: "center", display: "grid", gap: 8, justifyItems: "center" }}>
          <div style={{ fontSize: 26 }}>▲</div>
          <h2 style={{ margin: 0 }}>No investment account yet</h2>
          <p className="muted" style={{ margin: 0, maxWidth: 400 }}>Create a <strong>Demat</strong> (or stocks/mutual-funds) account, then add stocks, mutual funds, SIPs, crypto, FDs and other schemes here.</p>
          <Link href="/accounts/new" className="btn">+ Add investment account</Link>
        </div>
      ) : selected ? (
        <DrillIn
          group={selected}
          quoteFor={(h) => (h.off_list ? undefined : market.quote(h.symbol, h.exchange))}
          onBack={() => setSelectedKey(null)}
          onAdd={() => {
            const first = selected.holdings[0];
            if (!first) { setAddCtx({}); return; }
            const isEx = selected.key.startsWith("ex:");
            setAddCtx({ assetClass: assetClassOf(first), accountId: first.account_id, ...(isEx ? { exchange: first.exchange ?? null } : {}) });
          }}
        />
      ) : (
        <>
          {/* Group tiles */}
          {groups.length > 0 ? (
            <section style={{ display: "grid", gap: 12 }}>
              <div className="eyebrow">By exchange &amp; scheme</div>
              <div className="list-grid">
                {groups.map((g) => <GroupTile key={g.key} g={g} base={base} onOpen={() => setSelectedKey(g.key)} />)}
              </div>
            </section>
          ) : isLoading ? <ListSkeleton rows={3} /> : (
            <div className="card" style={{ padding: 24, textAlign: "center", color: "var(--text-2)" }}>No investments yet — add your first with the button above.</div>
          )}

          {/* Insights */}
          {groups.length > 0 && (
            <section style={{ display: "grid", gap: 12 }}>
              <div className="eyebrow">Insights</div>
              <div style={{ display: "grid", gap: 12, gridTemplateColumns: "repeat(auto-fit, minmax(min(320px,100%),1fr))" }}>
                <div className="card pc-glass" style={{ padding: 18, display: "grid", gap: 8 }}>
                  <div className="muted" style={{ fontSize: 12 }}>Dividends earned · {fyLabel()}</div>
                  <div style={{ fontSize: 28, fontWeight: 760, color: "var(--positive)" }}>{fmt(money(Math.round(dividendFY), base))}</div>
                  <div className="muted" style={{ fontSize: 11 }}>Estimated from held quantities × declared dividends this financial year (Apr–Mar).</div>
                </div>
                <div className="card pc-glass" style={{ padding: 18, display: "grid", gap: 8 }}>
                  <div className="eyebrow">Allocation</div>
                  <AllocationDonut
                    data={groups.map((g) => ({ name: g.label, value: toMajor(money(Math.round(g.value), base)) }))}
                    centerLabel="Total" centerValue={fmt(money(Math.round(totals.value), base))}
                    fmt={(n) => fmt(money(fromMajor(n, base).amount, base))} />
                </div>
                <div className="card pc-glass" style={{ padding: 18, display: "grid", gap: 8 }}>
                  <div className="eyebrow">Gain / loss by group</div>
                  <GainBars
                    data={groups.map((g) => ({ name: g.label, gain: toMajor(money(Math.round(g.gain), base)) }))}
                    fmt={(n) => fmt(money(fromMajor(n, base).amount, base))} />
                </div>
              </div>
            </section>
          )}
        </>
      )}

      {addCtx && (
        <AddInvestmentDialog
          ctx={addCtx}
          accounts={invAccounts.map((b) => ({ id: b.account.id, name: b.account.name, currency: b.account.currency, type: b.account.type }))}
          availableOf={(id) => (invAccounts.find((b) => b.account.id === id)?.balance.amount ?? 0) - holdings.filter((h) => h.account_id === id).reduce((s, h) => s + (h.avg_cost ?? 0) * h.quantity, 0)}
          fundingAccounts={balances.filter((b) => !DEMAT_TYPES.includes(b.account.type) && (b.account as { kind?: string }).kind === undefined).map((b) => ({ id: b.account.id, name: b.account.name, currency: b.account.currency, balance: b.balance.amount }))}
          base={base}
          onClose={() => setAddCtx(null)}
        />
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

function GroupTile({ g, base, onOpen }: { g: Group; base: string; onOpen: () => void }) {
  const fmt = useMoneyFmt();
  const up = g.gain >= 0;
  return (
    <button className="card lift" onClick={onOpen} style={{ padding: 16, display: "grid", gap: 8, textAlign: "left", color: "inherit", cursor: "pointer" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8 }}>
        <strong style={{ fontSize: 15 }}>{g.label}</strong>
        <span className="muted" style={{ fontSize: 11 }}>{g.holdings.length} holding{g.holdings.length === 1 ? "" : "s"} ›</span>
      </div>
      <div style={{ fontSize: 22, fontWeight: 740 }}>{fmt(money(Math.round(g.value), base))}</div>
      <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12 }}>
        <span className="muted">Invested {fmt(money(Math.round(g.cost), base))}</span>
        <span style={{ color: up ? "var(--positive)" : "var(--negative)", fontWeight: 600 }}>
          {up ? "+" : "−"}{fmt(money(Math.round(Math.abs(g.gain)), base))} ({up ? "+" : "−"}{Math.abs(g.gainPct).toFixed(1)}%)
        </span>
      </div>
    </button>
  );
}

function DrillIn({ group, quoteFor, onBack, onAdd }: {
  group: Group; quoteFor: (h: HoldingRow) => Quote | undefined; onBack: () => void; onAdd: () => void;
}) {
  const fmt = useMoneyFmt();
  const base = useBaseCurrency();
  const up = group.gain >= 0;
  return (
    <div style={{ display: "grid", gap: 14 }}>
      <button className="chip" onClick={onBack} style={{ justifySelf: "start" }}>‹ All investments</button>
      <section className="card pc-glass" style={{ padding: 18, display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 12 }}>
        <div>
          <h2 style={{ margin: 0 }}>{group.label}</h2>
          <div className="muted" style={{ fontSize: 12 }}>Invested {fmt(money(Math.round(group.cost), base))}</div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontSize: 24, fontWeight: 750 }}>{fmt(money(Math.round(group.value), base))}</div>
          <div style={{ fontSize: 13, color: up ? "var(--positive)" : "var(--negative)", fontWeight: 600 }}>
            {up ? "+" : "−"}{fmt(money(Math.round(Math.abs(group.gain)), base))} ({up ? "+" : "−"}{Math.abs(group.gainPct).toFixed(1)}%)
          </div>
        </div>
      </section>
      <div style={{ display: "flex", justifyContent: "flex-end" }}>
        <button className="btn" onClick={onAdd}>+ Add to {group.label}</button>
      </div>
      <div className="list-grid">
        {group.holdings.map((h) => <HoldingTile key={h.id} h={h} quote={h.off_list ? undefined : quoteFor(h)} />)}
      </div>
    </div>
  );
}

/** Zerodha-style tile: name, qty × avg + LTP on the left; value + gain on the right. */
function HoldingTile({ h, quote }: { h: HoldingRow; quote: Quote | undefined }) {
  const fmt = useMoneyFmt();
  const confirm = useConfirm();
  const [editing, setEditing] = useState(false);

  const cls = assetClassOf(h);
  const label = holdingLabel(h);
  const v = valuation(h, quote ? { price: quote.price, currency: quote.currency, change_pct: quote.change_pct } : null);
  const up = v.gain >= 0;
  const ltp = quote ? quote.price : (h.quantity > 0 && h.current_value != null ? h.current_value / h.quantity : h.avg_cost ?? 0);
  const meta = classMeta(cls);

  if (editing) return <EditHolding h={h} onDone={() => setEditing(false)} />;

  return (
    <div className="card tx-tile" style={{ padding: 14, display: "grid", gap: 6 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 10 }}>
        <div style={{ minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <strong style={{ fontSize: 15, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{label}</strong>
            {h.off_list ? <span className="chip" style={{ padding: "0 6px", fontSize: 9.5, background: "var(--accent-ghost)", borderColor: "var(--accent-soft)", color: "var(--accent)" }}>untracked</span> : null}
          </div>
          <div className="muted" style={{ fontSize: 12 }}>
            {h.quantity}{meta.unitWord ? ` ${meta.unitWord}` : ""} × {h.avg_cost != null ? fmt(money(h.avg_cost, h.currency)) : "—"}
          </div>
        </div>
        <div style={{ textAlign: "right", flexShrink: 0 }}>
          <div style={{ fontWeight: 700, fontSize: 16 }}>{fmt(money(Math.round(v.value), h.currency))}</div>
          {h.avg_cost != null || h.current_value != null ? (
            <div style={{ fontSize: 12.5, color: up ? "var(--positive)" : "var(--negative)", fontWeight: 600 }}>
              {up ? "+" : "−"}{fmt(money(Math.round(Math.abs(v.gain)), h.currency))} ({up ? "+" : "−"}{Math.abs(v.gainPct).toFixed(2)}%)
            </div>
          ) : null}
        </div>
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 6 }}>
        <span className="muted" style={{ fontSize: 11.5 }}>
          {meta.label}{h.exchange ? ` · ${h.exchange}` : ""}
          {cls === "fd" && h.annual_rate ? ` · ${h.annual_rate}% p.a.` : ""}
          {cls === "fd" && h.maturity_date ? ` · matures ${new Date(h.maturity_date).toLocaleDateString(undefined, { month: "short", year: "numeric" })}` : ""}
          {quote ? ` · LTP ${fmt(money(quote.price, quote.currency))}${quote.change_pct != null ? ` (${quote.change_pct >= 0 ? "+" : ""}${quote.change_pct.toFixed(1)}%)` : ""}` : ` · value ${fmt(money(Math.round(ltp), h.currency))}`}
        </span>
        <div style={{ display: "flex", gap: 6, flexShrink: 0 }}>
          <button className="chip" onClick={() => setEditing(true)} style={{ padding: "2px 8px", fontSize: 11 }}>Edit</button>
          <button className="chip" onClick={async () => { if (await confirm({ title: "Remove this investment?", message: `“${label}” will be removed from your portfolio.`, confirmLabel: "Remove" })) softDelete("holdings", h.id); }} aria-label="Remove" style={{ padding: "2px 8px", fontSize: 11 }}>×</button>
        </div>
      </div>
    </div>
  );
}

function EditHolding({ h, onDone }: { h: HoldingRow; onDone: () => void }) {
  const cls = assetClassOf(h);
  const priced = isListed(cls) && !h.off_list;
  const [qty, setQty] = useState(String(h.quantity));
  const [cost, setCost] = useState(h.avg_cost ? String(toMajor(money(h.avg_cost, h.currency))) : "");
  const [cur, setCur] = useState(h.current_value != null ? String(toMajor(money(h.current_value, h.currency))) : "");
  const [rate, setRate] = useState(h.annual_rate != null ? String(h.annual_rate) : "");
  const meta = classMeta(cls);

  async function save() {
    await updateRow("holdings", h.id, {
      quantity: Number(qty) || 0,
      avg_cost: cost ? fromMajor(Number(cost), h.currency).amount : null,
      current_value: !priced && cur ? fromMajor(Number(cur), h.currency).amount : (priced ? null : h.current_value),
      annual_rate: cls === "fd" && rate ? Number(rate) : h.annual_rate,
    });
    onDone();
  }

  return (
    <div className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
      <div className="muted" style={{ fontSize: 12 }}>{holdingLabel(h)}{h.exchange ? ` · ${h.exchange}` : ""}</div>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <FloatingInput label={meta.unitWord ? meta.unitWord.replace(/^./, (c) => c.toUpperCase()) : "Quantity"} inputMode="decimal" value={qty} onChange={(v) => setQty(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1, minWidth: 110 }} />
        <FloatingInput label={`${cls === "mf" ? "NAV / cost" : "Avg cost"} (${h.currency})`} group currency={h.currency} value={cost} onChange={setCost} style={{ flex: 1, minWidth: 130 }} />
      </div>
      {!priced && (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <FloatingInput label={`Current value (${h.currency})`} group currency={h.currency} value={cur} onChange={setCur} style={{ flex: 1, minWidth: 130 }} />
          {cls === "fd" && <FloatingInput label="Interest % p.a." inputMode="decimal" value={rate} onChange={(v) => setRate(v.replace(/[^0-9.]/g, ""))} style={{ width: 120 }} />}
        </div>
      )}
      <div style={{ display: "flex", gap: 8 }}><button className="btn" onClick={save}>Save</button><button className="chip" onClick={onDone}>Cancel</button></div>
    </div>
  );
}
