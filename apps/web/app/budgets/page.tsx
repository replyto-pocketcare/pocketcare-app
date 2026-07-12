"use client";

import { useTranslation } from "react-i18next";
import { useEffect, useState } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor, type Money } from "@pocketcare/money";
import { budgetProgress } from "@pocketcare/budget";
import type { Period } from "@pocketcare/types";
import { getRepositories, getDb, getUserId } from "../../src/powersync";
import { insertRow, updateRow, softDelete, uuid, nowIso } from "../../src/write";
import { useBaseCurrency } from "../../src/hooks";
import { ProgressBar } from "../../src/ui/ProgressBar";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { useMoneyFmt } from "../../src/ui/Money";
import { MultiSelect } from "../../src/ui/MultiSelect";
import { LabelPicker } from "../../src/ui/LabelPicker";
import { Modal } from "../../src/ui/Modal";
import { useConfirm } from "../../src/ui/Confirm";
import { ResponsiveContainer, AreaChart, Area, XAxis, YAxis, ReferenceLine, Tooltip } from "recharts";
import type { BudgetLike } from "@pocketcare/data";

const PERIODS: Period[] = ["daily", "weekly", "monthly", "yearly"];
const CURRENCIES = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED"];
type TimeMode = "recurring" | "custom";

const isoDay = (d: Date) => d.toISOString().slice(0, 10);
const fmtDay = (s: string) => new Date(s + (s.length <= 10 ? "T00:00:00" : "")).toLocaleDateString(undefined, { day: "numeric", month: "short" });

/** The active date window + label for a budget (current period for recurring). */
function periodWindow(b: BudgetLike): { start: string; end: string; label: string } {
  if (b.start_date && b.end_date) return { start: b.start_date.slice(0, 10), end: b.end_date.slice(0, 10), label: `${fmtDay(b.start_date)} – ${fmtDay(b.end_date)}` };
  const now = new Date();
  let s: Date, e: Date;
  if (b.period === "daily") { s = new Date(now.getFullYear(), now.getMonth(), now.getDate()); e = new Date(s); }
  else if (b.period === "weekly") { const dow = (now.getDay() + 6) % 7; s = new Date(now.getFullYear(), now.getMonth(), now.getDate() - dow); e = new Date(s); e.setDate(e.getDate() + 6); }
  else if (b.period === "yearly") { s = new Date(now.getFullYear(), 0, 1); e = new Date(now.getFullYear(), 11, 31); }
  else { s = new Date(now.getFullYear(), now.getMonth(), 1); e = new Date(now.getFullYear(), now.getMonth() + 1, 0); }
  return { start: isoDay(s), end: isoDay(e), label: `${fmtDay(isoDay(s))} – ${fmtDay(isoDay(e))}` };
}

