"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useEntitlement } from "../entitlement";
import { useSession } from "../account";
import { Modal } from "./Modal";

// Features that disappear when the trial ends and the user stays on Free.
const LOSE_ON_FREE = [
  "Ask PocketCare — the AI assistant",
  "Detailed Insights & Statements",
  "Auto-categorisation, upcoming bills & daily stock sync",
  "CSV import",
];

const seenKey = (email: string | null) => `pocketcare:trial-welcome:${email ?? "anon"}`;

/**
 * Trial onboarding: a one-time welcome dialog right after registration, plus a
 * persistent banner counting down the 14-day trial with an upgrade CTA. Only
 * shown to registered users who are actually on the trial (not guests, not paid).
 */
export function TrialNotice() {
  const e = useEntitlement();
  const session = useSession();
  const onTrial = Boolean(session && !session.isGuest && e.isTrial);

  const [welcomeOpen, setWelcomeOpen] = useState(false);
  useEffect(() => {
    if (!onTrial || !session) return;
    try {
      if (localStorage.getItem(seenKey(session.email)) !== "true") setWelcomeOpen(true);
    } catch { /* ignore */ }
  }, [onTrial, session]);

  const dismissWelcome = () => {
    try { if (session) localStorage.setItem(seenKey(session.email), "true"); } catch { /* ignore */ }
    setWelcomeOpen(false);
  };

  if (!onTrial) return null;
  const days = e.trialDaysLeft;
  const dayLabel = days === 1 ? "1 day" : `${days} days`;

  return (
    <>
      {/* Persistent countdown banner */}
      <div style={{ padding: "9px 14px", marginBottom: 16, borderRadius: 10, fontSize: 13,
        display: "flex", flexWrap: "wrap", gap: 12, alignItems: "center",
        border: "1px solid var(--accent-soft)", background: "var(--accent-ghost)", color: "var(--text)" }}>
        <span style={{ width: 8, height: 8, borderRadius: 999, flexShrink: 0, background: "var(--accent)" }} />
        <div style={{ flex: "1 1 auto", minWidth: 0 }}>
          <strong>Free trial · {dayLabel} left.</strong>{" "}
          <span className="muted">When it ends you’ll lose Ask PocketCare, Insights, Statements &amp; more unless you upgrade.</span>
        </div>
        <Link href="/settings" className="btn" style={{ padding: "4px 12px", fontSize: 12, minHeight: 0, height: 28, display: "inline-flex", alignItems: "center" }}>
          Upgrade
        </Link>
      </div>

      {/* One-time welcome dialog */}
      <Modal open={welcomeOpen} onClose={dismissWelcome}>
        <div style={{ display: "grid", gap: 14 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <div style={{ width: 38, height: 38, borderRadius: 10, background: "var(--accent)", color: "#fff", display: "grid", placeItems: "center", fontSize: 20 }}>✦</div>
            <div>
              <h2 style={{ margin: 0, fontSize: 18 }}>Your 14-day free trial is live</h2>
              <div className="muted" style={{ fontSize: 13 }}>{dayLabel} left · full access, no card needed.</div>
            </div>
          </div>
          <p style={{ margin: 0, fontSize: 14 }}>
            You’ve got everything unlocked while you explore PocketCare — including the features that are paid-only after the trial:
          </p>
          <ul style={{ margin: 0, paddingLeft: 4, display: "grid", gap: 6, fontSize: 13.5, listStyle: "none" }}>
            {LOSE_ON_FREE.map((f) => (
              <li key={f} style={{ display: "flex", gap: 8 }}><span style={{ color: "var(--accent)" }}>✦</span>{f}</li>
            ))}
          </ul>
          <p className="muted" style={{ margin: 0, fontSize: 12.5 }}>
            After {dayLabel}, you’ll move to the Free plan (all your money tracking stays free) unless you upgrade to Lite or Pro.
          </p>
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", flexWrap: "wrap" }}>
            <button className="btn ghost" onClick={dismissWelcome}>Maybe later</button>
            <Link href="/settings" className="btn" onClick={dismissWelcome}>See plans</Link>
          </div>
        </div>
      </Modal>
    </>
  );
}
