"use client";

/**
 * Dashboard → "Worth a look" — a horizontal strip of features this person
 * hasn't tried yet.
 *
 * WHY IT ISN'T JUST A FEATURE LIST. Most of the app is invisible from the
 * dashboard: someone tracking spends for six months may never learn that loans,
 * budgets or bill-splitting exist. But a permanent "here's what else we sell"
 * rail is an ad, and in a finance app that costs trust. So every rule in
 * `@sanvya/suggestions` exists to REMOVE cards:
 *
 *  - Each suggestion has a prerequisite — nothing appears until the user has
 *    enough history for it to be a real observation rather than a pitch.
 *  - Credit cards only surface if they actually hold a credit-card account.
 *  - Premium features are never suggested to a free user.
 *  - Every card is dismissible, permanently. "Not interested" has to mean it.
 *  - When there's nothing to say, the strip renders NOTHING — no empty state,
 *    no "you've explored everything!" badge.
 *
 * COPY IS IN ENGLISH, INLINE. The rest of the dashboard (tiles, hero, account
 * chips) is not internationalised either; adding an i18n namespace for this one
 * widget would leave it as the only translated thing on an English page. If the
 * dashboard is ever localised, this moves with it.
 */

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { pickSuggestions, isFeatureId, type FeatureId, type UsageCounts } from "@sanvya/suggestions";

import { useEntitlement } from "../entitlement";
import { useInitialSyncPending } from "../sync";
import { MaterialIcon, type MaterialIconName } from "../ui/MaterialIcon";

const DISMISS_KEY = "sanvya:suggestionsDismissed";

interface Card {
  readonly icon: MaterialIconName;
  readonly title: string;
  /** One line. Says what it does FOR THEM, not what the feature is called. */
  readonly body: string;
  readonly cta: string;
  readonly href: string;
}

/**
 * Copy per feature.
 *
 * Written as an observation plus a benefit, never as an imperative — "Netflix,
 * gym, insurance: see what they cost you a year" reads as help, "Add your
 * subscriptions!" reads as a chore.
 */
const CARDS: Record<FeatureId, Card> = {
  subscriptions: {
    icon: "subscriptions",
    title: "Track subscriptions",
    body: "Netflix, gym, insurance — see what they quietly cost you each year.",
    cta: "Add one",
    href: "/cashflow#payments",
  },
  budgets: {
    icon: "pie_chart",
    title: "Set a budget",
    body: "Pick a monthly cap for eating out or shopping and watch it as you spend.",
    cta: "Create a budget",
    href: "/budgets",
  },
  recurring: {
    icon: "autorenew",
    title: "Automate repeat entries",
    body: "Rent, salary, EMI — enter them once and they post themselves each month.",
    cta: "Set up",
    href: "/recurring",
  },
  creditCards: {
    icon: "credit_card",
    title: "Track your card cycle",
    body: "Add a statement day and see what's due before the bill arrives.",
    cta: "Set it up",
    href: "/cards",
  },
  loans: {
    icon: "request_quote",
    title: "Follow your EMIs",
    body: "Add a loan once and see the schedule, what's paid, and what's left.",
    cta: "Add a loan",
    href: "/loans",
  },
  goals: {
    icon: "savings",
    title: "Save towards something",
    body: "Set a target and a date, and track how close you actually are.",
    cta: "Add a goal",
    href: "/goals",
  },
  splits: {
    icon: "groups",
    title: "Split with friends",
    body: "Share a dinner or a trip, track who owes what, and settle over UPI.",
    cta: "Start a group",
    href: "/friends",
  },
  receipts: {
    icon: "receipt_long",
    title: "Scan a receipt",
    body: "Photograph a bill and it fills in the amount, date and line items.",
    cta: "Try scanning",
    href: "/receipts/new",
  },
  investments: {
    icon: "trending_up",
    title: "Track investments",
    body: "Add holdings to see them counted in your net worth.",
    cta: "Add a holding",
    href: "/investments",
  },
};