/** Find-or-create label rows by name, returning their ids. */
async function resolveLabelIds(names: string[]): Promise<string[]> {
  const db = getDb();
  if (!db) return [];
  const userId = getUserId();
  const ids: string[] = [];
  const seen = new Set<string>();
  for (const raw of names) {
    const name = raw.trim();
    if (!name || seen.has(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    const found = await db.getOptional<{ id: string }>(
      "SELECT id FROM labels WHERE user_id = ? AND name = ? AND deleted_at IS NULL",
      [userId, name],
    );
    if (found) ids.push(found.id);
    else {
      const id = uuid();
      const ts = nowIso();
      await db.execute(
        "INSERT INTO labels (id,user_id,name,color,created_at,updated_at) VALUES (?,?,?,?,?,?)",
        [id, userId, name, null, ts, ts],
      );
      ids.push(id);
    }
  }
  return ids;
}

/** Rewrite a budget's category/label scope via the junction tables. */
async function writeBudgetScope(budgetId: string, catIds: string[], labelNames: string[]): Promise<void> {
  const db = getDb();
  if (!db) return;
  const userId = getUserId();
  await db.execute("DELETE FROM budget_categories WHERE budget_id = ?", [budgetId]);
  await db.execute("DELETE FROM budget_labels WHERE budget_id = ?", [budgetId]);
  for (const cid of [...new Set(catIds)]) {
    await db.execute(
      "INSERT INTO budget_categories (id,user_id,budget_id,category_id) VALUES (?,?,?,?)",
      [uuid(), userId, budgetId, cid],
    );
  }
  const labelIds = await resolveLabelIds(labelNames);
  for (const lid of labelIds) {
    await db.execute(
      "INSERT INTO budget_labels (id,user_id,budget_id,label_id) VALUES (?,?,?,?)",
      [uuid(), userId, budgetId, lid],
    );
  }
}

export default function BudgetsPage() {
  const { t } = useTranslation();
  const base = useBaseCurrency();
  const { data: budgets = [] } = useQuery<BudgetLike>(
    "SELECT id, name, period, start_date, end_date, limit_amount, currency, threshold_pct FROM budgets WHERE deleted_at IS NULL ORDER BY created_at DESC",
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories WHERE deleted_at IS NULL AND kind='expense' ORDER BY name");
  const { data: labels = [] } = useQuery<{ id: string; name: string; color: string | null }>("SELECT id, name, color FROM labels WHERE deleted_at IS NULL ORDER BY name");
  const catOptions = cats.map((c) => ({ value: c.id, label: c.name }));

  const [name, setName] = useState("");
  const [limit, setLimit] = useState("");
  const [selCats, setSelCats] = useState<string[]>([]);
  const [selLabels, setSelLabels] = useState<string[]>([]);
  const [timeMode, setTimeMode] = useState<TimeMode>("recurring");
  const [period, setPeriod] = useState<Period>("monthly");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [threshold, setThreshold] = useState("80");
  const [currency, setCurrency] = useState(base);
  const [showNew, setShowNew] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function addBudget() {
    setErr(null);
    if (!limit || Number(limit) <= 0) { setErr("Enter a spending limit."); return; }
    if (timeMode === "custom" && (!start || !end)) { setErr("Pick a start and end date."); return; }
    const budgetId = await insertRow("budgets", {
      name: name.trim() || null,
      period,
      start_date: timeMode === "custom" ? start || null : null,
      end_date: timeMode === "custom" ? end || null : null,
      limit_amount: fromMajor(Number(limit), currency).amount,
      currency,
      threshold_pct: Math.min(100, Math.max(1, Number(threshold) || 80)),
      rollover: 0,
    });
    await writeBudgetScope(budgetId, selCats, selLabels);
    setName(""); setLimit(""); setSelCats([]); setSelLabels([]); setStart(""); setEnd(""); setThreshold("80"); setCurrency(base);
    setShowNew(false);
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>{t("pages.budgets", "Budgets")}</h1>
        <button className="btn" onClick={() => setShowNew(true)}>+ New budget</button>
      </div>

      {budgets.length > 0 ? (
        <div style={{ display: "grid", gap: 12 }}>
          {budgets.map((b) => <BudgetRow key={b.id} budget={b} cats={cats} labels={labels} catOptions={catOptions} />)}
        </div>
      ) : (
        <div className="card" style={{ padding: 32, textAlign: "center", display: "grid", gap: 10, justifyItems: "center" }}>
          <div style={{ fontSize: 26 }}>◔</div>
          <h2 style={{ margin: 0 }}>No budgets yet</h2>
          <p className="muted" style={{ margin: 0, maxWidth: 380 }}>Set a spending cap for a category, a label, or a whole trip — recurring or for custom dates.</p>
          <button className="btn" onClick={() => setShowNew(true)}>+ Create your first budget</button>
        </div>
      )}

      <Modal open={showNew} onClose={() => setShowNew(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>New budget</h2>
          <FloatingInput label="Name (e.g. Japan Trip)" value={name} onChange={setName} />
          <div style={{ display: "flex", gap: 8 }}>
            <FloatingInput label={`Limit (${currency})`} group currency={currency} value={limit} onChange={setLimit} style={{ flex: 1 }} />
            <select className="input" value={currency} onChange={(e) => setCurrency(e.target.value)} style={{ width: 96 }}>
              {CURRENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>
          <label className="muted" style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 8 }}>
            Alert me at
            <input className="input" style={{ width: 72 }} inputMode="numeric" value={threshold} onChange={(e) => setThreshold(e.target.value.replace(/\D/g, ""))} />
            % of the limit
          </label>

          <span className="muted" style={{ fontSize: 13 }}>Categories (optional — leave empty for all spending)</span>
          <MultiSelect options={catOptions} selected={selCats} onChange={setSelCats} placeholder="Add categories…" />

          <span className="muted" style={{ fontSize: 13 }}>Labels (optional)</span>
          <LabelPicker labels={labels} selected={selLabels} onChange={setSelLabels} />

          <span className="muted" style={{ fontSize: 13 }}>Timeframe</span>
          <div style={{ display: "flex", gap: 6 }}>
            <button className="chip" data-active={timeMode === "recurring"} onClick={() => setTimeMode("recurring")}>Recurring</button>
            <button className="chip" data-active={timeMode === "custom"} onClick={() => setTimeMode("custom")}>Custom dates</button>
          </div>
          {timeMode === "recurring" ? (
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              {PERIODS.map((p) => <button key={p} className="chip" data-active={p === period} onClick={() => setPeriod(p)}>{p}</button>)}
            </div>
          ) : (
            <div style={{ display: "flex", gap: 8 }}>
              <input className="input" type="date" value={start} onChange={(e) => { setStart(e.target.value); if (end && e.target.value > end) setEnd(e.target.value); }} />
              <input className="input" type="date" value={end} min={start || undefined} onChange={(e) => setEnd(e.target.value)} />
            </div>
          )}

          {err && <div className="card" style={{ padding: "8px 12px", background: "var(--surface-2)", border: "1px solid var(--negative)", color: "var(--negative)", fontSize: 13 }}>{err}</div>}
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
            <button className="btn ghost" onClick={() => setShowNew(false)}>Cancel</button>
            <button className="btn" onClick={addBudget}>Add budget</button>
          </div>
        </div>
      </Modal>
    </div>
  );
}

function BudgetRow({ budget, cats, labels, catOptions }: {
  budget: BudgetLike;
  cats: { id: string; name: string }[];
  labels: { id: string; name: string; color: string | null }[];
  catOptions: { value: string; label: string }[];
}) {
  const [spent, setSpent] = useState<Money>(money(0, budget.currency));
  const fmt = useMoneyFmt();
  const confirm = useConfirm();
  // This budget's scope, from the junction tables.
  const { data: budgetCats = [] } = useQuery<{ category_id: string }>("SELECT category_id FROM budget_categories WHERE budget_id = ?", [budget.id]);
  const { data: budgetLabels = [] } = useQuery<{ name: string }>(
    "SELECT l.name FROM budget_labels bl JOIN labels l ON l.id = bl.label_id WHERE bl.budget_id = ?",
    [budget.id],
  );
  const catIds = budgetCats.map((r) => r.category_id);
  const labelNames = budgetLabels.map((r) => r.name);

  useEffect(() => {
    let active = true;
    void getRepositories().budgets.spentThisPeriod(budget).then((s) => active && setSpent(s));
    return () => { active = false; };
    // Recompute when scope changes too.
  }, [budget, catIds.join(","), labelNames.join(",")]);

  const limit = money(budget.limit_amount, budget.currency);
  const p = budgetProgress(limit, spent, budget.threshold_pct);
  const color = p.overLimit ? "var(--negative)" : p.atOrOverThreshold ? "var(--warning)" : "var(--positive)";
  const remaining = money(Math.max(0, limit.amount - spent.amount), budget.currency);

  const catNames = catIds.map((id) => cats.find((c) => c.id === id)?.name).filter(Boolean) as string[];
  const scopeLabel = [...catNames, ...labelNames].join(", ") || "All spending";
  const title = budget.name || scopeLabel;
  const win = periodWindow(budget);
  const timeframe = budget.start_date && budget.end_date ? win.label : `${budget.period} · ${win.label}`;

  const [editing, setEditing] = useState(false);
  const [eName, setEName] = useState(budget.name ?? "");
  const [eLimit, setELimit] = useState(String(toMajor(limit)));
  const [ePeriod, setEPeriod] = useState<Period>(budget.period);
  const [eThreshold, setEThreshold] = useState(String(budget.threshold_pct));
  const [eCats, setECats] = useState<string[]>([]);
  const [eLabels, setELabels] = useState<string[]>([]);

  function openEdit() {
    setEName(budget.name ?? "");
    setELimit(String(toMajor(limit)));
    setEPeriod(budget.period);
    setEThreshold(String(budget.threshold_pct));
    setECats(catIds);
    setELabels(labelNames);
    setEditing(true);
  }

  async function saveEdit() {
    await updateRow("budgets", budget.id, {
      name: eName.trim() || null,
      limit_amount: fromMajor(Number(eLimit) || 0, budget.currency).amount,
      period: ePeriod,
      threshold_pct: Math.min(100, Math.max(1, Number(eThreshold) || 80)),
    });
    await writeBudgetScope(budget.id, eCats, eLabels);
    setEditing(false);
  }

  return (
    <div className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
      {editing ? (
        <div style={{ display: "grid", gap: 8 }}>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <FloatingInput label="Name (optional)" value={eName} onChange={setEName} style={{ flex: 1, minWidth: 140 }} />
            <FloatingInput label="Limit" group currency={budget.currency} value={eLimit} onChange={setELimit} style={{ width: 130 }} />
          </div>
          <span className="muted" style={{ fontSize: 12 }}>Categories (empty = all spending)</span>
          <MultiSelect options={catOptions} selected={eCats} onChange={setECats} placeholder="Add categories…" />
          <span className="muted" style={{ fontSize: 12 }}>Labels</span>
          <LabelPicker labels={labels} selected={eLabels} onChange={setELabels} />
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
            {!budget.start_date && <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>{PERIODS.map((pp) => <button key={pp} className="chip" data-active={pp === ePeriod} onClick={() => setEPeriod(pp)}>{pp}</button>)}</div>}
            <label className="muted" style={{ fontSize: 12, display: "flex", alignItems: "center", gap: 6 }}>Alert at
              <input className="input" style={{ width: 70 }} inputMode="numeric" value={eThreshold} onChange={(e) => setEThreshold(e.target.value.replace(/\D/g, ""))} />%
            </label>
            <button className="btn" onClick={saveEdit}>Save</button>
            <button className="chip" onClick={() => setEditing(false)}>Cancel</button>
          </div>
        </div>
      ) : (
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <div>
            <span style={{ fontWeight: 600 }}>{title}</span>
            <span className="muted" style={{ fontSize: 12 }}> · {timeframe}{budget.name && scopeLabel !== "All spending" ? ` · ${scopeLabel}` : ""}</span>
          </div>
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <span className="muted">{Number.isFinite(p.pct) ? `${Math.round(p.pct)}%` : "—"}</span>
            <button className="chip" style={{ padding: "2px 8px", fontSize: 12 }} onClick={openEdit}>Edit</button>
            <button className="chip" style={{ padding: "2px 8px" }} aria-label="Delete budget"
              onClick={async () => { if (await confirm({ title: "Delete this budget?", message: `“${title}” will be removed. This can't be undone.` })) softDelete("budgets", budget.id); }}>×</button>
          </div>
        </div>
      )}
      <ProgressBar pct={p.pct} color={color} />
      <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }} className="muted">
        <span>{fmt(spent)} spent</span>
        <span>{p.overLimit ? `${fmt(money(spent.amount - limit.amount, budget.currency))} over` : `${fmt(remaining)} left`}</span>
      </div>
      {!editing && <BudgetSpendChart budget={budget} catIds={catIds} labelNames={labelNames} win={win} limitMajor={toMajor(limit)} color={color} />}
    </div>
  );
}

/** Cumulative expenditure across the budget's active window, vs the limit line. */
function BudgetSpendChart({ budget, catIds, labelNames, win, limitMajor, color }: {
  budget: BudgetLike; catIds: string[]; labelNames: string[]; win: { start: string; end: string }; limitMajor: number; color: string;
}) {
  const { data: rows = [] } = useQuery<{ d: string; amount: number; category_id: string | null; lbls: string | null }>(
    `SELECT date(occurred_at) AS d, amount, category_id,
       (SELECT GROUP_CONCAT(l.name) FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id WHERE tl.transaction_id = t.id) AS lbls
     FROM transactions t WHERE deleted_at IS NULL AND type='expense' AND occurred_at >= ? AND occurred_at <= ? ORDER BY d`,
    [win.start + "T00:00:00", win.end + "T23:59:59"],
  );
  const hasCat = catIds.length > 0, hasLbl = labelNames.length > 0;
  const perDay = new Map<string, number>();
  for (const r of rows) {
    const catOk = hasCat && r.category_id ? catIds.includes(r.category_id) : false;
    const lblOk = hasLbl && r.lbls ? r.lbls.split(",").some((n) => labelNames.includes(n.trim())) : false;
    if ((!hasCat && !hasLbl) || catOk || lblOk) perDay.set(r.d, (perDay.get(r.d) ?? 0) + r.amount);
  }

  // Build a cumulative series across the window — only the days that have already
  // happened (up to today), never future days of the period.
  const start = new Date(win.start + "T00:00:00"), end = new Date(win.end + "T00:00:00");
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const lastDay = end < today ? end : today; // clamp to today
  const spanDays = Math.max(1, Math.round((lastDay.getTime() - start.getTime()) / 86400000) + 1);
  const step = spanDays > 92 ? 7 : 1;
  const series: { label: string; cum: number }[] = [];
  let cum = 0;
  for (let i = 0; i < spanDays; i++) {
    const day = new Date(start); day.setDate(day.getDate() + i);
    if (day > today) break;
    cum += (perDay.get(isoDay(day)) ?? 0);
    if (i % step === 0 || i === spanDays - 1) series.push({ label: fmtDay(isoDay(day)), cum: cum / 100 });
  }
  if (series.length < 2) return null;

  return (
    <ResponsiveContainer width="100%" height={120}>
      <AreaChart data={series} margin={{ top: 6, right: 6, bottom: 0, left: 0 }}>
        <defs>
          <linearGradient id={`gBud-${budget.id}`} x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor={color} stopOpacity={0.35} /><stop offset="100%" stopColor={color} stopOpacity={0.02} /></linearGradient>
        </defs>
        <XAxis dataKey="label" tick={{ fontSize: 10, fill: "var(--text-2)" }} axisLine={false} tickLine={false} interval="preserveStartEnd" minTickGap={24} />
        <YAxis hide />
        <Tooltip formatter={(v: number) => v.toLocaleString()} labelStyle={{ fontSize: 11 }} contentStyle={{ fontSize: 11, borderRadius: 8 }} />
        {limitMajor > 0 && <ReferenceLine y={limitMajor} stroke="var(--text-2)" strokeDasharray="4 4" strokeOpacity={0.7} />}
        <Area type="monotone" dataKey="cum" stroke={color} strokeWidth={2} fill={`url(#gBud-${budget.id})`} dot={false} />
      </AreaChart>
    </ResponsiveContainer>
  );
}
