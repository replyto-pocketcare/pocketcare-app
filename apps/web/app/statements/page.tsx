"use client";

import { useTranslation } from "react-i18next";
import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, format } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { useBaseCurrency } from "../../src/hooks";
import { useEntitlement } from "../../src/entitlement";
import { LockIcon } from "../../src/ui/icons";

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
          <div style={{ fontSize: 30, fontWeight: 780, letterSpacing: "-0.02em", whiteSpace: "nowrap", color: income - expense >= 0 ? "var(--positive)" : "var(--negative)" }}>
            {format(money(income - expense, base), "en-US")}
          </div>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10 }}>
          <Summary label={t("income")} value={format(money(income, base), "en-US")} color="var(--positive)" />
          <Summary label={t("expenses")} value={format(money(expense, base), "en-US")} color="var(--negative)" />
          <Summary label={t("transactions")} value={String(rows.length)} />
        </div>
      </section>

      {/* Transaction tiles, grouped by day (newest first) */}
      {rows.length === 0 ? (
        <p className="muted card" style={{ padding: 16, margin: 0 }}>{t("noTransactions")}</p>
      ) : (
        <div style={{ display: "grid", gap: 16, minWidth: 0 }}>
          {groupByDay(rows, t).map(({ day, label, items, net }) => (
            <section key={day} style={{ display: "grid", gap: 8, minWidth: 0 }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8, padding: "0 4px", minWidth: 0 }}>
                <span className="eyebrow" style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{label}</span>
                <span className="muted" style={{ fontSize: 12, whiteSpace: "nowrap", flexShrink: 0 }}>{net >= 0 ? "+" : "−"}{format(money(Math.abs(net), base), "en-US")}</span>
              </div>
              <div className="card" style={{ padding: 0, overflow: "hidden" }}>
                {items.map((r, i) => <TxnTile key={r.id} r={r} first={i === 0} category={catName(r.category_id)} />)}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}

function Summary({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div style={{ minWidth: 0 }}>
      <div className="muted" style={{ fontSize: 11.5, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{label}</div>
      <div style={{ fontWeight: 700, fontSize: 15.5, color, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{value}</div>
    </div>
  );
}

type Row = Transaction & { labels: string | null };

const AV = ["#b06a4f", "#5f7a52", "#c08a3e", "#7a4a6b", "#2f6f6a", "#7c4a3a", "#9cae8e"];
const avColor = (s: string) => AV[[...s].reduce((a, c) => a + c.charCodeAt(0), 0) % AV.length]!;

/** Pull a readable name out of a bank/UPI narration ("UPI/ASHISH ALA/…" → "ASHISH ALA"). */
function merchantTitle(desc: string): string {
  const parts = desc.split("/").map((s) => s.trim()).filter(Boolean);
  if (parts.length >= 2 && /^(upi|imps|neft|ach|bil|inft|rtgs|nach|pos)$/i.test(parts[0]!)) {
    const name = parts.slice(1).find((p) => /[a-z]{3,}/i.test(p) && !/^\d+$/.test(p));
    return (name || parts[1]!).slice(0, 34);
  }
  return desc.slice(0, 40);
}

function TxnTile({ r, first, category }: { r: Row; first: boolean; category: string }) {
  const base = useBaseCurrency();
  const raw = (r.labels || r.description || r.type).trim();
  const title = merchantTitle(raw);
  const time = new Date(r.occurred_at).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  const sign = r.type === "expense" ? "−" : r.type === "income" ? "+" : "";
  const color = r.type === "income" ? "var(--positive)" : r.type === "expense" ? "var(--text)" : "var(--text)";
  return (
    <div style={{ display: "flex", gap: 12, alignItems: "flex-start", padding: "12px 14px", borderTop: first ? "none" : "1px solid var(--border)" }}>
      <span aria-hidden style={{ width: 34, height: 34, flexShrink: 0, borderRadius: 999, background: avColor(title), color: "#fff", display: "grid", placeItems: "center", fontSize: 14, fontWeight: 700 }}>{(title[0] || "•").toUpperCase()}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 600 }}>{title}</div>
        <div className="muted" style={{ fontSize: 11.5, lineHeight: 1.45, overflowWrap: "anywhere", wordBreak: "break-word" }}>{raw !== title ? raw : category}</div>
      </div>
      <div style={{ textAlign: "right", flexShrink: 0 }}>
        <div style={{ fontSize: 14.5, fontWeight: 700, whiteSpace: "nowrap", color }}>{sign}{format(money(r.amount, r.currency), "en-US")}</div>
        <div className="muted" style={{ fontSize: 11, whiteSpace: "nowrap" }}>{time}</div>
      </div>
    </div>
  );
}

/** Group rows by calendar day, newest first, with a friendly label + day net. */
function groupByDay(rows: Row[], t: (k: string) => string): { day: string; label: string; items: Row[]; net: number }[] {
  const map = new Map<string, Row[]>();
  for (const r of rows) {
    const day = r.occurred_at.slice(0, 10);
    (map.get(day) ?? map.set(day, []).get(day)!).push(r);
  }
  const todayStr = new Date().toISOString().slice(0, 10);
  const yStr = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);
  return [...map.entries()]
    .sort((a, b) => b[0].localeCompare(a[0]))
    .map(([day, items]) => {
      const sorted = [...items].sort((a, b) => b.occurred_at.localeCompare(a.occurred_at));
      const net = sorted.reduce((s, r) => s + (r.type === "income" ? r.amount : r.type === "expense" ? -r.amount : 0), 0);
      const label = day === todayStr ? t("today") : day === yStr ? t("yesterday")
        : new Date(day + "T00:00:00").toLocaleDateString(undefined, { day: "numeric", month: "short", year: "2-digit" });
      return { day, label, items: sorted, net };
    });
}