/** Persisted dismissals, filtered through `isFeatureId` so a stale id can't linger. */
function readDismissed(): FeatureId[] {
  try {
    const raw = localStorage.getItem(DISMISS_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((v): v is FeatureId => typeof v === "string" && isFeatureId(v)) : [];
  } catch {
    return [];
  }
}

interface CountRow extends Record<string, number> {}

export function Suggestions() {
  const { isPaid } = useEntitlement();
  const syncPending = useInitialSyncPending();
  const [dismissed, setDismissed] = useState<FeatureId[]>([]);
  const [ready, setReady] = useState(false);

  // Read after mount: localStorage is unavailable during SSR, and this widget
  // renders inside the app shell rather than a client-only boundary.
  useEffect(() => {
    setDismissed(readDismissed());
    setReady(true);
  }, []);

  // One query with scalar subselects rather than a dozen `useQuery` calls —
  // each would open its own watcher on the same tables for a single integer.
  const { data: rows = [], isLoading } = useQuery<CountRow>(`
    SELECT
      (SELECT COUNT(*) FROM accounts WHERE deleted_at IS NULL AND IFNULL(kind,'real')='real') AS accounts,
      (SELECT COUNT(*) FROM accounts WHERE deleted_at IS NULL AND type='credit_card') AS creditCardAccounts,
      (SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL) AS transactions,
      (SELECT COUNT(*) FROM subscriptions WHERE deleted_at IS NULL) AS subscriptions,
      (SELECT COUNT(*) FROM loans WHERE deleted_at IS NULL) AS loans,
      (SELECT COUNT(*) FROM budgets WHERE deleted_at IS NULL) AS budgets,
      (SELECT COUNT(*) FROM goals WHERE deleted_at IS NULL) AS goals,
      (SELECT COUNT(*) FROM split_groups WHERE deleted_at IS NULL) AS splitGroups,
      (SELECT COUNT(*) FROM receipt_scans WHERE deleted_at IS NULL) AS receipts,
      (SELECT COUNT(*) FROM recurring_items WHERE deleted_at IS NULL) AS recurring,
      (SELECT COUNT(*) FROM holdings WHERE deleted_at IS NULL) AS holdings,
      (SELECT COUNT(*) FROM credit_card_details WHERE deleted_at IS NULL) AS creditCards,
  `);

  const dismiss = useCallback((id: FeatureId) => {
    setDismissed((prev) => {
      const next = prev.includes(id) ? prev : [...prev, id];
      try { localStorage.setItem(DISMISS_KEY, JSON.stringify(next)); } catch { /* private mode */ }
      return next;
    });
  }, []);

  // Never judge mid-sync. A returning user's rows haven't arrived yet, so every
  // count reads zero — we'd tell someone with five budgets to create their
  // first one. Same reasoning as the first-run walkthrough's own guard.
  if (!ready || isLoading || syncPending) return null;

  const usage = (rows[0] ?? {}) as UsageCounts;
  const picked = pickSuggestions(usage, { dismissed, isPaid });
  if (picked.length === 0) return null;

  return (
    <section style={{ display: "grid", gap: 10, minWidth: 0 }}>
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 8 }}>
        <h2 style={{ margin: 0 }}>Worth a look</h2>
        <span className="muted" style={{ fontSize: 12.5 }}>Things you haven&apos;t tried yet</span>
      </div>

      {/* Horizontal rail. Negative margins + matching padding let cards bleed to
          the screen edge on mobile, so a half-visible card signals scrollability
          instead of stopping dead at the container edge. */}
      <div
        style={{
          display: "flex", gap: 12, overflowX: "auto", scrollSnapType: "x mandatory",
          margin: "0 -4px", padding: "2px 4px 6px",
          scrollbarWidth: "thin", WebkitOverflowScrolling: "touch",
        }}
      >
        {picked.map((id) => {
          const card = CARDS[id];
          return (
            <div
              key={id}
              className="card"
              style={{
                position: "relative", scrollSnapAlign: "start", flex: "0 0 auto",
                width: "min(256px, 78vw)", padding: 16,
                display: "flex", flexDirection: "column", gap: 8,
              }}
            >
              <button
                type="button"
                aria-label={`Dismiss ${card.title}`}
                onClick={() => dismiss(id)}
                className="chip"
                style={{
                  position: "absolute", top: 8, right: 8, padding: "2px 6px",
                  fontSize: 11, lineHeight: 1.2, borderRadius: 999,
                }}
              >
                <MaterialIcon name="close" size={13} />
              </button>

              <span
                style={{
                  width: 36, height: 36, borderRadius: 10, flexShrink: 0,
                  background: "var(--accent-ghost)", color: "var(--accent)",
                  display: "grid", placeItems: "center",
                }}
              >
                <MaterialIcon name={card.icon} size={20} />
              </span>

              <strong style={{ fontSize: 14.5, paddingRight: 22 }}>{card.title}</strong>
              <p className="muted" style={{ margin: 0, fontSize: 12.5, lineHeight: 1.45, flex: 1 }}>
                {card.body}
              </p>
              <Link href={card.href} className="btn ghost" style={{ justifySelf: "start", fontSize: 13 }}>
                {card.cta}
              </Link>
            </div>
          );
        })}
      </div>
    </section>
  );
}
