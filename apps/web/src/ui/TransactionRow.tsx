"use client";

import Link from "next/link";
import { money } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { AccountBadge } from "./AccountBadge";
import { useMoneyFmt } from "./Money";
import { colorForId } from "../colors";

export type TxRow = Transaction & { labels: string | null; method_label: string | null };
type Acct = { id: string; name: string; type: string; color: string | null } | undefined;

/**
 * Shared transaction list row — one consistent look across Transactions, Search,
 * and anywhere else we list transactions. Truncates long labels, respects the
 * "hide amounts" setting, and links to the edit page.
 */
export function TransactionRow({ tx, account, categoryName }: { tx: TxRow; account: Acct; categoryName: string }) {
  const fmt = useMoneyFmt();
  const primary = tx.description || tx.labels || categoryName || "Uncategorised";
  const sign = tx.type === "expense" ? "−" : tx.type === "income" ? "+" : "⇄ ";
  return (
    <Link
      href={`/transactions/${tx.id}/edit`}
      style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "12px 14px", borderBottom: "1px solid var(--border)", width: "100%", boxSizing: "border-box", overflowX: "hidden" }}
    >
      <div style={{ display: "flex", gap: 12, alignItems: "center", minWidth: 0, flex: 1, overflow: "hidden" }}>
        <div style={{ flexShrink: 0 }}>
          <AccountBadge type={account?.type ?? ""} color={account?.color ?? colorForId(tx.account_id)} id={tx.account_id} name={account?.name} />
        </div>
        <div style={{ minWidth: 0, flex: 1, overflow: "hidden" }}>
          <div style={{ fontSize: 15, fontWeight: 500, color: "var(--text)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
            {primary}
          </div>
          <div className="muted" style={{ fontSize: 12, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", marginTop: 2 }}>
            {new Date(tx.occurred_at).toLocaleDateString(undefined, { month: "short", day: "numeric" })}
            {tx.method_label ? ` · ${tx.method_label}` : ""}
          </div>
        </div>
      </div>
      <div style={{ flexShrink: 0, whiteSpace: "nowrap", fontWeight: 600, fontSize: 15, color: tx.type === "income" ? "var(--positive)" : "var(--text)" }}>
        {sign}{fmt(money(tx.amount, tx.currency))}
      </div>
    </Link>
  );
}
