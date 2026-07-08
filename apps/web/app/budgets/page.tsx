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
import type { BudgetLike } from "@pocketcare/data";

const PERIODS: Period[] = ["daily", "weekly", "monthly", "yearly"];
type TimeMode = "recurring" | "custom";

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
  const [showNew, setShowNew] = useState(false);

  async function addBudget() {
    if (!limit) return;
    const budgetId = await insertRow("budgets", {
      name: name.trim() || null,
      period,
      start_date: timeMode === "custom" ? start || null : null,
      end_date: timeMode === "custom" ? end || null : null,
      limit_amount: fromMajor(Number(limit), base).amount,
      currency: base,
      threshold_pct: 80,
      rollover: 0,
    });
    await writeBudgetScope(budgetId, selCats, selLabels);
    setName(""); setLimit(""); setSelCats([]); setSelLabels([]); setStart(""); setEnd("");
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
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              {PERIODS.map((p) => <button key={p} className="chip" data-active={p === period} onClick={() => setPeriod(p)}>{p}</button>)}
            </div>
          ) : (
            <div style={{ display: "flex", gap: 8 }}>
              <input className="input" type="date" value={start} onChange={(e) => { setStart(e.target.value); if (end && e.target.value > end) setEnd(e.target.value); }} />
              <input className="input" type="date" value={end} min={start || undefined} onChange={(e) => setEnd(e.target.value)} />
            </div>
          )}

          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
            <button className="btn ghost" onClick={() => setShowNew(false)}>Cancel</button>
            <button className="btn" onClick={addBudget} disabled={!limit || (timeMode === "custom" && (!start || !end))}>Add budget</button>
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
  const timeframe = budget.start_date && budget.end_date
    ? `${new Date(budget.start_date).toLocaleDateString()} – ${new Date(budget.end_date).toLocaleDateString()}`
    : budget.period;

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
            <FloatingInput label="Limit" inputMode="decimal" value={eLimit} onChange={(v) => setELimit(v.replace(/[^0-9.]/g, ""))} style={{ width: 130 }} />
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
            <button className="chip" style={{ padding: "2px 8px" }} onClick={() => softDelete("budgets", budget.id)}>×</button>
          </div>
        </div>
      )}
      <ProgressBar pct={p.pct} color={color} />
      <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }} className="muted">
        <span>{fmt(spent)} spent</span>
        <span>{p.overLimit ? `${fmt(money(spent.amount - limit.amount, budget.currency))} over` : `${fmt(remaining)} left`}</span>
      </div>
    </div>
  );
}
