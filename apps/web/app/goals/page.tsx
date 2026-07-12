"use client";

import { useTranslation } from "react-i18next";
import { useState, useEffect, useRef, useCallback } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { insertRow, updateRow, softDelete } from "../../src/write";
import type { CurrencyCode } from "@pocketcare/types";
import { ProgressBar } from "../../src/ui/ProgressBar";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { KebabMenu } from "../../src/ui/KebabMenu";
import { Modal } from "../../src/ui/Modal";
import { useConfirm } from "../../src/ui/Confirm";
import { ListSkeleton } from "../../src/ui/Skeleton";
import { GoalCelebration } from "../../src/goals/GoalCelebration";

// Remember which goals we've already celebrated so completing one is a one-time
// moment (survives reloads), while a goal that dips below target can re-earn it.
const CELEB_KEY = "pc_goals_celebrated";
function celebratedSet(): Set<string> {
  if (typeof localStorage === "undefined") return new Set();
  try { return new Set(JSON.parse(localStorage.getItem(CELEB_KEY) || "[]") as string[]); } catch { return new Set(); }
}
function persistCelebrated(s: Set<string>) {
  try { localStorage.setItem(CELEB_KEY, JSON.stringify([...s])); } catch { /* ignore */ }
}

/** Compact, locale-aware currency (e.g. ₹1.5L / ₹10L for INR, $1.2K for USD). */
function compactMoney(minor: number, currency: string): string {
  const locale = currency === "INR" ? "en-IN" : undefined;
  return new Intl.NumberFormat(locale, { style: "currency", currency, notation: "compact", maximumFractionDigits: 1 })
    .format(toMajor(money(minor, currency as CurrencyCode)));
}

const GOAL_CURRENCIES = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED"];

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
  const { data: goals = [], isLoading: goalsLoading } = useQuery<Goal>(
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
  const [currency, setCurrency] = useState(base);
  const [isEf, setIsEf] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const hasEf = !!ef;

  const [celebrate, setCelebrate] = useState<string | null>(null);
  const onAchieved = useCallback((goalName: string) => setCelebrate(goalName), []);

  async function addGoal() {
    setErr(null);
    if (!name.trim()) { setErr("Give your goal a name."); return; }
    if (!target || Number(target) <= 0) { setErr("Enter a target amount."); return; }
    await insertRow("goals", {
      name: name.trim(),
      target_amount: fromMajor(Number(target), currency).amount,
      currency,
      is_emergency_fund: isEf && !hasEf ? 1 : 0,
      priority: goals.length,
    });
    setName(""); setTarget(""); setCurrency(base); setIsEf(false);
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
            locked={!g.is_emergency_fund && !efFunded} base={base} onAchieved={onAchieved} />
        ))}
        {goals.length === 0 && (goalsLoading ? <ListSkeleton rows={3} /> : <p className="muted">No goals yet. Start with an emergency fund.</p>)}
      </div>

      <div className="card" style={{ padding: 20, display: "grid", gap: 10, maxWidth: 460 }}>
        <h2>New goal</h2>
        <FloatingInput label="Goal name" value={name} onChange={setName} />
        <div style={{ display: "flex", gap: 8 }}>
          <FloatingInput label={`Target (${currency})`} group currency={currency} value={target} onChange={setTarget} style={{ flex: 1 }} />
          <select className="input" value={currency} onChange={(e) => setCurrency(e.target.value)} style={{ width: 96 }}>
            {GOAL_CURRENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>
        {!hasEf && (
          <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 14 }}>
            <input type="checkbox" checked={isEf} onChange={(e) => setIsEf(e.target.checked)} /> This is my emergency fund (kept liquid, filled first)
          </label>
        )}
        {err && <div className="card" style={{ padding: "8px 12px", background: "var(--surface-2)", border: "1px solid var(--negative)", color: "var(--negative)", fontSize: 13 }}>{err}</div>}
        <button className="btn" onClick={addGoal}>Add goal</button>
      </div>

      {celebrate && <GoalCelebration name={celebrate} onClose={() => setCelebrate(null)} />}
    </div>
  );
}

