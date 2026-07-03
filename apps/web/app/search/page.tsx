"use client";

import { useTranslation } from "react-i18next";
import { useMemo, useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, format, toMajor } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { AccountBadge } from "../../src/ui/AccountBadge";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { SlidersIcon } from "../../src/ui/icons";
import { useMoneyFmt } from "../../src/ui/Money";
import { colorForId } from "../../src/colors";

const TYPES = ["all", "income", "expense", "transfer"] as const;

export default function SearchPage() {
  const { t } = useTranslation();
  const fmt = useMoneyFmt();
  const [q, setQ] = useState("");
  const [type, setType] = useState<(typeof TYPES)[number]>("all");
  const [accountId, setAccountId] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [min, setMin] = useState("");
  const [max, setMax] = useState("");
  const [showFilters, setShowFilters] = useState(false);
  const activeFilters = [type !== "all", !!accountId, !!from, !!to, !!min, !!max].filter(Boolean).length;
  const clearFilters = () => { setType("all"); setAccountId(""); setFrom(""); setTo(""); setMin(""); setMax(""); };

  const { data: rows = [] } = useQuery<Transaction & { labels: string | null; method_label: string | null }>(
    `SELECT t.*,
       (SELECT GROUP_CONCAT(l.name, ', ') FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id WHERE tl.transaction_id = t.id) AS labels,
       (SELECT pm.label FROM payment_methods pm WHERE pm.id = t.payment_method) AS method_label
     FROM transactions t WHERE t.deleted_at IS NULL AND t.type != 'opening_balance' ORDER BY t.occurred_at DESC LIMIT 2000`,
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories WHERE deleted_at IS NULL");
  const { data: accts = [] } = useQuery<{ id: string; name: string; type: string; color: string | null }>("SELECT id, name, type, color FROM accounts WHERE deleted_at IS NULL");
  const catName = (id: string | null) => cats.find((c) => c.id === id)?.name ?? "";
  const acct = (id: string) => accts.find((a) => a.id === id);

  const results = useMemo(() => {
    const term = q.trim().toLowerCase();
    const minA = min ? Math.round(Number(min) * 100) : null;
    const maxA = max ? Math.round(Number(max) * 100) : null;
    return rows.filter((t) => {
      if (type !== "all" && t.type !== type) return false;
      if (accountId && t.account_id !== accountId && t.to_account_id !== accountId) return false;
      const day = t.occurred_at.slice(0, 10);
      if (from && day < from) return false;
      if (to && day > to) return false;
      if (minA !== null && Math.abs(t.amount) < minA) return false;
      if (maxA !== null && Math.abs(t.amount) > maxA) return false;
      if (term) {
        const a = acct(t.account_id);
        const hay = [
          t.labels, t.note, t.description, t.type, t.method_label, catName(t.category_id),
          a?.name, a?.type, toMajor(money(t.amount, t.currency)).toFixed(2),
        ].filter(Boolean).join(" ").toLowerCase();
        if (!hay.includes(term)) return false;
      }
      return true;
    }).slice(0, 300);
  }, [rows, q, type, accountId, from, to, min, max, cats, accts]);

  return (
    <div style={{ display: "grid", gap: 18 }} className="fade-up">
      <h1>{t("pages.search", "Search")}</h1>

      <input className="input" placeholder="Search everything — label, note, description, category, account, amount…" value={q} onChange={(e) => setQ(e.target.value)} />

      <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        <button className="chip" onClick={() => setShowFilters((v) => !v)} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
          <SlidersIcon size={15} /> Filters{activeFilters > 0 ? ` · ${activeFilters}` : ""} <span style={{ opacity: 0.6 }}>{showFilters ? "▴" : "▾"}</span>
        </button>
        {activeFilters > 0 && <button className="chip" onClick={clearFilters}>Clear</button>}
      </div>

      {showFilters && (
        <div className="card" style={{ padding: 14, display: "grid", gap: 12 }}>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            {TYPES.map((t) => <button key={t} className="chip" data-active={t === type} style={{ textTransform: "capitalize" }} onClick={() => setType(t)}>{t}</button>)}
          </div>
          <select className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            <option value="">All accounts</option>
            {accts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <input className="input" type="date" style={{ flex: "1 1 140px" }} value={from} onChange={(e) => { setFrom(e.target.value); if (to && e.target.value > to) setTo(e.target.value); }} />
            <input className="input" type="date" style={{ flex: "1 1 140px" }} min={from || undefined} value={to} onChange={(e) => setTo(e.target.value)} />
          </div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <FloatingInput label="Min amount" inputMode="decimal" style={{ flex: "1 1 120px" }} value={min} onChange={(v) => setMin(v.replace(/[^0-9.]/g, ""))} />
            <FloatingInput label="Max amount" inputMode="decimal" style={{ flex: "1 1 120px" }} value={max} onChange={(v) => setMax(v.replace(/[^0-9.]/g, ""))} />
          </div>
        </div>
      )}

      <div className="muted" style={{ fontSize: 13 }}>{results.length} result{results.length === 1 ? "" : "s"}</div>

      <div className="card" style={{ padding: 8 }}>
        {results.map((t) => {
          const a = acct(t.account_id);
          return (
            <Link key={t.id} href={`/transactions/${t.id}/edit`} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "12px 14px", borderBottom: "1px solid var(--border)" }}>
              <div style={{ display: "flex", gap: 10, alignItems: "center", minWidth: 0, flex: 1 }}>
                <AccountBadge type={a?.type ?? ""} color={a?.color ?? colorForId(t.account_id)} id={t.account_id} name={a?.name} />
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontWeight: 550, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{t.labels || catName(t.category_id) || t.type}</div>
                  <div className="muted" style={{ fontSize: 12, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                    {new Date(t.occurred_at).toLocaleDateString()} · {t.type}{t.description ? ` · ${t.description}` : ""}
                  </div>
                </div>
              </div>
              <div style={{ flexShrink: 0, whiteSpace: "nowrap", fontWeight: 650, color: t.type === "income" ? "var(--positive)" : t.type === "expense" ? "var(--negative)" : "var(--text)" }}>
                {t.type === "expense" ? "−" : t.type === "income" ? "+" : "⇄ "}{fmt(money(t.amount, t.currency))}
              </div>
            </Link>
          );
        })}
        {results.length === 0 && <p className="muted" style={{ padding: 16 }}>No matching transactions.</p>}
      </div>
    </div>
  );
}
