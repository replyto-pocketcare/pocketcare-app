"use client";

import { useState } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor } from "@pocketcare/money";
import { monthlyEquivalent, recurringMonthlyTotal, subscriptionImpact } from "@pocketcare/finance";
import type { Period } from "@pocketcare/types";
import Link from "next/link";
import { useBaseCurrency, useTier } from "../../src/hooks";
import { insertRow, updateRow, softDelete } from "../../src/write";
import { LockIcon } from "../../src/ui/icons";
import { FloatingInput } from "../../src/ui/FloatingInput";

interface Sub {
  id: string;
  name: string;
  amount: number;
  currency: string;
  billing_cycle: Period;
  purchased_on: string | null;
}

const CYCLES: Period[] = ["daily", "weekly", "monthly", "yearly"];

/** Next renewal date from a purchase/start date + billing cycle. */
function nextDue(purchasedOn: string | null, cycle: Period, asOf = new Date()): Date | null {
  if (!purchasedOn) return null;
  const d = new Date(purchasedOn);
  if (Number.isNaN(d.getTime())) return null;
  const add = (dt: Date) => {
    const n = new Date(dt);
    if (cycle === "daily") n.setDate(n.getDate() + 1);
    else if (cycle === "weekly") n.setDate(n.getDate() + 7);
    else if (cycle === "monthly") n.setMonth(n.getMonth() + 1);
    else n.setFullYear(n.getFullYear() + 1);
    return n;
  };
  let next = new Date(d);
  let guard = 0;
  while (next <= asOf && guard++ < 5000) next = add(next);
  return next;
}

export default function SubscriptionsPage() {
  const base = useBaseCurrency();
  const tier = useTier();
  const { data: subs = [] } = useQuery<Sub>(
    "SELECT id, name, amount, currency, billing_cycle, purchased_on FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1 ORDER BY created_at",
  );

  const monthlyTotal = recurringMonthlyTotal(subs.map((s) => ({ amount: s.amount, frequency: s.billing_cycle })));

  const [name, setName] = useState("");
  const [amount, setAmount] = useState("");
  const [cycle, setCycle] = useState<Period>("monthly");
  const [purchased, setPurchased] = useState(new Date().toISOString().slice(0, 10));

  async function addSub() {
    if (!name.trim() || !amount) return;
    await insertRow("subscriptions", {
      name: name.trim(),
      amount: fromMajor(Number(amount), base).amount,
      currency: base,
      billing_cycle: cycle,
      purchased_on: purchased || null,
      next_renewal: nextDue(purchased, cycle)?.toISOString().slice(0, 10) ?? null,
      is_active: 1,
    });
    setName(""); setAmount("");
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1>Subscriptions</h1>

      <section className="card" style={{ padding: 20, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div>
          <div className="muted" style={{ fontSize: 13 }}>Total monthly cost</div>
          <div style={{ fontSize: 30, fontWeight: 750 }}>{format(money(monthlyTotal, base), "en-US")}</div>
        </div>
        <div className="muted" style={{ fontSize: 13, textAlign: "right" }}>{subs.length} active · {format(money(monthlyTotal * 12, base), "en-US")}/yr</div>
      </section>

      <div style={{ display: "grid", gap: 10 }}>
        {subs.map((s) => (
          <SubRow key={s.id} sub={s} />
        ))}
        {subs.length === 0 && <p className="muted">No subscriptions yet.</p>}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 20 }} className="dash-cols">
        <div className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
          <h2>Add subscription</h2>
          <FloatingInput label="Name" value={name} onChange={setName} />
          <FloatingInput label={`Amount (${base})`} inputMode="decimal" value={amount} onChange={(v) => setAmount(v.replace(/[^0-9.]/g, ""))} />
          <div style={{ display: "flex", gap: 6 }}>
            {CYCLES.map((c) => <button key={c} className="chip" data-active={c === cycle} onClick={() => setCycle(c)}>{c}</button>)}
          </div>
          <label className="muted" style={{ fontSize: 12 }}>Purchased / started on
            <input className="input" type="date" value={purchased} onChange={(e) => setPurchased(e.target.value)} />
          </label>
          {purchased && <span className="muted" style={{ fontSize: 12 }}>Next due: {nextDue(purchased, cycle)?.toLocaleDateString()}</span>}
          <button className="btn" onClick={addSub} disabled={!name.trim() || !amount}>Add</button>
        </div>

        {tier === "premium" ? (
          <Simulator base={base} />
        ) : (
          <div className="card" style={{ padding: 20, display: "grid", gap: 10, textAlign: "center", background: "var(--surface-2)" }}>
            <div style={{ display: "flex", justifyContent: "center", color: "var(--text-2)" }}><LockIcon size={28} /></div>
            <h2>Impact simulator</h2>
            <p className="muted" style={{ fontSize: 13 }}>See a subscription’s true long-term cost before you commit. Premium.</p>
            <Link href="/settings" className="btn" style={{ justifySelf: "center" }}>Go Premium</Link>
          </div>
        )}
      </div>
    </div>
  );
}

