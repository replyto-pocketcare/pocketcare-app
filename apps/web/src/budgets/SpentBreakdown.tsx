"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { money, type Money } from "@sanvya/money";
import type { BudgetLike, BudgetTxn } from "@sanvya/data";
import { getRepositories } from "../powersync";
import { Modal } from "../ui/Modal";
import { useMoneyFmt } from "../ui/Money";
import { Spinner } from "../ui/Spinner";

/**
 * The expenses behind a budget's "spent" figure.
 *
 * Reads through `budgets.transactionsThisPeriod`, which shares its scope
 * clause with `spentThisPeriod` — so this list is the same query that produced
 * the number, not a second interpretation of "what counts". A drill-down that
 * disagrees with the figure above it is worse than none, because it makes the
 * user distrust the budget rather than the screen.
 */
export function SpentBreakdown({ open, onClose, budget, spent, title }: {
  open: boolean; onClose: () => void; budget: BudgetLike; spent: Money; title: string;
}) {
  const fmt = useMoneyFmt();
  const [rows, setRows] = useState<BudgetTxn[] | null>(null);

  useEffect(() => {
    if (!open) { setRows(null); return; }
    let active = true;
    void getRepositories().budgets.transactionsThisPeriod(budget)
      .then((r) => active && setRows(r))
      .catch(() => active && setRows([]));
    return () => { active = false; };
  }, [open, budget]);

  const listed = (rows ?? []).reduce((s, r) => s + r.amount, 0);
  // If these ever disagree the cause is a scope change landing mid-read, not a
  // rounding artefact — so say so rather than quietly showing a total that
  // contradicts the card the user just tapped.
  const mismatch = rows !== null && listed !== spent.amount;

  return (
    <Modal open={open} onClose={onClose} label={`${title} — spending`}>
      <h2 style={{ margin: "0 0 2px", fontSize: 17 }}>{title}</h2>
      <p className="muted" style={{ margin: "0 0 14px", fontSize: 12.5 }}>
        {rows === null ? "Loading…" : `${rows.length} transaction${rows.length === 1 ? "" : "s"} · ${fmt(spent)} spent`}
      </p>

      {rows === null ? (
        <div style={{ display: "grid", placeItems: "center", padding: 28 }}><Spinner size={26} /></div>
      ) : rows.length === 0 ? (
        <p className="muted" style={{ fontSize: 13, lineHeight: 1.55 }}>
          Nothing has been counted against this budget yet in this period.
        </p>
      ) : (
        <>
          <div style={{ maxHeight: "52vh", overflowY: "auto", margin: "0 -4px" }}>
            {rows.map((r) => (
              <Link
                key={r.id}
                href={`/transactions/${r.id}`}
                onClick={onClose}
                style={{
                  display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12,
                  padding: "10px 4px", borderBottom: "1px solid var(--border)",
                }}
              >
                <span style={{ minWidth: 0 }}>
                  <span style={{ display: "block", fontSize: 13.5, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                    {r.description || r.note || r.category_name || "Expense"}
                  </span>
                  <span className="muted" style={{ fontSize: 11.5 }}>
                    {new Date(r.occurred_at).toLocaleDateString()}
                    {r.category_name ? ` · ${r.category_name}` : ""}
                    {r.account_name ? ` · ${r.account_name}` : ""}
                  </span>
                </span>
                <span style={{ fontSize: 13.5, fontWeight: 650, flexShrink: 0 }} className="tabular-nums">
                  {fmt(money(r.amount, r.currency))}
                </span>
              </Link>
            ))}
          </div>

          <div style={{ display: "flex", justifyContent: "space-between", gap: 12, paddingTop: 12, fontSize: 13.5, fontWeight: 700 }}>
            <span>Total</span>
            <span className="tabular-nums">{fmt(money(listed, budget.currency))}</span>
          </div>
          {mismatch && (
            <p className="muted" style={{ fontSize: 11.5, marginTop: 8 }}>
              This differs from the {fmt(spent)} on the card — the budget’s scope changed while loading. Reopen to refresh.
            </p>
          )}
        </>
      )}
    </Modal>
  );
}
