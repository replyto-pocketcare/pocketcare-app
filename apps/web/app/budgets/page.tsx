"use client";

import { useEffect, useState } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor, type Money } from "@pocketcare/money";
import { budgetProgress } from "@pocketcare/budget";
import type { Period } from "@pocketcare/types";
import { getRepositories } from "../../src/powersync";
import { insertRow, updateRow, softDelete } from "../../src/write";
import { useBaseCurrency } from "../../src/hooks";
import { ProgressBar } from "../../src/ui/ProgressBar";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { MultiSelect } from "../../src/ui/MultiSelect";
import { LabelPicker } from "../../src/ui/LabelPicker";
import type { BudgetLike } from "@pocketcare/data";

const PERIODS: Period[] = ["daily", "weekly", "monthly", "yearly"];
type TimeMode = "recurring" | "custom";

export default function BudgetsPage() {
  const base = useBaseCurrency();
  const { data: budgets = [] } = useQuery<BudgetLike>(
    "SELECT id, name, scope, scope_ref, category_ids, label_names, period, start_date, end_date, limit_amount, currency, threshold_pct FROM budgets WHERE deleted_at IS NULL ORDER BY created_at DESC",
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

  async function addBudget() {
    if (!limit) return;
    await insertRow("budgets", {
      name: name.trim() || null,
      scope: "overall",
      scope_ref: null,
      category_ids: selCats.join(",") || null,
      label_names: selLabels.join(",") || null,
      period,
      start_date: timeMode === "custom" ? start || null : null,
      end_date: timeMode === "custom" ? end || null : null,
      limit_amount: fromMajor(Number(limit), base).amount,
      currency: base,
      threshold_pct: 80,
      rollover: 0,
    });
    setName(""); setLimit(""); setSelCats([]); setSelLabels([]); setStart(""); setEnd("");
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1>Budgets</h1>
      <div style={{ display: "grid", gap: 12 }}>
        {budgets.map((b) => <BudgetRow key={b.id} budget={b} catName={(id) => cats.find((c) => c.id === id)?.name} />)}
        {budgets.length === 0 && <p className="muted">No budgets yet — try a named budget for a trip below.</p>}
      </div>

      <div className="card" style={{ padding: 20, display: "grid", gap: 12, maxWidth: 560 }}>
        <h2>New budget</h2>
        <FloatingInput label="Name (e.g. Japan Trip)" value={name} onChange={setName} />
        <FloatingInput label={`Limit (${base})`} inputMode="decimal" value={limit} onChange={(v) => setLimit(v.replace(/[^0-9.]/g, ""))} />

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
          <div style={{ display: "flex", gap: 6 }}>
            {PERIODS.map((p) => <button key={p} className="chip" data-active={p === period} onClick={() => setPeriod(p)}>{p}</button>)}
          </div>
        ) : (
          <div style={{ display: "flex", gap: 8 }}>
            <input className="input" type="date" value={start} onChange={(e) => { setStart(e.target.value); if (end && e.target.value > end) setEnd(e.target.value); }} />
            <input className="input" type="date" value={end} min={start || undefined} onChange={(e) => setEnd(e.target.value)} />
          </div>
        )}

        <button className="btn" onClick={addBudget} disabled={!limit || (timeMode === "custom" && (!start || !end))}>Add budget</button>
      </div>
    </div>
  );
}

function BudgetRow({ budget, catName }: { budget: BudgetLike; catName: (id: string) => string | undefined }) {
  const [spent, setSpent] = useState<Money>(money(0, budget.currency));
  useEffect(() => {
    let active = true;
    void getRepositories().budgets.spentThisPeriod(budget).then((s) => active && setSpent(s));
    return () => { active = false; };
  }, [budget]);

  const limit = money(budget.limit_amount, budget.currency);
  const p = budgetProgress(limit, spent, budget.threshold_pct);
  const color = p.overLimit ? "var(--negative)" : p.atOrOverThreshold ? "var(--warning)" : "var(--positive)";
  const remaining = money(Math.max(0, limit.amount - spent.amount), budget.currency);

  const split = (s?: string | null) => (s ?? "").split(",").map((x) => x.trim()).filter(Boolean);
  const catNames = split(budget.category_ids).map((id) => catName(id)).filter(Boolean) as string[];
  const labelNames = split(budget.label_names);
  // Legacy single-scope fallback
  if (catNames.length === 0 && labelNames.length === 0 && budget.scope_ref) {
    if (budget.scope === "category") { const n = catName(budget.scope_ref); if (n) catNames.push(n); }
    else if (budget.scope === "label") labelNames.push(budget.scope_ref);
  }
  const scopeLabel = [...catNames, ...labelNames].join(", ") || "All spending";
  const title = budget.name || scopeLabel;
  const timeframe = budget.start_date && budget.end_date
    ? `${new Date(budget.start_date).toLocaleDateString()} – ${new Date(budget.end_date).toLocaleDateString()}`
    : budget.period;

  const [editing, setEditing] = useState(false);
  const [eName, setEName] = useState(budget.name ?? "");
  const [eLimit, setELimit] = useState(String(toMajor(limit)));
  const [ePeriod, setEPeriod] = useState<Period>(budget.period);
  const [eThreshold, setEThreshold] = useState(String(budget.threshold_pct));

  async function saveEdit() {
    await updateRow("budgets", budget.id, {
      name: eName.trim() || null,
      limit_amount: fromMajor(Number(eLimit) || 0, budget.currency).amount,
      period: ePeriod,
      threshold_pct: Math.min(100, Math.max(1, Number(eThreshold) || 80)),
    });
    setEditing(false);
  }

  return (
    <div className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
      {editing ? (
        <div style={{ display: "grid", gap: 8 }}>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <FloatingInput label="Name (optional)" value={eName} onChange={setEName} style={{ flex: 1, minWidth: 140 }} />
            <FloatingInput label="Limit" inputMode="decimal" value={eLimit} onChange={(v) => setELimit(v.replace(/[^0-9.]/g, ""))} style={{ width: 130 }} />
          </div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
            {!budget.start_date && <div style={{ display: "flex", gap: 6 }}>{PERIODS.map((pp) => <button key={pp} className="chip" data-active={pp === ePeriod} onClick={() => setEPeriod(pp)}>{pp}</button>)}</div>}
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
            <button className="chip" style={{ padding: "2px 8px", fontSize: 12 }} onClick={() => { setEName(budget.name ?? ""); setELimit(String(toMajor(limit))); setEPeriod(budget.period); setEThreshold(String(budget.threshold_pct)); setEditing(true); }}>Edit</button>
            <button className="chip" style={{ padding: "2px 8px" }} onClick={() => softDelete("budgets", budget.id)}>×</button>
          </div>
        </div>
      )}
      <ProgressBar pct={p.pct} color={color} />
      <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }} className="muted">
        <span>{format(spent, "en-US")} spent</span>
        <span>{p.overLimit ? `${format(money(spent.amount - limit.amount, budget.currency), "en-US")} over` : `${format(remaining, "en-US")} left`}</span>
      </div>
    </div>
  );
}