function SubRow({ sub }: { sub: Sub }) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(sub.name);
  const [amount, setAmount] = useState(String(toMajor(money(sub.amount, sub.currency))));
  const [cycle, setCycle] = useState<Period>(sub.billing_cycle);
  const [purchased, setPurchased] = useState(sub.purchased_on ?? "");

  async function save() {
    await updateRow("subscriptions", sub.id, {
      name: name.trim() || sub.name,
      amount: fromMajor(Number(amount) || 0, sub.currency).amount,
      billing_cycle: cycle,
      purchased_on: purchased || null,
      next_renewal: nextDue(purchased || null, cycle)?.toISOString().slice(0, 10) ?? null,
    });
    setEditing(false);
  }

  if (editing) {
    return (
      <div className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <FloatingInput label="Name" value={name} onChange={setName} style={{ flex: 1, minWidth: 140 }} />
          <FloatingInput label="Amount" inputMode="decimal" value={amount} onChange={(v) => setAmount(v.replace(/[^0-9.]/g, ""))} style={{ width: 120 }} />
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
          <div style={{ display: "flex", gap: 6 }}>{CYCLES.map((c) => <button key={c} className="chip" data-active={c === cycle} onClick={() => setCycle(c)}>{c}</button>)}</div>
          <input className="input" type="date" style={{ width: 160 }} value={purchased} onChange={(e) => setPurchased(e.target.value)} />
          <button className="btn" onClick={save}>Save</button>
          <button className="chip" onClick={() => setEditing(false)}>Cancel</button>
        </div>
      </div>
    );
  }

  return (
    <div className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
      <div>
        <strong>{sub.name}</strong>
        <div className="muted" style={{ fontSize: 12 }}>
          {format(money(sub.amount, sub.currency), "en-US")} / {sub.billing_cycle} · {format(money(monthlyEquivalent(sub.amount, sub.billing_cycle), sub.currency), "en-US")}/mo
          {nextDue(sub.purchased_on, sub.billing_cycle) && <> · next due {nextDue(sub.purchased_on, sub.billing_cycle)!.toLocaleDateString()}</>}
        </div>
      </div>
      <div style={{ display: "flex", gap: 6 }}>
        <button className="chip" onClick={() => setEditing(true)}>Edit</button>
        <button className="chip" onClick={() => softDelete("subscriptions", sub.id)}>Remove</button>
      </div>
    </div>
  );
}

/** Pre-purchase impact simulator (feature #11): total paid vs opportunity cost. */
function Simulator({ base }: { base: string }) {
  const [amount, setAmount] = useState("15");
  const [cycle, setCycle] = useState<Period>("monthly");
  const [years, setYears] = useState("5");
  const [ret, setRet] = useState("8");

  const impact = subscriptionImpact(
    fromMajor(Number(amount) || 0, base).amount,
    cycle,
    Number(years) || 0,
    Number(ret) || 0,
  );

  return (
    <div className="card" style={{ padding: 20, display: "grid", gap: 10, background: "var(--surface-2)" }}>
      <h2>Before you subscribe…</h2>
      <p className="muted" style={{ fontSize: 13, marginTop: -4 }}>See the true long-term cost of a new subscription.</p>
      <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
        <FloatingInput label={`Amount (${base})`} inputMode="decimal" value={amount} onChange={(v) => setAmount(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
        <div style={{ display: "flex", gap: 6 }}>
          {CYCLES.map((c) => <button key={c} className="chip" data-active={c === cycle} onClick={() => setCycle(c)}>{c[0].toUpperCase()}</button>)}
        </div>
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        <FloatingInput label="Years" inputMode="numeric" value={years} onChange={(v) => setYears(v.replace(/\D/g, ""))} style={{ flex: 1 }} />
        <FloatingInput label="Return %" inputMode="decimal" value={ret} onChange={(v) => setRet(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", paddingTop: 8, borderTop: "1px solid var(--border)" }}>
        <div><div className="muted" style={{ fontSize: 12 }}>You’d pay</div><strong>{format(money(impact.totalPaid, base), "en-US")}</strong></div>
        <div style={{ textAlign: "right" }}><div className="muted" style={{ fontSize: 12 }}>If invested instead</div><strong style={{ color: "var(--positive)" }}>{format(money(impact.opportunityCost, base), "en-US")}</strong></div>
      </div>
    </div>
  );
}
