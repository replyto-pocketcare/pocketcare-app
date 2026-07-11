"use client";

import { useState } from "react";
import { useQuery } from "@powersync/react";
import { useEntitlement } from "../entitlement";
import { useSession } from "../account";
import { PLANS, CREDIT_PACKS, price, type PaidTier, type Cycle } from "../billing/plans";
import { startSubscription, buyCredits, cancelSubscription, redeemCoupon } from "../billing";
import { openInvoice, type InvoicePayment } from "../billing/invoice";

const FREE_FEATURES = ["All account types (bank, cash, cards, stocks…)", "Categories, labels, budgets, goals", "Transactions, transfers, search"];
const PAID_EXTRA = ["Detailed Insights & Statements", "Ask PocketCare AI assistant", "Auto-categorisation, upcoming, stock sync", "CSV import"];

type PlanKey = "free" | "lite" | "pro";
const PLAN_DETAILS: Record<PlanKey, { includes: string[]; excludes: string[]; ai: string }> = {
  free: { includes: FREE_FEATURES, excludes: PAID_EXTRA, ai: "No Ask PocketCare — upgrade to Lite or Pro to unlock" },
  lite: { includes: [...FREE_FEATURES, ...PAID_EXTRA], excludes: [], ai: "50 Ask PocketCare prompts / month" },
  pro: { includes: [...FREE_FEATURES, ...PAID_EXTRA], excludes: [], ai: "200 Ask PocketCare prompts / month" },
};