function GoalCard({ goal, saved, savings, locked, base, onAchieved }: {
  goal: Goal; saved: number; savings: { id: string; name: string; currency: string }[]; locked: boolean; base: string;
  onAchieved: (name: string) => void;
}) {
  const confirm = useConfirm();
  const pct = goal.target_amount ? Math.min(100, (saved / goal.target_amount) * 100) : 0;
  const funded = goal.target_amount > 0 && saved >= goal.target_amount;

  // Fire the celebration only on the *transition* into fully-funded (not on load,
  // and not again while it stays funded). prevFunded starts null so the first
  // observed value just seeds the ref.
  const prevFunded = useRef<boolean | null>(null);
  useEffect(() => {
    const was = prevFunded.current;
    prevFunded.current = funded;
    const seen = celebratedSet();
    if (was === false && funded && !seen.has(goal.id)) {
      seen.add(goal.id); persistCelebrated(seen);
      onAchieved(goal.name);
    } else if (!funded && seen.has(goal.id)) {
      seen.delete(goal.id); persistCelebrated(seen); // dropped below → can celebrate again later
    }
  }, [funded, goal.id, goal.name, onAchieved]);
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

  const remaining = Math.max(0, goal.target_amount - saved); // minor units left to fully fund

  async function allocate() {
    const src = srcId ?? savings[0]?.id;
    if (!src || !amount) return;
    // Never allocate beyond the goal's target — cap at what's remaining.
    const capped = Math.min(fromMajor(Number(amount), goal.currency).amount, remaining);
    if (capped <= 0) { setShowAlloc(false); return; }
    await insertRow("goal_allocations", {
      goal_id: goal.id,
      source_account_id: src,
      amount_blocked: capped,
    });
    setAmount("");
    setShowAlloc(false);
  }

  const allocLabel = goal.is_emergency_fund ? "Add funds" : "Block funds";

  return (
    <div className="card" style={{
      padding: 20, display: "grid", gap: 10, opacity: locked ? 0.55 : 1,
      ...(funded ? {
        background: "radial-gradient(130% 120% at 50% 0%, var(--accent-ghost), var(--surface) 68%)",
        borderColor: "var(--accent-soft)",
        boxShadow: "0 0 0 1px var(--accent-soft), var(--shadow)",
      } : {}),
    }}>
      {editing ? (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
          <FloatingInput label="Goal name" value={eName} onChange={setEName} style={{ flex: 1, minWidth: 140 }} />
          <FloatingInput label="Target" group currency={goal.currency} value={eTarget} onChange={setETarget} style={{ width: 140 }} />
          <button className="btn" onClick={saveEdit}>Save</button>
          <button className="chip" onClick={() => setEditing(false)}>Cancel</button>
        </div>
      ) : (
        <div>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 8 }}>
            <div style={{ minWidth: 0 }}>
              <strong>{goal.name}</strong>
              {funded
                ? <span style={{ fontSize: 12, color: "var(--accent)", fontWeight: 600 }}> · 🎉 Funded</span>
                : goal.is_emergency_fund ? <span className="muted" style={{ fontSize: 12 }}> · emergency fund (liquid)</span> : null}
            </div>
            <KebabMenu
              label={`${goal.name} actions`}
              items={[
                { label: "Edit", onClick: () => { setEName(goal.name); setETarget(String(toMajor(money(goal.target_amount, goal.currency)))); setEditing(true); } },
                { label: "Delete", danger: true, onClick: async () => { if (await confirm({ title: "Delete this goal?", message: `“${goal.name}” and its saved allocations will be removed.` })) softDelete("goals", goal.id); } },
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
      ) : funded ? (
        <span style={{ fontSize: 13, color: "var(--accent)", fontWeight: 600 }}>Goal reached — nicely done! ✨</span>
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
              <FloatingInput label={`Amount (${goal.currency})`} group currency={goal.currency} value={amount} onChange={setAmount} />
              <div className="muted" style={{ fontSize: 12, marginTop: -4 }}>
                {compactMoney(remaining, goal.currency)} left to reach your target.
                {amount && fromMajor(Number(amount), goal.currency).amount > remaining ? " We’ll cap this at the remaining amount." : ""}
              </div>
              <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
                <button className="btn ghost" onClick={() => setShowAlloc(false)}>Cancel</button>
                <button className="btn" onClick={allocate} disabled={!amount || remaining <= 0}>{goal.is_emergency_fund ? "Add" : "Block"}</button>
              </div>
            </>
          )}
        </div>
      </Modal>
    </div>
  );
}
