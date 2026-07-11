"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { useMoneyFmt } from "../../src/ui/Money";
import { Modal } from "../../src/ui/Modal";
import { useSplitOverview, useUserProfiles } from "../../src/splits/hooks";
import { settleUp } from "../../src/splits/write";

interface SettleTarget { userId: string; name: string; net: number }

const AVATAR_COLORS = ["#7c9a6d", "#c9b48f", "#cb9b7a", "#b9855f", "#c06a4f", "#8a9b7a", "#d0a98b"];
function colorFor(id: string): string {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  return AVATAR_COLORS[h % AVATAR_COLORS.length]!;
}
function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return (parts[0]![0]! + parts[1]![0]!).toUpperCase();
  return (name.trim().slice(0, 2) || "?").toUpperCase();
}

function Avatar({ id, name, size = 30, ring = false }: { id: string; name: string; size?: number; ring?: boolean }) {
  return (
    <span style={{
      width: size, height: size, borderRadius: 999, flexShrink: 0, background: colorFor(id),
      color: "#2b2723", display: "grid", placeItems: "center", fontWeight: 700, fontSize: size * 0.4,
      ...(ring ? { boxShadow: "0 0 0 2px var(--bg)" } : {}),
    }}>{initials(name)}</span>
  );
}

export default function SplitsPage() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const overview = useSplitOverview();
  const profiles = useUserProfiles();
  const name = (id: string) => profiles.get(id)?.name ?? "Someone";

  const { data: accounts = [] } = useQuery<{ id: string; name: string }>(
    "SELECT id, name FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real' AND type NOT IN ('stocks','mutual_funds') ORDER BY created_at",
  );
  const { data: settleGroups = [] } = useQuery<{ group_id: string; user_id: string }>(
    "SELECT group_id, user_id FROM split_group_members WHERE deleted_at IS NULL",
  );

  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const toggle = (id: string) => setExpanded((prev) => {
    const next = new Set(prev);
    next.has(id) ? next.delete(id) : next.add(id);
    return next;
  });

  const [person, setPerson] = useState<SettleTarget | null>(null);
  const [target, setTarget] = useState<SettleTarget | null>(null);
  const [amount, setAmount] = useState("");
  const [accountId, setAccountId] = useState("");
  const [busy, setBusy] = useState(false);
  const [reminded, setReminded] = useState(false);

  function openPerson(userId: string, net: number) {
    setReminded(false);
    setPerson({ userId, name: name(userId), net });
  }
  function openSettle(userId: string, net: number) {
    setPerson(null);
    setTarget({ userId, name: name(userId), net });
    setAmount((Math.abs(net) / 100).toFixed(2));
    setAccountId("");
  }
  async function remind(p: SettleTarget) {
    const line = p.net > 0
      ? `Hi ${p.name}, friendly reminder about the ${fmt(money(Math.abs(p.net), base))} from our split on PocketCare 🙂`
      : `Hi ${p.name}, I still owe you ${fmt(money(Math.abs(p.net), base))} from our split — I’ll settle up soon!`;
    try {
      if (typeof navigator !== "undefined" && navigator.share) await navigator.share({ text: line });
      else if (typeof navigator !== "undefined" && navigator.clipboard) { await navigator.clipboard.writeText(line); setReminded(true); }
    } catch { /* user dismissed share sheet */ }
  }
  async function confirmSettle() {
    if (!target) return;
    const minor = Math.round((Number(amount) || 0) * 100);
    if (minor <= 0) return;
    const gid = settleGroups.find((g) => g.user_id === target.userId)?.group_id;
    if (!gid) { setBusy(false); setTarget(null); return; }
    setBusy(true);
    try {
      await settleUp({ otherUserId: target.userId, groupId: gid, amount: minor, direction: target.net >= 0 ? "received" : "paid", accountId: accountId || null, currency: base });
      setTarget(null);
    } finally { setBusy(false); }
  }

  const { netPosition, owed, owe, groups, direct } = overview;
  const total = owed + owe;
  const owePct = total > 0 ? (owe / total) * 100 : 0;
  const owedPct = total > 0 ? (owed / total) * 100 : 100;
  const netColor = netPosition >= 0 ? "var(--positive)" : "var(--negative)";
  const empty = groups.length === 0 && direct.length === 0;

  const amt = (n: number) => fmt(money(Math.abs(n), base));

  return (
    <div className="fade-up">
      <section className="card" style={{ padding: 24, display: "grid", gap: 24 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
          <div>
            <div style={{ color: "var(--accent)", fontWeight: 700, fontSize: 12, letterSpacing: "0.08em" }}>SPLITS</div>
            <h1 style={{ margin: "2px 0 0", fontSize: 30 }}>Your balance</h1>
          </div>
          <Link href="/groups" className="btn ghost" style={{ flexShrink: 0 }}>Groups &amp; trips</Link>
        </div>

        {/* Net position */}
        <div style={{ background: "var(--accent-ghost, rgba(0,0,0,0.04))", borderRadius: 18, padding: "22px 24px", display: "grid", gap: 14, justifyItems: "center" }}>
          <div className="muted" style={{ fontSize: 14 }}>Net position</div>
          <div style={{ fontSize: 46, fontWeight: 750, lineHeight: 1, color: netColor }}>
            {netPosition >= 0 ? "+" : "−"}{amt(netPosition)}
          </div>
          <div style={{ width: "100%", height: 12, borderRadius: 999, overflow: "hidden", display: "flex", background: "var(--border)" }}>
            <div style={{ width: `${owePct}%`, background: "var(--negative)" }} />
            <div style={{ width: `${owedPct}%`, background: "var(--positive)" }} />
          </div>
        </div>

        {empty ? (
          <div style={{ padding: "24px 8px", textAlign: "center", display: "grid", gap: 10, justifyItems: "center" }}>
            <div style={{ fontSize: 26 }}>◑</div>
            <h2 style={{ margin: 0 }}>No splits yet</h2>
            <p className="muted" style={{ margin: 0, maxWidth: 380 }}>Create a group and invite people from <Link href="/groups">Groups &amp; trips</Link>. Once they join, you can split and settle here.</p>
          </div>
        ) : (
          <>
            {/* Groups & trips */}
            {groups.length > 0 && (
              <div style={{ display: "grid", gap: 12 }}>
                <div className="muted" style={{ fontSize: 12, fontWeight: 700, letterSpacing: "0.08em" }}>GROUPS &amp; TRIPS</div>
                {groups.map((g) => {
                  const isOpen = expanded.has(g.group.id);
                  const shown = g.memberIds.slice(0, 3);
                  const extra = g.memberIds.length - shown.length;
                  return (
                    <div key={g.group.id} style={{ borderRadius: 16, background: isOpen ? "var(--accent-ghost, rgba(0,0,0,0.03))" : "transparent", transition: "background 0.15s" }}>
                      <button
                        onClick={() => toggle(g.group.id)}
                        style={{ width: "100%", background: "none", border: "none", cursor: "pointer", padding: "10px 12px", display: "flex", alignItems: "center", gap: 14, textAlign: "left" }}
                      >
                        <div style={{ display: "flex", alignItems: "center", flexShrink: 0 }}>
                          {shown.map((uid, i) => (
                            <span key={uid} style={{ marginLeft: i === 0 ? 0 : -12 }}><Avatar id={uid} name={name(uid)} size={44} ring /></span>
                          ))}
                          {extra > 0 && (
                            <span style={{ marginLeft: -12, width: 44, height: 44, borderRadius: 999, background: "var(--border)", color: "var(--text-2)", display: "grid", placeItems: "center", fontWeight: 700, fontSize: 14, boxShadow: "0 0 0 2px var(--bg)" }}>+{extra}</span>
                          )}
                        </div>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontWeight: 700, fontSize: 19, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{g.group.name}</div>
                          <div className="muted" style={{ fontSize: 14 }}>{g.peopleCount} {g.peopleCount === 1 ? "person" : "people"} · {g.group.kind === "trip" ? "trip" : "group"}</div>
                        </div>
                        <div style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
                          <span style={{ fontWeight: 750, fontSize: 19, color: g.net > 0 ? "var(--positive)" : g.net < 0 ? "var(--negative)" : "var(--text-2)" }}>
                            {g.net === 0 ? amt(0) : (g.net > 0 ? "" : "−") + amt(g.net)}
                          </span>
                          <span className="muted" style={{ transform: isOpen ? "rotate(180deg)" : "none", transition: "transform 0.15s", fontSize: 12 }}>▾</span>
                        </div>
                      </button>
                      {isOpen && (
                        <div style={{ padding: "0 14px 12px 70px", display: "grid", gap: 10 }}>
                          {g.perUser.length === 0 && <div className="muted" style={{ fontSize: 13 }}>Everyone’s settled up.</div>}
                          {g.perUser.map((b) => (
                            <button key={b.userId} onClick={() => openPerson(b.userId, b.net)}
                              style={{ background: "none", border: "none", cursor: "pointer", padding: 0, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, textAlign: "left" }}>
                              <span style={{ fontSize: 16 }}>{name(b.userId)}</span>
                              <span style={{ fontWeight: 700, fontSize: 16, color: b.net > 0 ? "var(--positive)" : "var(--negative)" }}>{amt(b.net)}</span>
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}

            {/* Direct */}
            {direct.length > 0 && (
              <div style={{ display: "grid", gap: 4 }}>
                <div className="muted" style={{ fontSize: 12, fontWeight: 700, letterSpacing: "0.08em", marginBottom: 8 }}>DIRECT</div>
                {direct.map((b) => (
                  <button
                    key={b.userId}
                    onClick={() => openPerson(b.userId, b.net)}
                    style={{ width: "100%", background: "none", border: "none", cursor: "pointer", padding: "10px 4px", display: "flex", alignItems: "center", gap: 14, textAlign: "left" }}
                  >
                    <Avatar id={b.userId} name={name(b.userId)} size={44} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontWeight: 700, fontSize: 18, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{name(b.userId)}</div>
                      <div style={{ fontSize: 14, color: b.net > 0 ? "var(--positive)" : "var(--negative)" }}>{b.net > 0 ? "owes you" : "you owe"}</div>
                    </div>
                    <span style={{ fontWeight: 750, fontSize: 19, color: b.net > 0 ? "var(--positive)" : "var(--negative)", flexShrink: 0 }}>{amt(b.net)}</span>
                  </button>
                ))}
              </div>
            )}
          </>
        )}
      </section>

      {/* Person detail sheet — opens when you tap a friend */}
      <Modal open={!!person} onClose={() => setPerson(null)}>
        {person && (
          <div style={{ display: "grid", gap: 20 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
              <Avatar id={person.userId} name={person.name} size={56} />
              <div style={{ minWidth: 0 }}>
                <div style={{ fontWeight: 750, fontSize: 24, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{person.name}</div>
                <div style={{ fontSize: 15, color: person.net > 0 ? "var(--positive)" : "var(--negative)" }}>{person.net > 0 ? "owes you" : "you owe"}</div>
              </div>
            </div>
            <div style={{ fontSize: 44, fontWeight: 750, lineHeight: 1, color: person.net > 0 ? "var(--positive)" : "var(--negative)" }}>{amt(person.net)}</div>
            <div style={{ display: "flex", gap: 12 }}>
              <button className="btn" style={{ flex: 1 }} onClick={() => openSettle(person.userId, person.net)}>Settle up</button>
              <button className="btn ghost" style={{ flex: "0 0 auto", minWidth: 120 }} onClick={() => void remind(person)}>{reminded ? "Copied!" : "Remind"}</button>
            </div>
          </div>
        )}
      </Modal>

      <Modal open={!!target} onClose={() => setTarget(null)}>
        {target && (
          <div style={{ display: "grid", gap: 12 }}>
            <h2 style={{ margin: 0 }}>Settle with {target.name}</h2>
            <p className="muted" style={{ margin: 0, fontSize: 13 }}>{target.net >= 0 ? `${target.name} pays you back.` : `You pay ${target.name} back.`}</p>
            <label style={{ display: "grid", gap: 4 }}>
              <span className="muted" style={{ fontSize: 12 }}>Amount ({base})</span>
              <input className="input" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
            </label>
            <label style={{ display: "grid", gap: 4 }}>
              <span className="muted" style={{ fontSize: 12 }}>{target.net >= 0 ? "Received into" : "Paid from"} account</span>
              <select className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
                <option value="">None — just mark settled</option>
                {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
              </select>
            </label>
            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
              <button className="btn ghost" onClick={() => setTarget(null)}>Cancel</button>
              <button className="btn" onClick={() => void confirmSettle()} disabled={busy || !(Number(amount) > 0)}>{busy ? "Settling…" : "Settle"}</button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}
