"use client";

import { useTranslation } from "react-i18next";
import { useState, useEffect, useRef, useCallback } from "react";
import { useSearchParams } from "next/navigation";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor } from "@sanvya/money";
import { useBaseCurrency } from "../../src/hooks";
import type { CurrencyCode } from "@sanvya/types";
import { ProgressBar } from "../../src/ui/ProgressBar";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { utcToLocalTime, localToUtcTime } from "../../src/time";
import { KebabMenu } from "../../src/ui/KebabMenu";
import { Modal } from "../../src/ui/Modal";
import { useConfirm } from "../../src/ui/Confirm";
import { ListSkeleton } from "../../src/ui/Skeleton";
import { GoalCelebration } from "../../src/goals/GoalCelebration";
import { MaterialIcon } from "../../src/ui/MaterialIcon";

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
  const { t } = useTranslation("goals");
  const searchParams = useSearchParams();
  const editId = searchParams?.get("edit");
  const base = useBaseCurrency();
  const { data: goals = [], isLoading: goalsLoading } = useQuery<Goal & { alert_time_utc: string }>(
    "SELECT id, name, target_amount, currency, is_emergency_fund, priority, alert_time_utc FROM goals WHERE deleted_at IS NULL ORDER BY is_emergency_fund DESC, priority",
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
  const [alertTime, setAlertTime] = useState("09:00");
  const [err, setErr] = useState<string | null>(null);
  const hasEf = !!ef;

  const [celebrate, setCelebrate] = useState<string | null>(null);
  const onAchieved = useCallback((goalName: string) => setCelebrate(goalName), []);
  const [addOpen, setAddOpen] = useState(false);

  async function addGoal() {
    setErr(null);
    if (!name.trim()) { setErr(t("errName")); return; }
    if (!target || Number(target) <= 0) { setErr(t("errTarget")); return; }
    await insertRow("goals", {
      name: name.trim(),
      target_amount: fromMajor(Number(target), currency).amount,
      currency,
      is_emergency_fund: isEf && !hasEf ? 1 : 0,
      priority: goals.length,
      alert_time_utc: localToUtcTime(alertTime),
    });
    setName(""); setTarget(""); setCurrency(base); setIsEf(false); setAlertTime("09:00");
    setAddOpen(false);
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>{t("title")}</h1>
        <button className="btn" onClick={() => { setErr(null); setAddOpen(true); }}>+ {t("addGoal")}</button>
      </div>
      {ef && !efFunded && (
        <div className="card" style={{ padding: 14, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)" }}>
          {t("efFirst")}
        </div>
      )}

      <div className="list-grid">
        {goals.map((g) => (
          <GoalCard key={g.id} goal={g} saved={saved(g.id)} savings={savings}
            locked={!g.is_emergency_fund && !efFunded} base={base} onAchieved={onAchieved} autoOpen={editId === g.id} />
        ))}
        {goals.length === 0 && (goalsLoading ? <ListSkeleton rows={3} /> : <p className="muted">{t("noGoals")}</p>)}
      </div>

      <Modal open={addOpen} onClose={() => setAddOpen(false)}>
        <div style={{ display: "grid", gap: 10 }}>
          <h2 style={{ margin: 0 }}>{t("newGoal")}</h2>
          <FloatingInput label={t("goalName")} value={name} onChange={setName} />
          <div style={{ display: "flex", gap: 8 }}>
            <FloatingInput label={t("target", { currency })} group currency={currency} value={target} onChange={setTarget} style={{ flex: 1 }} />
            <select className="input" value={currency} onChange={(e) => setCurrency(e.target.value)} style={{ width: 96 }}>
              {GOAL_CURRENCIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>
          <label className="muted" style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13 }}>
            Alert time
            <input type="time" className="input" value={alertTime} onChange={(e) => setAlertTime(e.target.value)} />
          </label>
          {!hasEf && (
            <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 14 }}>
              <input type="checkbox" checked={isEf} onChange={(e) => setIsEf(e.target.checked)} /> {t("efCheckbox")}
            </label>
          )}
          {err && <div className="card" style={{ padding: "8px 12px", background: "var(--surface-2)", border: "1px solid var(--negative)", color: "var(--negative)", fontSize: 13 }}>{err}</div>}
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
            <button className="btn ghost" onClick={() => setAddOpen(false)}>{t("cancel", "Cancel")}</button>
            <button className="btn" onClick={addGoal}>{t("addGoal")}</button>
          </div>
        </div>
      </Modal>

      {celebrate && <GoalCelebration name={celebrate} onClose={() => setCelebrate(null)} />}
    </div>
  );
}

