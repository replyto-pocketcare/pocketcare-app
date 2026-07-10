"use client";

import { money } from "@pocketcare/money";
import { useBaseCurrency } from "../hooks";
import { useMoneyFmt } from "../ui/Money";
import { useFriendBalances, useUserProfiles } from "./hooks";

const initials = (name: string) => name.trim().split(/\s+/).map((w) => w[0]).slice(0, 2).join("").toUpperCase() || "?";

/**
 * Minimal "who owes whom" graph from your perspective: you in the centre, each
 * friend around a ring, a directed arrow on each edge (pointing to whoever is
 * owed) labelled with the amount. Green = they owe you, red = you owe them.
 */
export function FriendsGraph() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const profiles = useUserProfiles();
  const name = (id: string) => profiles.get(id)?.name ?? "Someone";

  const open = useFriendBalances().filter((b) => b.net !== 0).sort((a, b) => Math.abs(b.net) - Math.abs(a.net)).slice(0, 8);
  if (open.length === 0) return null;

  const W = 340, H = 340, cx = W / 2, cy = H / 2, R = 122, cr = 30, fr = 26;
  const nodes = open.map((b, i) => {
    const a = -Math.PI / 2 + (i * 2 * Math.PI) / open.length;
    return { ...b, x: cx + R * Math.cos(a), y: cy + R * Math.sin(a) };
  });

  // Trim a segment so it starts/ends at the node edges (not centres).
  const trim = (x1: number, y1: number, x2: number, y2: number, r1: number, r2: number) => {
    const dx = x2 - x1, dy = y2 - y1, L = Math.hypot(dx, dy) || 1;
    return { x1: x1 + (dx / L) * r1, y1: y1 + (dy / L) * r1, x2: x2 - (dx / L) * r2, y2: y2 - (dy / L) * r2 };
  };

  return (
    <section className="card" style={{ padding: 20, display: "grid", gap: 8 }}>
      <h2 style={{ margin: 0 }}>Who owes whom</h2>
      <div style={{ display: "flex", gap: 14, fontSize: 12 }} className="muted">
        <span><span style={{ color: "var(--positive)" }}>→</span> owes you</span>
        <span><span style={{ color: "var(--negative)" }}>→</span> you owe</span>
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", maxWidth: 420, justifySelf: "center" }} role="img" aria-label="Friend balances graph">
        <defs>
          <marker id="arrowPos" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
            <path d="M0,0 L10,5 L0,10 z" fill="var(--positive)" />
          </marker>
          <marker id="arrowNeg" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
            <path d="M0,0 L10,5 L0,10 z" fill="var(--negative)" />
          </marker>
        </defs>

        {nodes.map((n) => {
          const owedToYou = n.net > 0;
          const color = owedToYou ? "var(--positive)" : "var(--negative)";
          // Arrow points to the creditor: friend→you when they owe you, you→friend otherwise.
          const seg = owedToYou ? trim(n.x, n.y, cx, cy, fr, cr) : trim(cx, cy, n.x, n.y, cr, fr);
          const mx = (n.x + cx) / 2, my = (n.y + cy) / 2;
          return (
            <g key={n.userId}>
              <line x1={seg.x1} y1={seg.y1} x2={seg.x2} y2={seg.y2} stroke={color} strokeWidth={2} opacity={0.8} markerEnd={`url(#${owedToYou ? "arrowPos" : "arrowNeg"})`} />
              <g>
                <rect x={mx - 30} y={my - 10} width={60} height={18} rx={9} fill="var(--surface)" stroke="var(--border)" />
                <text x={mx} y={my + 3} textAnchor="middle" fontSize="10.5" fontWeight={600} fill={color}>{fmt(money(Math.abs(n.net), base), "en-US")}</text>
              </g>
            </g>
          );
        })}

        {nodes.map((n) => (
          <g key={`n-${n.userId}`}>
            <circle cx={n.x} cy={n.y} r={fr} fill="var(--surface-2)" stroke="var(--border)" />
            <text x={n.x} y={n.y + 3} textAnchor="middle" fontSize="12" fontWeight={600} fill="var(--text)">{initials(name(n.userId))}</text>
            <text x={n.x} y={n.y + fr + 13} textAnchor="middle" fontSize="10.5" fill="var(--text-2)">{name(n.userId).split(" ")[0]}</text>
          </g>
        ))}

        <circle cx={cx} cy={cy} r={cr} fill="var(--accent)" />
        <text x={cx} y={cy + 4} textAnchor="middle" fontSize="13" fontWeight={700} fill="#fff">You</text>
      </svg>
    </section>
  );
}