export function Billing() {
  const e = useEntitlement();
  const session = useSession();
  const email = session?.email ?? "";
  const { data: payments = [] } = useQuery<InvoicePayment>(
    "SELECT id, created_at, kind, amount, currency, credits_added, razorpay_payment_id, razorpay_order_id, status FROM payments WHERE status = 'captured' ORDER BY created_at DESC LIMIT 50",
  );
  // Default to the user's ACTUAL plan/cycle (which may load after first render),
  // then stick to whatever they pick.
  const [pickedCycle, setPickedCycle] = useState<Cycle | null>(null);
  const [picked, setPicked] = useState<PlanKey | null>(null);
  const cycle: Cycle = pickedCycle ?? (e.cycle === "yearly" ? "yearly" : "monthly");
  const selected: PlanKey = picked ?? e.tier;
  const setCycle = setPickedCycle;
  const setSelected = setPicked;
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  // Reward coupons (earned via bug reports) + manual redemption.
  const { data: coupons = [] } = useQuery<{ id: string; code: string; tier: string; expires_at: string; redeemed_at: string | null }>(
    "SELECT id, code, tier, expires_at, redeemed_at FROM coupons ORDER BY created_at DESC",
  );
  const [couponCode, setCouponCode] = useState("");
  const [redeeming, setRedeeming] = useState(false);
  const [couponMsg, setCouponMsg] = useState<string | null>(null);
  async function doRedeem(code: string) {
    if (!code.trim()) return;
    setRedeeming(true); setCouponMsg(null);
    try {
      const r = await redeemCoupon(code);
      setCouponMsg(`✓ ${r.tier[0]!.toUpperCase()}${r.tier.slice(1)} unlocked until ${new Date(r.until).toLocaleDateString()}.`);
      setCouponCode("");
    } catch (err) { setCouponMsg((err as Error).message); }
    finally { setRedeeming(false); }
  }

  async function run(id: string, fn: () => Promise<{ ok: boolean }>, okMsg: string) {
    setBusy(id); setMsg(null);
    try { const r = await fn(); setMsg(r.ok ? okMsg : "Checkout was closed."); }
    catch (err) { setMsg((err as Error).message); }
    finally { setBusy(null); }
  }

    const RANK: Record<PlanKey, number> = { free: 0, lite: 1, pro: 2 };
  const planCard = (tier: PaidTier) => {
    const p = PLANS[tier];
    const isYourTier = e.tier === tier;
    // "Current" only when the tier AND the shown billing cycle match your plan.
    const isCurrent = isYourTier && e.cycle === cycle;
    const isSelected = selected === tier;
    // Block re-buying while a subscription is active: same tier (any cycle other
    // than a cycle-switch) or a lower tier is already included in the active plan.
    const hasActiveSub = e.subscriptionStatus === "active" && e.tier !== "free";
    const isLower = hasActiveSub && RANK[tier] < RANK[e.tier];
    return (
      <div key={tier} className="card" role="button" tabIndex={0} onClick={() => setSelected(tier)}
        style={{ padding: 16, display: "grid", gap: 8, cursor: "pointer", background: "var(--surface-2)",
          borderColor: isSelected ? "var(--accent)" : isCurrent ? "var(--accent-soft)" : "var(--border)",
          boxShadow: isSelected ? "0 0 0 2px var(--accent-soft)" : "none" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <strong style={{ fontSize: 16 }}>{p.label}{isCurrent && <span className="muted" style={{ fontSize: 11, fontWeight: 400 }}> · current</span>}</strong>
          <span><strong style={{ fontSize: 18 }}>₹{price(tier, cycle)}</strong><span className="muted" style={{ fontSize: 12 }}>/{cycle === "yearly" ? "yr" : "mo"}</span></span>
        </div>
        <div className="muted" style={{ fontSize: 12.5 }}>{p.blurb} <strong>{p.quota} AI prompts/mo.</strong></div>
        {isCurrent ? (
          <button className="chip" disabled style={{ justifySelf: "start", opacity: 0.7 }}>Current plan</button>
        ) : isLower ? (
          <button className="chip" disabled style={{ justifySelf: "start", opacity: 0.7 }}>Included in your plan</button>
        ) : isYourTier ? (
          <button className="btn" disabled={!!busy} onClick={(ev) => { ev.stopPropagation(); run(tier, () => startSubscription(tier, cycle), "Payment received — your plan will update in a moment."); }}>
            {busy === tier ? "Opening…" : `Switch to ${cycle}`}
          </button>
        ) : (
          <button className="btn" disabled={!!busy} onClick={(ev) => { ev.stopPropagation(); run(tier, () => startSubscription(tier, cycle), "Payment received — your plan will activate in a moment."); }}>
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
          {e.isTrial ? ` · trial (${e.trialDaysLeft}d left)` : e.subscriptionStatus && e.subscriptionStatus !== "active" ? ` · ${e.subscriptionStatus}` : ""}
          {e.tier !== "free" && !e.isTrial && e.cycle ? ` · billed ${e.cycle}` : ""}
          {e.tier !== "free" && e.subscriptionStatus === "active" && e.quotaResetDate ? ` · renews ${new Date(e.quotaResetDate).toLocaleDateString()}` : ""}.
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

      {/* AI credit balance */}
      <div className="card" style={{ padding: 14, display: "flex", gap: 20, flexWrap: "wrap", alignItems: "center", background: "var(--surface-2)" }}>
        <div>
          <div style={{ fontSize: 22, fontWeight: 750 }}>{e.quotaLeft}</div>
          <div className="muted" style={{ fontSize: 12 }}>AI prompts available</div>
        </div>
        <div className="muted" style={{ fontSize: 12.5, lineHeight: 1.6 }}>
          {Math.max(0, e.quotaTotal - e.quotaUsed)} left in your plan this cycle
          {e.purchased > 0 ? <> · {e.purchased} purchased credit{e.purchased === 1 ? "" : "s"} (never expire)</> : ""}
          {e.quotaResetDate && e.quotaTotal > 0 ? <><br />Plan quota resets {new Date(e.quotaResetDate).toLocaleDateString()}</> : ""}
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(200px, 100%), 1fr))", gap: 12 }}>
        <div className="card" role="button" tabIndex={0} onClick={() => setSelected("free")}
          style={{ padding: 16, display: "grid", gap: 8, cursor: "pointer", background: "var(--surface-2)",
            borderColor: selected === "free" ? "var(--accent)" : e.tier === "free" ? "var(--accent-soft)" : "var(--border)",
            boxShadow: selected === "free" ? "0 0 0 2px var(--accent-soft)" : "none" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <strong style={{ fontSize: 16 }}>Free{e.tier === "free" && <span className="muted" style={{ fontSize: 11, fontWeight: 400 }}> · current</span>}</strong><strong style={{ fontSize: 18 }}>₹0</strong>
          </div>
          <div className="muted" style={{ fontSize: 12.5 }}>Everything to track your money — no AI, insights or statements.</div>
          {e.tier === "free" && <button className="chip" disabled style={{ justifySelf: "start", opacity: 0.7 }}>Current plan</button>}
        </div>
        {planCard("lite")}
        {planCard("pro")}
      </div>

      {/* What's included in the tapped plan */}
      <div className="card" style={{ padding: 14, background: "var(--surface-2)", display: "grid", gap: 8 }}>
        <div style={{ fontSize: 13 }}>
          <strong style={{ textTransform: "capitalize" }}>{selected}</strong> plan includes:
        </div>
        <ul style={{ fontSize: 12.5, margin: 0, paddingLeft: 4, display: "grid", gap: 3, listStyle: "none" }}>
          {PLAN_DETAILS[selected].includes.map((f) => (
            <li key={f} style={{ display: "flex", gap: 8 }}><span style={{ color: "var(--positive)" }}>✓</span>{f}</li>
          ))}
          <li style={{ display: "flex", gap: 8 }}><span style={{ color: "var(--accent)" }}>✦</span>{PLAN_DETAILS[selected].ai}</li>
          {PLAN_DETAILS[selected].excludes.map((f) => (
            <li key={f} className="muted" style={{ display: "flex", gap: 8, textDecoration: "line-through" }}><span>✕</span>{f}</li>
          ))}
        </ul>
      </div>

      {/* AI credit top-ups — Lite/Pro only */}
      <div style={{ display: "grid", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 12 }}>
        <div><strong style={{ fontSize: 14 }}>Buy AI credits</strong> <span className="muted" style={{ fontSize: 12 }}>— extra Ask PocketCare prompts that never expire.</span></div>
        {e.isPaid ? (
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            {CREDIT_PACKS.map((c) => (
              <button key={c.id} className="chip" disabled={!!busy} onClick={() => run(c.id, () => buyCredits(c.id), "Payment received — credits will be added shortly.")}>
                {busy === c.id ? "Opening…" : `₹${c.price} · +${c.credits}`}
              </button>
            ))}
          </div>
        ) : (
          <p className="muted" style={{ fontSize: 13, margin: 0 }}>Available on the Lite and Pro plans — choose a plan above, then you can buy credit top-ups anytime.</p>
        )}
      </div>

      {msg && <div className="card" style={{ padding: 10, fontSize: 13, background: "var(--accent-ghost)", borderColor: "var(--accent-soft)" }}>{msg}</div>}

      {/* Reward coupons */}
      <div style={{ display: "grid", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 12 }}>
        <div><strong style={{ fontSize: 14 }}>Have a coupon?</strong> <span className="muted" style={{ fontSize: 12 }}>— redeem a reward code for a free plan, no charge.</span></div>
        {coupons.filter((c) => !c.redeemed_at && new Date(c.expires_at).getTime() > Date.now()).map((c) => (
          <div key={c.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, padding: "8px 12px", borderRadius: 10, border: "1px solid var(--accent-soft)", background: "var(--accent-ghost)", flexWrap: "wrap" }}>
            <span style={{ fontSize: 13 }}>🎁 <strong>{c.tier[0]!.toUpperCase()}{c.tier.slice(1)}</strong> reward · <code>{c.code}</code> <span className="muted">· expires {new Date(c.expires_at).toLocaleDateString()}</span></span>
            <button className="btn" style={{ padding: "4px 12px", fontSize: 13, minHeight: 0, height: 30 }} disabled={redeeming} onClick={() => doRedeem(c.code)}>{redeeming ? "Redeeming…" : "Redeem"}</button>
          </div>
        ))}
        <div style={{ display: "flex", gap: 8 }}>
          <input className="input" placeholder="Enter coupon code" value={couponCode} onChange={(e) => setCouponCode(e.target.value.toUpperCase())} onKeyDown={(e) => { if (e.key === "Enter") void doRedeem(couponCode); }} />
          <button className="btn ghost" disabled={redeeming || !couponCode.trim()} onClick={() => doRedeem(couponCode)}>Redeem</button>
        </div>
        {couponMsg && <span style={{ fontSize: 12, color: couponMsg.startsWith("✓") ? "var(--positive)" : "var(--negative)" }}>{couponMsg}</span>}
        <p className="muted" style={{ fontSize: 11, margin: 0 }}>Beta testers earn coupons: 5 bug reports → 1 month Lite, 25 → Pro.</p>
      </div>

      {/* Billing history + invoices */}
      {payments.length > 0 && (
        <div style={{ display: "grid", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 12 }}>
          <strong style={{ fontSize: 14 }}>Billing history</strong>
          <div style={{ display: "grid", gap: 6 }}>
            {payments.map((p) => (
              <div key={p.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, fontSize: 13, flexWrap: "wrap" }}>
                <span className="muted" style={{ minWidth: 0 }}>
                  {p.created_at ? new Date(p.created_at).toLocaleDateString() : ""} · {p.kind === "credits" ? `${p.credits_added ?? 0} AI credits` : "Subscription"} · ₹{((p.amount ?? 0) / 100).toFixed(2)}
                </span>
                <button className="chip" style={{ padding: "2px 10px", fontSize: 12 }} onClick={() => openInvoice(p, email)}>Invoice</button>
              </div>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}
