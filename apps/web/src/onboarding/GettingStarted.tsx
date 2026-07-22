"use client";

/**
 * A hand-holding "getting started" checklist for new users — shown on the
 * dashboard. Each step explains WHAT to do and WHY, links straight to it, and
 * ticks itself off as the user completes it. Dismissible, auto-hides when done,
 * and skipped entirely for Pro users (who tend to know their way around).
 */
import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { useInitialSyncPending } from "../sync";

const KEY = "gettingStartedDismissed";

interface Step { done: boolean; title: string; why: string; href: string; cta: string }

export function GettingStarted() {
  const syncPending = useInitialSyncPending();
  const [dismissed, setDismissed] = useState(() => (typeof window !== "undefined" ? localStorage.getItem(KEY) === "1" : false));

  const { data: acc = [] } = useQuery<{ c: number }>("SELECT COUNT(*) AS c FROM accounts WHERE deleted_at IS NULL AND IFNULL(kind,'real')='real'");
  const { data: txn = [] } = useQuery<{ c: number }>("SELECT COUNT(*) AS c FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense')");
  const { data: plan = [] } = useQuery<{ c: number }>("SELECT (SELECT COUNT(*) FROM budgets WHERE deleted_at IS NULL) + (SELECT COUNT(*) FROM goals WHERE deleted_at IS NULL) AS c");

  const hasAccount = (acc[0]?.c ?? 0) > 0;
  const hasTxn = (txn[0]?.c ?? 0) > 0;
  const hasPlan = (plan[0]?.c ?? 0) > 0;

  const steps: Step[] = [
    { done: hasAccount, title: "Add your first account", why: "So PocketCare knows your starting balance — this powers your net worth, budgets and insights.", href: "/accounts/new", cta: "Add account" },
    { done: hasTxn, title: "Record a transaction", why: "Log a spend or income (type it or tap the mic). PocketCare suggests the category for you.", href: "/transactions/new", cta: "Add transaction" },
    { done: hasPlan, title: "Set a budget or goal", why: "Give your money a plan — a monthly budget to stay on track, or a goal to save toward.", href: "/budgets", cta: "Create one" },
  ];
  const doneCount = steps.filter((s) => s.done).length;

  // Wait for the first sync before judging — otherwise it flashes for existing
  // users whose counts are momentarily 0 while data downloads. Keep it for
  // everyone; hide once dismissed or all done.
  if (syncPending || dismissed || doneCount === steps.length) return null;

  const next = steps.find((s) => !s.done);
  return (
    <section className="card" style={{ padding: 18, display: "grid", gap: 14, borderColor: "var(--accent-soft)" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10 }}>
        <div>
          <strong style={{ fontSize: 15 }}>Getting started</strong>
          <div className="muted" style={{ fontSize: 12 }}>{doneCount} of {steps.length} done · a couple of minutes to set up</div>
        </div>
        <button className="chip" onClick={() => { localStorage.setItem(KEY, "1"); setDismissed(true); }}>Dismiss</button>
      </div>
      <div style={{ height: 6, borderRadius: 999, background: "var(--surface-2)", overflow: "hidden" }}>
        <div style={{ width: `${(doneCount / steps.length) * 100}%`, height: "100%", background: "var(--accent)", transition: "width 0.4s cubic-bezier(0.2,0,0,1)" }} />
      </div>
      <div style={{ display: "grid", gap: 10 }}>
        {steps.map((s, i) => (
          <div key={i} style={{ display: "flex", gap: 12, alignItems: "flex-start", opacity: s.done ? 0.6 : 1 }}>
            <span aria-hidden style={{ width: 22, height: 22, flexShrink: 0, marginTop: 1, borderRadius: 999, display: "grid", placeItems: "center", fontSize: 12, fontWeight: 700,
              background: s.done ? "var(--positive)" : "var(--surface-2)", color: s.done ? "#fff" : "var(--text-2)" }}>{s.done ? "✓" : i + 1}</span>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 14, fontWeight: 600, textDecoration: s.done ? "line-through" : "none" }}>{s.title}</div>
              {!s.done && <div className="muted" style={{ fontSize: 12.5, lineHeight: 1.5 }}>{s.why}</div>}
            </div>
            {!s.done && s === next && <Link href={s.href} className="btn" style={{ padding: "5px 12px", fontSize: 13, minHeight: 0, flexShrink: 0 }}>{s.cta}</Link>}
          </div>
        ))}
      </div>
      <div className="muted" style={{ fontSize: 11.5 }}>Stuck? <Link href="/assistant">Ask PocketCare</Link> anything, or <Link href="/help">see the guide</Link>.</div>
    </section>
  );
}
