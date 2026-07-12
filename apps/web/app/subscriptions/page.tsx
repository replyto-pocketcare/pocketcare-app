"use client";

import { useTranslation } from "react-i18next";
import { useState } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor } from "@pocketcare/money";
import { monthlyEquivalent, recurringMonthlyTotal, subscriptionImpact } from "@pocketcare/finance";
import type { Period } from "@pocketcare/types";
import Link from "next/link";
import { useBaseCurrency } from "../../src/hooks";
import { useEntitlement } from "../../src/entitlement";
import { insertRow, updateRow, softDelete } from "../../src/write";
import { LockIcon } from "../../src/ui/icons";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { KebabMenu } from "../../src/ui/KebabMenu";
import { useMoneyFmt } from "../../src/ui/Money";
import { Modal } from "../../src/ui/Modal";

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
  const { t } = useTranslation();
  const base = useBaseCurrency();
  const { isPaid } = useEntitlement();
  const fmt = useMoneyFmt();
  const { data: subs = [] } = useQuery<Sub>(
    "SELECT id, name, amount, currency, billing_cycle, purchased_on FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1 ORDER BY created_at",
  );

  const monthlyTotal = recurringMonthlyTotal(subs.map((s) => ({ amount: s.amount, frequency: s.billing_cycle })));

  const [name, setName] = useState("");
  const [amount, setAmount] = useState("");
  const [cycle, setCycle] = useState<Period>("monthly");
  const [purchased, setPurchased] = useState(new Date().toISOString().slice(0, 10));
  const [showAdd, setShowAdd] = useState(false);
  const [showSim, setShowSim] = useState(false);

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
    setShowAdd(false);
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>{t("pages.subscriptions", "Subscriptions")}</h1>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <button className="btn ghost" onClick={() => setShowSim(true)}>Before you subscribe…</button>
          {subs.length > 0 && <button className="btn" onClick={() => setShowAdd(true)}>+ Add subscription</button>}
        </div>
      </div>

      <section className="card" style={{ padding: 20, display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12, flexWrap: "wrap" }}>
        <div>
          <div className="muted" style={{ fontSize: 13 }}>Total monthly cost</div>
          <div style={{ fontSize: 30, fontWeight: 750 }}>{fmt(money(monthlyTotal, base))}</div>
        </div>
        <div className="muted" style={{ fontSize: 13 }}>{subs.length} active · {fmt(money(monthlyTotal * 12, base))}/yr</div>
      </section>

      {subs.length > 0 ? (
        <div style={{ display: "grid", gap: 10, minWidth: 0 }}>
          {subs.map((s) => <SubRow key={s.id} sub={s} />)}
        </div>
      ) : (
        <div className="card" style={{ padding: 32, textAlign: "center", display: "grid", gap: 10, justifyItems: "center" }}>
          <div style={{ fontSize: 26 }}>↻</div>
          <h2 style={{ margin: 0 }}>No subscriptions yet</h2>
          <p className="muted" style={{ margin: 0, maxWidth: 360 }}>Track Netflix, Spotify, iCloud and the rest to see your true monthly and yearly load.</p>
          <button className="btn" onClick={() => setShowAdd(true)}>+ Add your first subscription</button>
        </div>
      )}

      {/* Add subscription dialog */}
      <Modal open={showAdd} onClose={() => setShowAdd(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>Add subscription</h2>
          <FloatingInput label="Name" value={name} onChange={setName} />
          <FloatingInput label={`Amount (${base})`} inputMode="decimal" value={amount} onChange={(v) => setAmount(v.replace(/[^0-9.]/g, ""))} />
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            {CYCLES.map((c) => <button key={c} className="chip" data-active={c === cycle} onClick={() => setCycle(c)}>{c}</button>)}
          </div>
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>Purchased / started on
            <input className="input" type="date" value={purchased} onChange={(e) => setPurchased(e.target.value)} />
          </label>
          {purchased && <span className="muted" style={{ fontSize: 12 }}>Next due: {nextDue(purchased, cycle)?.toLocaleDateString()}</span>}
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
            <button className="btn ghost" onClick={() => setShowAdd(false)}>Cancel</button>
            <button className="btn" onClick={addSub} disabled={!name.trim() || !amount}>Add</button>
          </div>
        </div>
      </Modal>

      {/* Before you subscribe… dialog */}
      <Modal open={showSim} onClose={() => setShowSim(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>Before you subscribe…</h2>
          {isPaid ? (
            <Simulator base={base} />
          ) : (
            <div style={{ display: "grid", gap: 10, textAlign: "center", justifyItems: "center" }}>
              <div style={{ color: "var(--text-2)" }}><LockIcon size={28} /></div>
              <p className="muted" style={{ fontSize: 13, margin: 0 }}>See a subscription’s true long-term cost before you commit — a Premium feature.</p>
              <Link href="/settings" className="btn" onClick={() => setShowSim(false)}>Go Premium</Link>
            </div>
          )}
        </div>
      </Modal>
    </div>
  );
}

function SubRow({ sub }: { sub: Sub }) {
  const fmt = useMoneyFmt();
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

  const due = nextDue(sub.purchased_on, sub.billing_cycle);
  return (
    <div className="card" style={{ padding: 16, display: "grid", gap: 12 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 8 }}>
        <strong style={{ fontSize: 15 }}>{sub.name}</strong>
        <KebabMenu
          label={`${sub.name} actions`}
          items={[
            { label: "Edit", onClick: () => setEditing(true) },
            { label: "Remove", danger: true, onClick: () => softDelete("subscriptions", sub.id) },
          ]}
        />
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: "10px 22px" }}>
        <Stat value={fmt(money(sub.amount, sub.currency))} label={`per ${sub.billing_cycle.replace(/ly$/, "").replace("dai", "day")}`} />
        <Stat value={fmt(money(monthlyEquivalent(sub.amount, sub.billing_cycle), sub.currency))} label="per month" />
        {due && <Stat value={due.toLocaleDateString()} label="next due" />}
      </div>
    </div>
  );
}

function Stat({ value, label }: { value: string; label: string }) {
  return (
    <div style={{ display: "grid", gap: 2 }}>
      <span style={{ fontWeight: 600, fontSize: 14 }}>{value}</span>
      <span className="muted" style={{ fontSize: 11, textTransform: "capitalize" }}>{label}</span>
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
    <div style={{ display: "grid", gap: 10 }}>
      <p className="muted" style={{ fontSize: 13, margin: 0 }}>See the true long-term cost of a new subscription.</p>
      <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
        <FloatingInput label={`Amount (${base})`} inputMode="decimal" value={amount} onChange={(v) => setAmount(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
        <div style={{ display: "flex", gap: 6 }}>
          {CYCLES.map((c) => <button key={c} className="chip" data-active={c === cycle} onClick={() => setCycle(c)}>{c.charAt(0).toUpperCase()}</button>)}
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
