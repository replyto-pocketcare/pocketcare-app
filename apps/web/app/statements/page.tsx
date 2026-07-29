"use client";

import { useTranslation } from "react-i18next";
import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { useBaseCurrency } from "../../src/hooks";
import { useEntitlement } from "../../src/entitlement";
import { LockIcon } from "../../src/ui/icons";
import { useMoneyFmt } from "../../src/ui/Money";
import { TransactionTile, groupTxnsByDay, txTags } from "../../src/ui/TransactionTile";

export default function StatementsPage() {
  const { t } = useTranslation("statements");
  const { isPaid } = useEntitlement();
  const base = useBaseCurrency();
  const today = new Date();
  const firstOfMonth = new Date(today.getFullYear(), today.getMonth(), 1).toISOString().slice(0, 10);
  const [start, setStart] = useState(firstOfMonth);
  const [end, setEnd] = useState(today.toISOString().slice(0, 10));

  const startIso = new Date(start).toISOString();
  const endIso = new Date(new Date(end).getTime() + 86_400_000).toISOString();
  const { data: rows = [] } = useQuery<Transaction & { labels: string | null }>(
    `SELECT t.*,
       (SELECT GROUP_CONCAT(l.name, ', ') FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id WHERE tl.transaction_id = t.id) AS labels
     FROM transactions t WHERE t.deleted_at IS NULL AND t.type != 'opening_balance' AND t.occurred_at >= ? AND t.occurred_at < ? ORDER BY t.occurred_at`,
    [startIso, endIso],
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories");
  const catName = (id: string | null) => cats.find((c) => c.id === id)?.name ?? "Uncategorised";
  // Every amount on this page goes through fmt, so the hide-amounts privacy
  // toggle applies here too — it previously called format() directly and leaked.
  const fmt = useMoneyFmt();

  const income = rows.filter((r) => r.type === "income").reduce((s, r) => s + r.amount, 0);
  const expense = rows.filter((r) => r.type === "expense").reduce((s, r) => s + r.amount, 0);

  if (!isPaid) {
    return (
      <div className="fade-up" style={{ display: "grid", gap: 16, maxWidth: 560 }}>
        <h1>{t("title")}</h1>
        <div className="card" style={{ padding: 28, display: "grid", gap: 12, textAlign: "center" }}>
          <div style={{ display: "flex", justifyContent: "center", color: "var(--text-2)" }}><LockIcon size={30} /></div>
          <h2>{t("premiumTitle")}</h2>
          <p className="muted">{t("premiumBody")}</p>
          <Link href="/settings" className="btn" style={{ justifySelf: "center" }}>{t("goPremium")}</Link>
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: "grid", gap: 20, minWidth: 0, maxWidth: "100%", overflowX: "hidden" }} className="fade-up">
      <div className="no-print" style={{ display: "grid", gap: 14 }}>
        <div style={{ display: "flex", gap: 12, alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", minWidth: 0 }}>
          <h1 style={{ minWidth: 0 }}>{t("title")}</h1>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", minWidth: 0 }}>
            <Link href="/statements/analyze" className="btn ghost">{t("analyze")}</Link>
            <button className="btn" onClick={() => window.print()}>{t("print")}</button>
          </div>
        </div>
        <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
          <label style={{ display: "grid", gap: 4, flex: "1 1 220px", minWidth: 0 }}>
            <span className="muted" style={{ fontSize: 12 }}>{t("fromDate")}</span>
            <input className="input" type="date" value={start} onChange={(e) => { setStart(e.target.value); if (e.target.value > end) setEnd(e.target.value); }} />
          </label>
          <label style={{ display: "grid", gap: 4, flex: "1 1 220px", minWidth: 0 }}>
            <span className="muted" style={{ fontSize: 12 }}>{t("toDate")}</span>
            <input className="input" type="date" value={end} min={start || undefined} onChange={(e) => setEnd(e.target.value)} />
          </label>
        </div>
      </div>

      {/* Summary header tile */}
      <section className="card statement-card pc-glass" style={{ padding: 20, minWidth: 0, maxWidth: "100%", overflowX: "hidden", boxSizing: "border-box", display: "grid", gap: 16 }}>
        <div>
          <div style={{ fontSize: 15, fontWeight: 650 }}>{t("statementName")}</div>
          <div className="muted" style={{ fontSize: 12.5 }}>{new Date(start).toLocaleDateString()} – {new Date(end).toLocaleDateString()}</div>
        </div>
        <div>
          <div className="muted" style={{ fontSize: 12 }}>{t("netForPeriod")}</div>
          <div style={{ fontSize: 30, fontWeight: 780, letterSpacing: "-0.02em", overflowWrap: "anywhere", color: income - expense >= 0 ? "var(--positive)" : "var(--negative)" }}>
            {fmt(money(income - expense, base))}
          </div>
        </div>
        {/* One row per figure. These were three columns of a 1fr grid, which is
            far too narrow for Indian-format amounts — anything from a lakh up
            ellipsised to "₹1,2…", i.e. exactly the digits that matter. */}
        <div className="row-stack">
          <SummaryRow label={t("income")} value={fmt(money(income, base))} color="var(--positive)" />
          <SummaryRow label={t("expenses")} value={fmt(money(expense, base))} color="var(--negative)" />
          <SummaryRow label={t("transactions")} value={String(rows.length)} />
        </div>
      </section>

      {/* Transaction tiles, grouped by day (newest first) */}
      {rows.length === 0 ? (
        <p className="muted card" style={{ padding: 16, margin: 0 }}>{t("noTransactions")}</p>
      ) : (
        <div style={{ display: "grid", gap: 16, minWidth: 0 }}>
          {groupTxnsByDay(rows, { today: t("today"), yesterday: t("yesterday") }).map(({ day, label, items, net }) => (
            <section key={day} style={{ display: "grid", gap: 8, minWidth: 0 }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8, padding: "0 4px", minWidth: 0 }}>
                <span className="eyebrow" style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{label}</span>
                <span className="muted" style={{ fontSize: 12, whiteSpace: "nowrap", flexShrink: 0 }}>{net >= 0 ? "+" : "−"}{fmt(money(Math.abs(net), base))}</span>
              </div>
              <div className="card" style={{ padding: 0, overflow: "hidden" }}>
                {items.map((r, i) => (
                  <TransactionTile
                    key={r.id}
                    raw={(r.labels || r.description || r.type).trim()}
                    amountMinor={r.amount}
                    currency={r.currency}
                    type={r.type}
                    meta={new Date(r.occurred_at).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })}
                    tags={txTags(catName(r.category_id), r.labels)}
                    href={`/transactions/${r.id}/edit`}
                    divided={i > 0}
                  />
                ))}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}

/**
 * Label left, value right, on its own line. The value gets the whole remaining
 * width and wraps rather than truncating — an amount is the one thing on this
 * page that must never be cut off.
 */
function SummaryRow({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="row-tile" style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 12 }}>
      <span className="muted" style={{ fontSize: 12.5, flexShrink: 0 }}>{label}</span>
      <span style={{ fontWeight: 700, fontSize: 16, color, textAlign: "right", minWidth: 0, overflowWrap: "anywhere" }}>{value}</span>
    </div>
  );
}
