"use client";

import { useTranslation } from "react-i18next";
import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import type { Transaction } from "@pocketcare/types";
import { TransactionRow } from "../../src/ui/TransactionRow";
import { Skeleton } from "../../src/ui/Skeleton";

const TYPES = ["all", "income", "expense", "transfer"] as const;

export default function TransactionsPage() {
  const { t } = useTranslation();
  const [q, setQ] = useState("");
  const [type, setType] = useState<(typeof TYPES)[number]>("all");

  const like = `%${q}%`;
  const { data: rows = [], isLoading: rowsLoading } = useQuery<Transaction & { labels: string | null; method_label: string | null }>(
    `SELECT t.*,
       (SELECT GROUP_CONCAT(l.name, ', ') FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id WHERE tl.transaction_id = t.id) AS labels,
       (SELECT pm.label FROM payment_methods pm WHERE pm.id = t.payment_method) AS method_label
     FROM transactions t
     WHERE t.deleted_at IS NULL AND t.type != 'opening_balance'
       AND (? = '' OR t.note LIKE ? OR EXISTS (
         SELECT 1 FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id
         WHERE tl.transaction_id = t.id AND l.name LIKE ?))
       AND (? = 'all' OR t.type = ?)
     ORDER BY t.occurred_at DESC LIMIT 200`,
    [q, like, like, type, type],
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories");
  const { data: accts = [] } = useQuery<{ id: string; name: string; type: string; color: string | null }>("SELECT id, name, type, color FROM accounts WHERE deleted_at IS NULL");
  const catName = (id: string | null) => cats.find((c) => c.id === id)?.name ?? "Uncategorised";
  const acct = (id: string) => accts.find((a) => a.id === id);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 20, minWidth: 0, maxWidth: "100%", overflowX: "hidden" }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 10 }}>
        <h1 style={{ margin: 0 }}>{t("pages.transactions", "Transactions")}</h1>
        <Link href="/transactions/new" className="btn">＋ Add</Link>
      </div>

      <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap", maxWidth: "100%" }}>
        <input className="input" placeholder="Search label or note…" value={q} onChange={(e) => setQ(e.target.value)} style={{ flex: "1 1 200px", minWidth: 0 }} />
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {TYPES.map((t) => (
            <button key={t} className="chip" data-active={t === type} style={{ textTransform: "capitalize" }} onClick={() => setType(t)}>{t}</button>
          ))}
        </div>
      </div>

      <div className="card" style={{ padding: 8, overflowX: "hidden", minWidth: 0, maxWidth: "100%" }}>
        {rows.map((t) => (
          <TransactionRow key={t.id} tx={t} account={acct(t.account_id)} categoryName={catName(t.category_id)} />
        ))}
        {rows.length === 0 && (rowsLoading ? (
          <div style={{ display: "grid", gap: 10, padding: 12 }}>
            {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} h={44} r={12} />)}
          </div>
        ) : (
          <p className="muted" style={{ padding: 16 }}>No matching transactions.</p>
        ))}
      </div>
    </div>
  );
}
