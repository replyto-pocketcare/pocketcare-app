"use client";

import { useState } from "react";
import { useEntitlement } from "../entitlement";
import { PLANS, CREDIT_PACKS, price, type PaidTier, type Cycle } from "../billing/plans";
import { startSubscription, buyCredits, cancelSubscription } from "../billing";
import { useTier, setTier } from "../tier";

const FREE_FEATURES = ["All account types (bank, cash, cards, stocks…)", "Categories, labels, budgets, goals", "Transactions, transfers, search"];
const PAID_EXTRA = ["Detailed Insights & Statements", "Ask PocketCare AI assistant", "Auto-categorisation, upcoming, stock sync", "CSV import"];

export function Billing() {
  const e = useEntitlement();
  const devTier = useTier();
  const [cycle, setCycle] = useState<Cycle>("monthly");
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  async function run(id: string, fn: () => Promise<{ ok: boolean }>, okMsg: string) {
    setBusy(id); setMsg(null);
    try { const r = await fn(); setMsg(r.ok ? okMsg : "Checkout was closed."); }
    catch (err) { setMsg((err as Error).message); }
    finally { setBusy(null); }
  }

  const planCard = (tier: PaidTier) => {
    const p = PLANS[tier];
    const isCurrent = e.tier === tier;
    return (
      <div key={tier} className="card" style={{ padding: 16, display: "grid", gap: 8, borderColor: isCurrent ? "var(--accent)" : "var(--border)", background: "var(--surface-2)" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <strong style={{ fontSize: 16 }}>{p.label}</strong>
          <span><strong style={{ fontSize: 18 }}>₹{price(tier, cycle)}</strong><span className="muted" style={{ fontSize: 12 }}>/{cycle === "yearly" ? "yr" : "mo"}</span></span>
        </div>
        <div className="muted" style={{ fontSize: 12.5 }}>{p.blurb} <strong>{p.quota} AI prompts/mo.</strong></div>
        {isCurrent ? (
          <button className="chip" disabled style={{ justifySelf: "start", opacity: 0.7 }}>Current plan</button>
        ) : (
          <button className="btn" disabled={!!busy} onClick={() => run(tier, () => startSubscription(tier, cycle), "Payment received — your plan will activate in a moment.")}>
            {busy === tier ? "Opening…" : `Upgrade to ${p.label}`}
          </button>
        )}
      </div>
    );
  };

  return (
    <section className="card" style={{ padding: 20, display: "grid", gap: 14 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
        <h2>Plan &amp; billing</h2>
        <div style={{ display: "flex", gap: 6 }}>
          <button className="chip" data-active={cycle === "monthly"} onClick={() => setCycle("monthly")}>Monthly</button>
          <button className="chip" data-active={cycle === "yearly"} onClick={() => setCycle("yearly")}>Yearly</button>
        </div>
      </div>

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
        <div className="muted" style={{ fontSize: 13 }}>
          You’re on the <strong style={{ color: "var(--text)", textTransform: "capitalize" }}>{e.tier}</strong> plan
          {e.isTrial ? ` · trial (${e.trialDaysLeft}d left)` : e.subscriptionStatus && e.subscriptionStatus !== "active" ? ` · ${e.subscriptionStatus}` : ""}.
          {e.tier !== "free" && <> AI: {e.quotaLeft} prompts left this cycle.</>}
        </div>
        {e.subscriptionStatus === "active" && (
          <button className="chip" disabled={!!busy} style={{ fontSize: 12, color: "var(--negative)", borderColor: "var(--negative)" }}
            onClick={async () => {
              if (typeof window !== "undefined" && !window.confirm("Cancel your subscription? You'll keep access until the end of the current billing cycle.")) return;
              setBusy("cancel"); setMsg(null);
              try { const r = await cancelSubscription(); setMsg(r.ok ? `Cancelled — you keep access until ${r.ends_at ? new Date(r.ends_at).toLocaleDateString() : "the cycle ends"}.` : "Couldn't cancel."); }
              catch (err) { setMsg((err as Error).message); }
              finally { setBusy(null); }
            }}>{busy === "cancel" ? "Cancelling…" : "Cancel plan"}</button>
        )}
        {e.subscriptionStatus === "cancelling" && (
          <span className="muted" style={{ fontSize: 12 }}>Cancels at the end of this cycle — access continues until then.</span>
        )}
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(200px, 100%), 1fr))", gap: 12 }}>
        <div className="card" style={{ padding: 16, display: "grid", gap: 8, borderColor: e.tier === "free" ? "var(--accent)" : "var(--border)", background: "var(--surface-2)" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <strong style={{ fontSize: 16 }}>Free</strong><strong style={{ fontSize: 18 }}>₹0</strong>
          </div>
          <div className="muted" style={{ fontSize: 12.5 }}>Everything to track your money — no AI, insights or statements.</div>
          {e.tier === "free" && <button className="chip" disabled style={{ justifySelf: "start", opacity: 0.7 }}>Current plan</button>}
        </div>
        {planCard("lite")}
        {planCard("pro")}
      </div>

      <ul className="muted" style={{ fontSize: 12.5, margin: 0, paddingLeft: 18, display: "grid", gap: 2 }}>
        {FREE_FEATURES.map((f) => <li key={f}>{f} <span style={{ color: "var(--positive)" }}>· all plans</span></li>)}
        {PAID_EXTRA.map((f) => <li key={f}>{f} <span style={{ color: "var(--accent)" }}>· Lite &amp; Pro</span></li>)}
      </ul>

      {/* AI credit top-ups */}
      <div style={{ display: "grid", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 12 }}>
        <div><strong style={{ fontSize: 14 }}>Buy AI credits</strong> <span className="muted" style={{ fontSize: 12 }}>— extra Ask PocketCare prompts that never expire.</span></div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {CREDIT_PACKS.map((c) => (
            <button key={c.id} className="chip" disabled={!!busy} onClick={() => run(c.id, () => buyCredits(c.id), "Payment received — credits will be added shortly.")}>
              {busy === c.id ? "Opening…" : `₹${c.price} · +${c.credits}`}
            </button>
          ))}
        </div>
      </div>

      {msg && <div className="card" style={{ padding: 10, fontSize: 13, background: "var(--accent-ghost)", borderColor: "var(--accent-soft)" }}>{msg}</div>}

      <div className="muted" style={{ fontSize: 11, display: "flex", alignItems: "center", gap: 6, borderTop: "1px solid var(--border)", paddingTop: 10 }}>
        Preview tier (dev):
        {(["free", "lite", "pro"] as const).map((tr) => (
          <button key={tr} className="chip" data-active={devTier === tr} style={{ padding: "2px 8px", fontSize: 11 }} onClick={() => setTier(tr)}>{tr}</button>
        ))}
      </div>
    </section>
  );
}
