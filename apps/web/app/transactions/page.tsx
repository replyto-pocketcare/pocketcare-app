"use client";

import { useTranslation } from "react-i18next";
import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, format } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { useAmountsHidden } from "../../src/prefs";
import { colorForId } from "../../src/colors";
import { AccountBadge } from "../../src/ui/AccountBadge";

const TYPES = ["all", "income", "expense", "transfer"] as const;

export default function TransactionsPage() {
  const { t } = useTranslation();
  const [q, setQ] = useState("");
  const [type, setType] = useState<(typeof TYPES)[number]>("all");

  const like = `%${q}%`;
  const { data: rows = [] } = useQuery<Transaction & { labels: string | null; method_label: string | null }>(
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
  const hidden = useAmountsHidden();

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h1>{t("pages.transactions", "Transactions")}</h1>
        <Link href="/transactions/new" className="btn">＋ Add</Link>
      </div>

      <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
        <input className="input" placeholder="Search label or note…" value={q} onChange={(e) => setQ(e.target.value)} style={{ flex: "1 1 220px" }} />
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {TYPES.map((t) => (
            <button key={t} className="chip" data-active={t === type} style={{ textTransform: "capitalize" }} onClick={() => setType(t)}>{t}</button>
          ))}
        </div>
      </div>

      <div className="card" style={{ padding: 8 }}>
        {rows.map((t) => (
          <Link key={t.id} href={`/transactions/${t.id}/edit`} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "12px 14px", borderBottom: "1px solid var(--border)" }}>
            <div style={{ display: "flex", gap: 10, alignItems: "center", minWidth: 0, flex: 1 }}>
              {(() => { const a = acct(t.account_id); return <AccountBadge type={a?.type ?? ""} color={a?.color ?? colorForId(t.account_id)} id={t.account_id} name={a?.name} />; })()}
              <div style={{ minWidth: 0 }}>
                <div style={{ fontWeight: 550, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{t.labels || catName(t.category_id)}</div>
                <div className="muted" style={{ fontSize: 12, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{new Date(t.occurred_at).toLocaleString()} · {t.type}{t.method_label ? ` · ${t.method_label}` : ""}</div>
              </div>
            </div>
            <div style={{ flexShrink: 0, whiteSpace: "nowrap", fontWeight: 650, color: t.type === "income" ? "var(--positive)" : t.type === "expense" ? "var(--negative)" : "var(--text)" }}>
              {t.type === "expense" ? "−" : t.type === "income" ? "+" : "⇄ "}{hidden ? "••••" : format(money(t.amount, t.currency), "en-US")}
            </div>
          </Link>
        ))}
        {rows.length === 0 && <p className="muted" style={{ padding: 16 }}>No matching transactions.</p>}
      </div>
    </div>
  );
}
