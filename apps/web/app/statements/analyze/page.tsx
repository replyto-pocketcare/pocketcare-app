"use client";

/**
 * Statement Parser & Analyzer (on-device). Upload a bank or credit-card
 * statement (CSV/Excel-export or PDF), parse it locally, categorise, analyse
 * (spend breakdown, trend, outliers, recurring), reconcile against recorded
 * transactions, and import what's missing. Nothing leaves the device.
 */
import { useMemo, useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import {
  ResponsiveContainer, PieChart, Pie, Cell, Tooltip, BarChart, Bar, XAxis, YAxis, CartesianGrid,
} from "recharts";
import { money, fromMajor } from "@pocketcare/money";
import { useBaseCurrency, useAccountBalances } from "../../../src/hooks";
import { useMoneyFmt } from "../../../src/ui/Money";
import { getDb, getUserId } from "../../../src/powersync";
import { suggestCategory } from "../../../src/categorize/engine";
import { importTransactions } from "../../../src/data/importCsv";
import { createRecurring } from "../../../src/cashflow/recurring";
import type { CanonRow } from "../../../src/data/adapters";
import { parseStatementCsv } from "../../../src/statements/parseCsv";
import { extractPdfText, parseStatementText } from "../../../src/statements/parsePdf";
import { summarize, byCategory, byDay, outliers as findOutliers, recurringCandidates } from "../../../src/statements/analysis";
import { reconcile, type RecordedTxn } from "../../../src/statements/reconcile";
import type { ParsedStatement, StatementKind } from "../../../src/statements/types";

const EARTH = ["#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#7c4a3a", "#2f6f6a", "#c98a72", "#7c7264"];
const AXIS = { fontSize: 11, fill: "var(--text-2)" } as const;

export default function AnalyzeStatementPage() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const accounts = useAccountBalances();
  const { data: categories = [] } = useQuery<{ id: string; name: string; kind: string }>("SELECT id, name, kind FROM categories WHERE deleted_at IS NULL");

  const [kind, setKind] = useState<StatementKind>("bank");
  const [accountId, setAccountId] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [parsed, setParsed] = useState<ParsedStatement | null>(null);

  const accountName = accounts.find((a) => a.account.id === accountId)?.account.name ?? "";
  const cur = parsed?.currency || base;

  async function handleFile(file: File) {
    setError(null); setParsed(null);
    try {
      let ps: ParsedStatement;
      if (/\.pdf$/i.test(file.name)) {
        setBusy("Reading PDF…");
        let text: string;
        try { text = await extractPdfText(file); }
        catch (e) {
          if (/password/i.test((e as Error).message)) {
            const pw = window.prompt("This PDF is password-protected. Enter its password:");
            if (!pw) { setBusy(null); return; }
            text = await extractPdfText(file, pw);
          } else throw e;
        }
        ps = parseStatementText(text, { currency: base, kind });
      } else {
        setBusy("Parsing…");
        const text = await file.text();
        ps = parseStatementCsv(text, { currency: base, kind });
      }
      // On-device categorisation of spends.
      setBusy("Categorising…");
      const db = getDb();
      if (db && ps.txns.length) {
        const uid = getUserId();
        const catName = new Map(categories.map((c) => [c.id, c.name]));
        for (const t of ps.txns) {
          if (t.amount >= 0) continue;
          try {
            const id = await suggestCategory(t.description, db, uid, categories as never);
            if (id) t.category = catName.get(id) ?? null;
          } catch { /* categoriser optional */ }
        }
      }
      setParsed(ps);
    } catch (e) {
      setError((e as Error).message || "Couldn't read that file.");
    } finally {
      setBusy(null);
    }
  }

  if (!parsed) {
    return (
      <div style={{ display: "grid", gap: 20, maxWidth: 640 }} className="fade-up">
        <div>
          <h1 style={{ margin: 0 }}>Analyze a statement</h1>
          <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>Upload a bank or credit-card statement — it's parsed <strong>entirely on your device</strong> and never uploaded. <Link href="/statements">Back to statements</Link>.</p>
        </div>
        <section className="card" style={{ padding: 20, display: "grid", gap: 14 }}>
          <div style={{ display: "grid", gap: 4 }}>
            <span className="muted" style={{ fontSize: 12 }}>Statement type</span>
            <div style={{ display: "flex", gap: 6 }}>
              <button className="chip" data-active={kind === "bank"} onClick={() => setKind("bank")}>Bank</button>
              <button className="chip" data-active={kind === "card"} onClick={() => setKind("card")}>Credit card</button>
            </div>
          </div>
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>Account to reconcile / import into
            <select className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
              <option value="">Choose later</option>
              {accounts.map((a) => <option key={a.account.id} value={a.account.id}>{a.account.name}</option>)}
            </select>
          </label>
          <label className="btn" style={{ justifySelf: "start", cursor: "pointer" }}>
            {busy ?? "Choose file (CSV or PDF)"}
            <input type="file" accept=".csv,.txt,.pdf" hidden disabled={!!busy}
              onChange={(e) => { const f = e.target.files?.[0]; if (f) void handleFile(f); e.target.value = ""; }} />
          </label>
          {error && <div style={{ color: "var(--negative)", fontSize: 13 }}>{error}</div>}
          <p className="muted" style={{ fontSize: 11.5, margin: 0 }}>Tip: most banks let you download a <strong>CSV/Excel</strong> statement — that parses most reliably. PDF works for digital (non-scanned) statements.</p>
        </section>
      </div>
    );
  }

  return <Results parsed={parsed} base={base} cur={cur} fmt={fmt} accountId={accountId} accountName={accountName} onReset={() => setParsed(null)} />;
}

