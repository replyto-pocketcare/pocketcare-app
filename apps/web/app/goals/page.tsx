"use client";

import { useTranslation } from "react-i18next";
import { useState } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { insertRow, updateRow, softDelete } from "../../src/write";
import type { CurrencyCode } from "@pocketcare/types";
import { ProgressBar } from "../../src/ui/ProgressBar";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { KebabMenu } from "../../src/ui/KebabMenu";
import { Modal } from "../../src/ui/Modal";

/** Compact, locale-aware currency (e.g. ₹1.5L / ₹10L for INR, $1.2K for USD). */
function compactMoney(minor: number, currency: string): string {
  const locale = currency === "INR" ? "en-IN" : undefined;
  return new Intl.NumberFormat(locale, { style: "currency", currency, notation: "compact", maximumFractionDigits: 1 })
    .format(toMajor(money(minor, currency as CurrencyCode)));
}

interface Goal {
  id: string;
  name: string;
  target_amount: number;
  currency: string;
  is_emergency_fund: number;
  priority: number;
}

export default function GoalsPage() {
  const { t } = useTranslation();
  const base = useBaseCurrency();
  const { data: goals = [] } = useQuery<Goal>(
    "SELECT id, name, target_amount, currency, is_emergency_fund, priority FROM goals WHERE deleted_at IS NULL ORDER BY is_emergency_fund DESC, priority",
  );
  const { data: allocs = [] } = useQuery<{ goal_id: string; amount_blocked: number }>(
    "SELECT goal_id, amount_blocked FROM goal_allocations WHERE deleted_at IS NULL",
  );
  const { data: savings = [] } = useQuery<{ id: string; name: string; currency: string }>(
    "SELECT id, name, currency FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND type = 'savings'",
  );

  const saved = (goalId: string) => allocs.filter((a) => a.goal_id === goalId).reduce((s, a) => s + a.amount_blocked, 0);
  const ef = goals.find((g) => g.is_emergency_fund);
  const efFunded = ef ? saved(ef.id) >= ef.target_amount : true; // no EF => others unlocked

  const [name, setName] = useState("");
  const [target, setTarget] = useState("");
  const [isEf, setIsEf] = useState(false);
  const hasEf = !!ef;

  async function addGoal() {
    if (!name.trim() || !target) return;
    await insertRow("goals", {
      name: name.trim(),
      target_amount: fromMajor(Number(target), base).amount,
      currency: base,
      is_emergency_fund: isEf && !hasEf ? 1 : 0,
      priority: goals.length,
    });
    setName(""); setTarget(""); setIsEf(false);
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1>{t("pages.goals", "Goals")}</h1>
      {ef && !efFunded && (
        <div className="card" style={{ padding: 14, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)" }}>
          Build your emergency fund first — other goals unlock once it’s fully funded.
        </div>
      )}

      <div style={{ display: "grid", gap: 12 }}>
        {goals.map((g) => (
          <GoalCard key={g.id} goal={g} saved={saved(g.id)} savings={savings}
            locked={!g.is_emergency_fund && !efFunded} base={base} />
        ))}
        {goals.length === 0 && <p className="muted">No goals yet. Start with an emergency fund.</p>}
      </div>

      <div className="card" style={{ padding: 20, display: "grid", gap: 10, maxWidth: 460 }}>
        <h2>New goal</h2>
        <FloatingInput label="Goal name" value={name} onChange={setName} />
        <FloatingInput label={`Target (${base})`} inputMode="decimal" value={target} onChange={(v) => setTarget(v.replace(/[^0-9.]/g, ""))} />
        {!hasEf && (
          <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 14 }}>
            <input type="checkbox" checked={isEf} onChange={(e) => setIsEf(e.target.checked)} /> This is my emergency fund (kept liquid, filled first)
          </label>
        )}
        <button className="btn" onClick={addGoal} disabled={!name.trim() || !target}>Add goal</button>
      </div>
    </div>
  );
}