function GoalCard({ goal, saved, savings, locked, base, onAchieved, autoOpen }: {
  goal: Goal & { alert_time_utc: string }; saved: number; savings: { id: string; name: string; currency: string }[]; locked: boolean; base: string;
  onAchieved: (name: string) => void;
  autoOpen?: boolean;
}) {
  const { t } = useTranslation("goals");
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
  useEffect(() => {
    if (autoOpen) {
      setEditing(true);
      setTimeout(() => {
        document.getElementById(goal.id)?.scrollIntoView({ behavior: "smooth", block: "center" });
      }, 100);
    }
  }, [autoOpen, goal.id]);
  const [showAlloc, setShowAlloc] = useState(false);
  const [eName, setEName] = useState(goal.name);
  const [eTarget, setETarget] = useState(String(toMajor(money(goal.target_amount, goal.currency))));
  const [eAlertTime, setEAlertTime] = useState(utcToLocalTime(goal.alert_time_utc));

  async function saveEdit() {
    await updateRow("goals", goal.id, {
      name: eName.trim() || goal.name,
      target_amount: fromMajor(Number(eTarget) || 0, goal.currency).amount,
      alert_time_utc: localToUtcTime(eAlertTime),
    });
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

  const allocLabel = goal.is_emergency_fund ? t("addFunds") : t("blockFunds");

  return (
    <div id={goal.id} className="card" style={{
      padding: 20, display: "grid", gap: 10, opacity: locked ? 0.55 : 1,
      ...(funded ? {
        background: "radial-gradient(130% 120% at 50% 0%, var(--accent-ghost), var(--surface) 68%)",
        borderColor: "var(--accent-soft)",
        boxShadow: "0 0 0 1px var(--accent-soft), var(--shadow)",
      } : {}),
    }}>
      {editing ? (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
          <FloatingInput label={t("goalName")} value={eName} onChange={setEName} style={{ flex: 1, minWidth: 140 }} />
          <FloatingInput label={t("target", { currency: goal.currency })} group currency={goal.currency} value={eTarget} onChange={setETarget} style={{ width: 140 }} />
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <label className="muted" style={{ fontSize: 12, display: "flex", alignItems: "center", gap: 6 }}>
              Alert at
              <input type="time" className="input" style={{ fontSize: 12 }} value={eAlertTime} onChange={(e) => setEAlertTime(e.target.value)} />
            </label>
            <button className="btn" onClick={saveEdit}>{t("save")}</button>
            <button className="chip" onClick={() => setEditing(false)}>{t("cancel")}</button>
          </div>
        </div>
      ) : (
        <div>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 8 }}>
            <div style={{ minWidth: 0 }}>
              <strong>{goal.name}</strong>
              {funded
                ? <span style={{ fontSize: 12, color: "var(--accent)", fontWeight: 600, display: "inline-flex", alignItems: "center", gap: 4 }}> · <MaterialIcon name="check" size={13} /> {t("funded")}</span>
                : goal.is_emergency_fund ? <span className="muted" style={{ fontSize: 12 }}> · {t("efLiquid")}</span> : null}
            </div>
            <KebabMenu
              label={t("goalActions", { name: goal.name })}
              items={[
                { label: t("edit"), onClick: () => { setEName(goal.name); setETarget(String(toMajor(money(goal.target_amount, goal.currency)))); setEAlertTime(utcToLocalTime(goal.alert_time_utc)); setEditing(true); } },
                { label: t("delete"), danger: true, onClick: async () => { if (await confirm({ title: t("deleteTitle"), message: t("deleteMsg", { name: goal.name }) })) softDelete("goals", goal.id); } },
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
        <span className="muted" style={{ fontSize: 13 }}>{t("lockedUntil")}</span>
      ) : funded ? (
        <span style={{ fontSize: 13, color: "var(--accent)", fontWeight: 600 }}>{t("goalReached")}</span>
      ) : (
        <button className="btn ghost" style={{ justifySelf: "start" }} onClick={() => setShowAlloc(true)} disabled={savings.length === 0}>
          + {allocLabel}
        </button>
      )}

      <Modal open={showAlloc} onClose={() => setShowAlloc(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>{allocLabel} · {goal.name}</h2>
          {savings.length === 0 ? (
            <p className="muted" style={{ margin: 0 }}>{t("addSavingsFirst")}</p>
          ) : (
            <>
              <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>{t("fromAccount")}
                <select className="input" value={srcId ?? savings[0]?.id ?? ""} onChange={(e) => setSrcId(e.target.value)}>
                  {savings.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </label>
              <FloatingInput label={t("amount", { currency: goal.currency })} group currency={goal.currency} value={amount} onChange={setAmount} />
              <div className="muted" style={{ fontSize: 12, marginTop: -4 }}>
                {t("leftToTarget", { amount: compactMoney(remaining, goal.currency) })}
                {amount && fromMajor(Number(amount), goal.currency).amount > remaining ? t("willCap") : ""}
              </div>
              <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
                <button className="btn ghost" onClick={() => setShowAlloc(false)}>{t("cancel")}</button>
                <button className="btn" onClick={allocate} disabled={!amount || remaining <= 0}>{goal.is_emergency_fund ? t("add") : t("block")}</button>
              </div>
            </>
          )}
        </div>
      </Modal>
    </div>
  );
}