function Results({ parsed, base, cur, fmt, accountId, accountName, onReset }: {
  parsed: ParsedStatement; base: string; cur: string; fmt: (m: import("@pocketcare/money").Money) => string;
  accountId: string; accountName: string; onReset: () => void;
}) {
  const [showAll, setShowAll] = useState(false);
  const [imported, setImported] = useState(false);
  const [addedRecurring, setAddedRecurring] = useState<Set<string>>(new Set());

  const s = useMemo(() => summarize(parsed.txns), [parsed]);
  const cats = useMemo(() => byCategory(parsed.txns), [parsed]);
  const days = useMemo(() => byDay(parsed.txns), [parsed]);
  const outliers = useMemo(() => findOutliers(parsed.txns), [parsed]);
  const recurring = useMemo(() => recurringCandidates(parsed.txns).filter((r) => r.cadence !== "irregular").slice(0, 6), [parsed]);

  // Recorded transactions for this account (to reconcile against).
  const { data: recorded = [] } = useQuery<{ id: string; amount: number; type: string; occurred_at: string; description: string | null }>(
    accountId
      ? `SELECT id, amount, type, occurred_at, description FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense') AND (account_id = ? OR to_account_id = ?)`
      : "SELECT id, amount, type, occurred_at, description FROM transactions WHERE 1=0",
    accountId ? [accountId, accountId] : [],
  );
  const recRows: RecordedTxn[] = useMemo(() => recorded
    .filter((r) => parsed.period.from && parsed.period.to ? r.occurred_at.slice(0, 10) >= parsed.period.from && r.occurred_at.slice(0, 10) <= addDays(parsed.period.to, 4) : true)
    .map((r) => ({ id: r.id, amount: r.type === "income" ? r.amount : -r.amount, date: r.occurred_at.slice(0, 10), description: r.description ?? "" })), [recorded, parsed.period]);
  const rec = useMemo(() => reconcile(parsed.txns, recRows), [parsed, recRows]);

  async function importMissing() {
    if (!accountName) return;
    const rows: CanonRow[] = rec.missingOnPlatform.map((t) => ({
      date: `${t.date}T12:00:00`,
      type: t.amount < 0 ? "expense" as const : "income" as const,
      amount: Math.abs(t.amount) / 100,
      currency: cur,
      account: accountName,
      description: t.description,
      ...(t.category ? { category: t.category } : {}),
    }));
    await importTransactions(rows, { skipDuplicates: false });
    setImported(true);
  }

  async function addRecurring(key: string, label: string, amountMinor: number, cadence: string) {
    const freq = cadence === "weekly" ? "weekly" : cadence === "yearly" ? "yearly" : "monthly";
    await createRecurring({ direction: "payment", name: label.slice(0, 40), amount: amountMinor / 100, accountId: accountId || null, frequency: freq, firstDue: new Date().toISOString().slice(0, 10), autoPost: false });
    setAddedRecurring((prev) => new Set(prev).add(key));
  }

  const donut = cats.slice(0, 7).map((c, i) => ({ name: c.name, value: Math.round(c.total / 100), color: EARTH[i % EARTH.length] }));
  const trend = days.map((d) => ({ x: d.date.slice(5), y: Math.round(d.debit / 100) }));
  const shown = showAll ? parsed.txns : parsed.txns.slice(0, 12);

  return (
    <div style={{ display: "grid", gap: 20, minWidth: 0 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <div>
          <h1 style={{ margin: 0 }}>{parsed.label}</h1>
          <p className="muted" style={{ margin: "2px 0 0", fontSize: 13 }}>{parsed.period.from && parsed.period.to ? `${parsed.period.from} → ${parsed.period.to} · ` : ""}{parsed.txns.length} transactions{accountName ? ` · ${accountName}` : ""}</p>
        </div>
        <button className="btn ghost" onClick={onReset}>New statement</button>
      </div>

      {parsed.warnings.length > 0 && (
        <div style={{ padding: "9px 12px", borderRadius: 10, fontSize: 12.5, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)", color: "var(--text-2)" }}>
          {parsed.warnings.map((w, i) => <div key={i}>⚠ {w}</div>)}
        </div>
      )}

      {/* Summary stats */}
      <div className="pc-hero">
        <Stat label="Money in" value={fmt(money(s.credits, cur))} color="var(--positive)" />
        <Stat label="Money out" value={fmt(money(s.debits, cur))} color="var(--negative)" />
        <Stat label="Net" value={`${s.net >= 0 ? "+" : "−"}${fmt(money(Math.abs(s.net), cur))}`} color={s.net >= 0 ? "var(--positive)" : "var(--negative)"} />
        {parsed.closingBalance != null && <Stat label="Closing balance" value={fmt(money(parsed.closingBalance, cur))} />}
      </div>

      {/* Credit-card specifics */}
      {parsed.kind === "card" && (parsed.card?.totalDue != null || parsed.card?.dueDate) && (
        <section className="card pc-glass" style={{ padding: 18, display: "flex", gap: 24, flexWrap: "wrap" }}>
          {parsed.card?.totalDue != null && <Stat label="Total due" value={fmt(money(parsed.card.totalDue, cur))} />}
          {parsed.card?.minDue != null && <Stat label="Minimum due" value={fmt(money(parsed.card.minDue, cur))} />}
          {parsed.card?.dueDate && <Stat label="Pay by" value={new Date(parsed.card.dueDate).toLocaleDateString()} color="var(--negative)" />}
        </section>
      )}

      {/* Analysis charts */}
      <section style={{ display: "grid", gap: 12, gridTemplateColumns: "repeat(auto-fit, minmax(min(280px,100%),1fr))", minWidth: 0 }}>
        <div className="card pc-glass" style={{ padding: 16, display: "grid", gap: 8 }}>
          <div className="eyebrow">Where it went</div>
          {donut.length ? (
            <ResponsiveContainer width="100%" height={220}>
              <PieChart>
                <Pie data={donut} dataKey="value" nameKey="name" innerRadius={58} outerRadius={92} paddingAngle={2} stroke="var(--surface)" strokeWidth={2}>
                  {donut.map((d, i) => <Cell key={i} fill={d.color} />)}
                </Pie>
                <Tooltip content={({ active, payload }) => active && payload?.length ? <Tip label={String(payload[0]!.name)} value={fmt(money(Number(payload[0]!.value) * 100, cur))} /> : null} />
              </PieChart>
            </ResponsiveContainer>
          ) : <Empty />}
        </div>
        <div className="card pc-glass" style={{ padding: 16, display: "grid", gap: 8 }}>
          <div className="eyebrow">Daily spend</div>
          {trend.length ? (
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={trend} margin={{ top: 8, right: 6, bottom: 0, left: -12 }}>
                <defs><linearGradient id="stmtBar" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#b06a4f" stopOpacity={0.95} /><stop offset="100%" stopColor="#b06a4f" stopOpacity={0.45} /></linearGradient></defs>
                <CartesianGrid vertical={false} stroke="var(--border)" />
                <XAxis dataKey="x" tick={AXIS} axisLine={false} tickLine={false} interval="preserveStartEnd" minTickGap={16} />
                <YAxis tick={AXIS} axisLine={false} tickLine={false} width={40} />
                <Tooltip cursor={{ fill: "var(--surface-2)" }} content={({ active, payload }) => active && payload?.length ? <Tip label={String(payload[0]!.payload.x)} value={fmt(money(Number(payload[0]!.value) * 100, cur))} /> : null} />
                <Bar dataKey="y" radius={[5, 5, 0, 0]} maxBarSize={30} fill="url(#stmtBar)" />
              </BarChart>
            </ResponsiveContainer>
          ) : <Empty />}
        </div>
      </section>

      {/* Outliers */}
      {outliers.length > 0 && (
        <section className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
          <div className="eyebrow">Outliers · unusually large</div>
          {outliers.slice(0, 5).map((o, i) => (
            <div key={i} style={{ display: "flex", justifyContent: "space-between", gap: 10, fontSize: 13 }}>
              <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{o.txn.description} <span className="muted">· {o.txn.date}</span></span>
              <strong style={{ color: "var(--negative)", flexShrink: 0 }}>{fmt(money(o.amount, cur))}</strong>
            </div>
          ))}
        </section>
      )}

      {/* Recurring detection */}
      {recurring.length > 0 && (
        <section className="card" style={{ padding: 16, display: "grid", gap: 10 }}>
          <div className="eyebrow">Looks recurring</div>
          {recurring.map((r) => (
            <div key={r.key} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
              <div style={{ minWidth: 0 }}>
                <div style={{ fontSize: 13.5, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{r.label}</div>
                <div className="muted" style={{ fontSize: 11.5 }}>{fmt(money(r.amount, cur))} · {r.cadence} · seen {r.count}×</div>
              </div>
              {addedRecurring.has(r.key)
                ? <span className="chip" style={{ color: "var(--positive)" }}>Added ✓</span>
                : <button className="chip" onClick={() => void addRecurring(r.key, r.label, r.amount, r.cadence)}>Add as recurring</button>}
            </div>
          ))}
        </section>
      )}

      {/* Reconciliation */}
      <section className="card" style={{ padding: 16, display: "grid", gap: 10 }}>
        <div className="eyebrow">Reconcile with your records</div>
        {!accountId ? (
          <p className="muted" style={{ fontSize: 13, margin: 0 }}>Pick an account when uploading to match these against your recorded transactions.</p>
        ) : (
          <>
            <div style={{ display: "flex", gap: 16, flexWrap: "wrap", fontSize: 13 }}>
              <span><strong style={{ color: "var(--positive)" }}>{rec.matched.length}</strong> matched</span>
              <span><strong style={{ color: "var(--accent)" }}>{rec.missingOnPlatform.length}</strong> in statement, not recorded</span>
              <span><strong className="muted">{rec.onlyOnPlatform.length}</strong> recorded, not in statement</span>
            </div>
            {rec.missingOnPlatform.length > 0 && !imported && (
              <button className="btn" style={{ justifySelf: "start", whiteSpace: "normal", textAlign: "left", maxWidth: "100%", height: "auto", minHeight: 0, padding: "8px 14px" }} onClick={() => void importMissing()}>Import {rec.missingOnPlatform.length} missing into {accountName}</button>
            )}
            {imported && <div style={{ color: "var(--positive)", fontSize: 13 }}>✓ Imported. They now appear in your transactions.</div>}
          </>
        )}
      </section>

      {/* Full transaction list (collapsible) */}
      <section style={{ display: "grid", gap: 8 }}>
        <div className="eyebrow">Transactions ({parsed.txns.length})</div>
        <div className="card" style={{ padding: 0, overflow: "hidden" }}>
          {shown.map((t, i) => (
            <div key={i} style={{ padding: "10px 14px", display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, borderTop: i === 0 ? "none" : "1px solid var(--border)" }}>
              <div style={{ minWidth: 0 }}>
                <div style={{ fontSize: 13.5, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{t.description}</div>
                <div className="muted" style={{ fontSize: 11.5 }}>{t.date}{t.category ? ` · ${t.category}` : ""}</div>
              </div>
              <strong style={{ flexShrink: 0, color: t.amount >= 0 ? "var(--positive)" : "var(--text)" }}>{t.amount >= 0 ? "+" : "−"}{fmt(money(Math.abs(t.amount), cur))}</strong>
            </div>
          ))}
        </div>
        {parsed.txns.length > 12 && <button className="chip" style={{ justifySelf: "start" }} onClick={() => setShowAll((v) => !v)}>{showAll ? "Show less" : `Show all ${parsed.txns.length}`}</button>}
      </section>
    </div>
  );
}

function Stat({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="card" style={{ padding: 16, display: "grid", gap: 4 }}>
      <span className="eyebrow">{label}</span>
      <div style={{ fontSize: 20, fontWeight: 720, letterSpacing: "-0.01em", color }}>{value}</div>
    </div>
  );
}
function Tip({ label, value }: { label: string; value: string }) {
  return <div style={{ background: "var(--surface)", border: "1px solid var(--border-strong)", borderRadius: 10, padding: "6px 10px", boxShadow: "var(--shadow)", fontSize: 12 }}><span className="muted">{label}</span> <strong>{value}</strong></div>;
}
function Empty() { return <div style={{ height: 220, display: "grid", placeItems: "center", color: "var(--text-3)", fontSize: 13 }}>No spends to chart</div>; }

const addDays = (iso: string, n: number) => { const d = new Date(iso + "T00:00:00"); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