function GoalCard({ goal, saved, savings, locked, base }: {
  goal: Goal; saved: number; savings: { id: string; name: string; currency: string }[]; locked: boolean; base: string;
}) {
  const pct = goal.target_amount ? Math.min(100, (saved / goal.target_amount) * 100) : 0;
  const [amount, setAmount] = useState("");
  const [srcId, setSrcId] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [showAlloc, setShowAlloc] = useState(false);
  const [eName, setEName] = useState(goal.name);
  const [eTarget, setETarget] = useState(String(toMajor(money(goal.target_amount, goal.currency))));

  async function saveEdit() {
    await updateRow("goals", goal.id, { name: eName.trim() || goal.name, target_amount: fromMajor(Number(eTarget) || 0, goal.currency).amount });
    setEditing(false);
  }

  // Simple ETA: assume monthly contribution equal to a typical block, 6% annual.
  async function allocate() {
    const src = srcId ?? savings[0]?.id;
    if (!src || !amount) return;
    await insertRow("goal_allocations", {
      goal_id: goal.id,
      source_account_id: src,
      amount_blocked: fromMajor(Number(amount), goal.currency).amount,
    });
    setAmount("");
    setShowAlloc(false);
  }

  const allocLabel = goal.is_emergency_fund ? "Add funds" : "Block funds";

  return (
    <div className="card" style={{ padding: 20, display: "grid", gap: 10, opacity: locked ? 0.55 : 1 }}>
      {editing ? (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
          <FloatingInput label="Goal name" value={eName} onChange={setEName} style={{ flex: 1, minWidth: 140 }} />
          <FloatingInput label="Target" inputMode="decimal" value={eTarget} onChange={(v) => setETarget(v.replace(/[^0-9.]/g, ""))} style={{ width: 140 }} />
          <button className="btn" onClick={saveEdit}>Save</button>
          <button className="chip" onClick={() => setEditing(false)}>Cancel</button>
        </div>
      ) : (
        <div>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 8 }}>
            <div style={{ minWidth: 0 }}>
              <strong>{goal.name}</strong>
              {goal.is_emergency_fund ? <span className="muted" style={{ fontSize: 12 }}> · emergency fund (liquid)</span> : null}
            </div>
            <KebabMenu
              label={`${goal.name} actions`}
              items={[
                { label: "Edit", onClick: () => { setEName(goal.name); setETarget(String(toMajor(money(goal.target_amount, goal.currency)))); setEditing(true); } },
                { label: "Delete", danger: true, onClick: () => softDelete("goals", goal.id) },
              ]}
            />
          </div>
          <div className="muted" style={{ fontSize: 14, marginTop: 4 }}>
            {compactMoney(saved, goal.currency)} <span style={{ opacity: 0.6 }}>/</span> {compactMoney(goal.target_amount, goal.currency)}
          </div>
        </div>
      )}
      <ProgressBar pct={pct} color={goal.is_emergency_fund ? "var(--sage)" : "var(--accent)"} height={8} />
      {locked ? (
        <span className="muted" style={{ fontSize: 13 }}>Locked until the emergency fund is funded.</span>
      ) : (
        <button className="btn ghost" style={{ justifySelf: "start" }} onClick={() => setShowAlloc(true)} disabled={savings.length === 0}>
          + {allocLabel}
        </button>
      )}

      <Modal open={showAlloc} onClose={() => setShowAlloc(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>{allocLabel} · {goal.name}</h2>
          {savings.length === 0 ? (
            <p className="muted" style={{ margin: 0 }}>Add a savings account first to allocate funds.</p>
          ) : (
            <>
              <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>From account
                <select className="input" value={srcId ?? savings[0]?.id ?? ""} onChange={(e) => setSrcId(e.target.value)}>
                  {savings.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </label>
              <FloatingInput label={`Amount (${goal.currency})`} inputMode="decimal" value={amount} onChange={(v) => setAmount(v.replace(/[^0-9.]/g, ""))} />
              <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
                <button className="btn ghost" onClick={() => setShowAlloc(false)}>Cancel</button>
                <button className="btn" onClick={allocate} disabled={!amount}>{goal.is_emergency_fund ? "Add" : "Block"}</button>
              </div>
            </>
          )}
        </div>
      </Modal>
    </div>
  );
}
