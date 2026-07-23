"use client";

import Link from "next/link";
import { money } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { AccountBadge } from "./AccountBadge";
import { useMoneyFmt } from "./Money";
import { colorForId } from "../colors";
import type { SplitInfo } from "../splits/collapse";

export type TxRow = Transaction & { labels: string | null; method_label: string | null };
type Acct = { id: string; name: string; type: string; color: string | null } | undefined;

/** Small "Split" pill shown on collapsed split tiles. */
export function SplitChip() {
  return (
    <span style={{
      flexShrink: 0, fontSize: 10.5, fontWeight: 700, letterSpacing: "0.03em", textTransform: "uppercase",
      color: "var(--accent)", background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)",
      borderRadius: 999, padding: "1px 7px", lineHeight: 1.5,
    }}>Split</span>
  );
}

/**
 * Shared transaction list row — one consistent look across Transactions, Search,
 * and anywhere else we list transactions. Truncates long labels, respects the
 * "hide amounts" setting, and links to the edit page.
 *
 * When `split` is provided the row represents a collapsed split expense: it
 * shows a "Split" chip and the **total you paid** (from SplitInfo) instead of
 * the single underlying posting's amount.
 */
export function TransactionRow({ tx, account, categoryName, tile = false, split }: { tx: TxRow; account: Acct; categoryName: string; tile?: boolean; split?: SplitInfo | undefined }) {
  const fmt = useMoneyFmt();
  const primary = tx.description || tx.labels || categoryName || "Uncategorised";
  const sign = split ? "−" : tx.type === "expense" ? "−" : tx.type === "income" ? "+" : "⇄ ";
  const amountMinor = split ? split.displayPaid : tx.amount;
  const amountCur = split ? split.currency : tx.currency;
  return (
    <Link
      href={`/transactions/${tx.id}/edit`}
      className={tile ? "tx-tile" : undefined}
      style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "12px 14px", borderBottom: "1px solid var(--border)", width: "100%", boxSizing: "border-box", overflowX: "hidden" }}
    >
      <div style={{ display: "flex", gap: 12, alignItems: "center", minWidth: 0, flex: 1, overflow: "hidden" }}>
        <div style={{ flexShrink: 0 }}>
          <AccountBadge type={account?.type ?? ""} color={account?.color ?? colorForId(tx.account_id)} id={tx.account_id} name={account?.name} />
        </div>
        <div style={{ minWidth: 0, flex: 1, overflow: "hidden" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 6, minWidth: 0 }}>
            <span style={{ fontSize: 15, fontWeight: 500, color: "var(--text)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
              {primary}
            </span>
            {split && <SplitChip />}
          </div>
          <div className="muted" style={{ fontSize: 12, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", marginTop: 2 }}>
            {new Date(tx.occurred_at).toLocaleDateString(undefined, { month: "short", day: "numeric" })}
            {split ? ` · your share ${fmt(money(split.yourShare, split.currency))}` : tx.method_label ? ` · ${tx.method_label}` : ""}
          </div>
        </div>
      </div>
      <div style={{ flexShrink: 0, whiteSpace: "nowrap", fontWeight: 600, fontSize: 15, color: !split && tx.type === "income" ? "var(--positive)" : "var(--text)" }}>
        {sign}{fmt(money(amountMinor, amountCur))}
      </div>
    </Link>
  );
}
