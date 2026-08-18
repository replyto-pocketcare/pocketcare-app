"use client";

import { useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import { useQuery } from "@powersync/react";
import { money, type Money } from "@sanvya/money";
import { MaterialIcon, type MaterialIconName } from "../MaterialIcon";

/**
 * The desktop KPI strip: four headline figures across the top of the dashboard,
 * each with a period-over-period delta.
 *
 * Desktop only — mounted by app/page.tsx behind `useIsDesktop()`, so phones
 * never run these queries or pay for the count-up animation.
 */

/** Animate a number up to `target` on mount / whenever it changes.
 *
 *  Skipped entirely when `enabled` is false (amounts hidden — there's nothing
 *  to count to) and for users who asked for reduced motion, who get the final
 *  value immediately rather than a 900ms tween they didn't want. */
function useCountUp(target: number, enabled: boolean): number {
  const [value, setValue] = useState(enabled ? 0 : target);
  const frame = useRef<number | undefined>(undefined);
  const from = useRef(0);

  useEffect(() => {
    if (!enabled) { setValue(target); return; }
    const reduced = typeof matchMedia !== "undefined" && matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) { setValue(target); return; }

    const start = performance.now();
    const origin = from.current;
    const DURATION = 900;
    // easeOutExpo — fast out of the gate, long settle. Reads as "landing on"
    // a figure rather than a linear odometer roll.
    const ease = (t: number) => (t === 1 ? 1 : 1 - Math.pow(2, -10 * t));

    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / DURATION);
      setValue(origin + (target - origin) * ease(t));
      if (t < 1) frame.current = requestAnimationFrame(tick);
      else from.current = target;
    };
    frame.current = requestAnimationFrame(tick);
    return () => { if (frame.current) cancelAnimationFrame(frame.current); };
  }, [target, enabled]);

  return value;
}

interface Stat {
  key: string;
  label: string;
  icon: MaterialIconName;
  tint: string;
  /** Current-period figure, in minor units. */
  minor: number;
  /** Previous-period figure, in minor units — drives the delta pill. */
  prevMinor: number;
  /** When true, a RISE is bad (spending). Flips the pill's colour only. */
  inverse?: boolean;
}

function StatCard({ stat, base, fmt, hidden, index }: {
  stat: Stat; base: string; fmt: (m: Money) => string; hidden: boolean; index: number;
}) {
  const shown = useCountUp(stat.minor, !hidden);

  const pct = stat.prevMinor === 0 ? null : ((stat.minor - stat.prevMinor) / Math.abs(stat.prevMinor)) * 100;
  const rose = (pct ?? 0) >= 0;
  // "Good" is not the same as "up": more spending is a worse month, so the
  // pill's colour follows the meaning, while the arrow follows the direction.
  const good = stat.inverse ? !rose : rose;

  return (
    <motion.div
      className="stat-card"
      initial={{ opacity: 0, y: 14 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.07, duration: 0.42, ease: [0.16, 1, 0.3, 1] }}
    >
      <div className="stat-head">
        <span className="stat-label">{stat.label}</span>
        <span className="stat-ico" style={{ background: `color-mix(in srgb, ${stat.tint} 16%, transparent)`, color: stat.tint }}>
          <MaterialIcon name={stat.icon} size={16} />
        </span>
      </div>
      <div className="stat-line">
        <span className="stat-value tabular-nums">{fmt(money(Math.round(shown), base))}</span>
        {pct !== null && !hidden && (
          <span className={`stat-delta${good ? " up" : " down"}`}>
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
              <path d={rose ? "M5 15l7-7 7 7" : "M5 9l7 7 7-7"} />
            </svg>
            {Math.abs(pct).toFixed(1)}%
          </span>
        )}
      </div>
      <div className="stat-sub">
        {hidden ? "Amounts hidden" : `vs. ${fmt(money(Math.round(stat.prevMinor), base))} last month`}
      </div>
    </motion.div>
  );
}

export function StatRow({ net, base, fmt, hidden }: {
  net: Money; base: string; fmt: (m: Money) => string; hidden: boolean;
}) {
  // Same shape of query the net-worth hero already runs, so this adds one
  // cheap aggregate rather than a second pass over the ledger per card.
  const { data: rows = [] } = useQuery<{ ym: string; type: string; total: number }>(
    "SELECT strftime('%Y-%m', occurred_at) as ym, type, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense') GROUP BY ym, type ORDER BY ym",
  );

  const byMonth = new Map<string, { inc: number; exp: number }>();
  for (const r of rows) {
    const o = byMonth.get(r.ym) ?? { inc: 0, exp: 0 };
    if (r.type === "income") o.inc = r.total; else o.exp = r.total;
    byMonth.set(r.ym, o);
  }
  const months = [...byMonth.values()];
  const cur = months[months.length - 1] ?? { inc: 0, exp: 0 };
  const prev = months[months.length - 2] ?? { inc: 0, exp: 0 };

  const stats: Stat[] = [
    // Net worth has no meaningful "last month" stored figure, so it compares
    // against itself minus this month's movement — i.e. where it started.
    { key: "net", label: "Net worth", icon: "account_balance", tint: "var(--forest)", minor: net.amount, prevMinor: net.amount - (cur.inc - cur.exp) },
    { key: "inc", label: "Income", icon: "trending_up", tint: "var(--positive)", minor: cur.inc, prevMinor: prev.inc },
    { key: "exp", label: "Spending", icon: "payments", tint: "var(--negative)", minor: cur.exp, prevMinor: prev.exp, inverse: true },
    { key: "sav", label: "Saved", icon: "savings", tint: "var(--teal)", minor: cur.inc - cur.exp, prevMinor: prev.inc - prev.exp },
  ];

  return (
    <div className="stat-row">
      {stats.map((s, i) => (
        <StatCard key={s.key} stat={s} base={base} fmt={fmt} hidden={hidden} index={i} />
      ))}
    </div>
  );
}
