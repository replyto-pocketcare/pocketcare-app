"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { useQuery } from "@powersync/react";
import { money } from "@sanvya/money";
import { useBaseCurrency } from "../../src/hooks";
import { useMoneyFmt } from "../../src/ui/Money";
import { Modal } from "../../src/ui/Modal";
import { AmountInput } from "../../src/ui/AmountInput";
import { useSplitOverview, useUserProfiles, usePersonLedger, useFriendInsights, type FriendInsight } from "../../src/splits/hooks";
import { settleUp, type SettlementStatus } from "../../src/splits/write";
import { TransactionTile } from "../../src/ui/TransactionTile";
import { MaterialIcon, type MaterialIconName } from "../../src/ui/MaterialIcon";
import { PayViaUpi } from "../../src/payments/PayViaUpi";
import { PendingSettlements } from "../../src/payments/PendingSettlements";
import { NewGroupModal } from "../../src/splits/NewGroupModal";
import { PayAnyone } from "../../src/payments/PayAnyone";
import { ListSkeleton } from "../../src/ui/Skeleton";

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

function BalanceRow({ b, name, amt, onOpen }: { b: { userId: string; net: number }; name: (id: string) => string; amt: (n: number) => string; onOpen: (id: string, net: number) => void }) {
  const { t } = useTranslation("splits");
  return (
    <button
      onClick={() => onOpen(b.userId, b.net)}
      className="card lift"
      style={{ width: "100%", cursor: "pointer", padding: "12px 14px", display: "flex", alignItems: "center", gap: 12, textAlign: "left" }}
    >
      <Avatar id={b.userId} name={name(b.userId)} size={38} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 700, fontSize: 16, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{name(b.userId)}</div>
        <div style={{ fontSize: 13, color: b.net > 0 ? "var(--positive)" : "var(--negative)" }}>{b.net > 0 ? t("owesYouInline") : t("youOweInline")}</div>
      </div>
      <span style={{ fontWeight: 750, fontSize: 17, color: b.net > 0 ? "var(--positive)" : "var(--negative)", flexShrink: 0 }}>{amt(b.net)}</span>
    </button>
  );
}

export default function SplitsPage() {
  const { t } = useTranslation("splits");
  const router = useRouter();
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const overview = useSplitOverview();
  const profiles = useUserProfiles();
  const name = (id: string) => profiles.get(id)?.name ?? "Someone";

  const { data: accounts = [] } = useQuery<{ id: string; name: string }>(
    "SELECT id, name FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real' AND type NOT IN ('stocks','mutual_funds') ORDER BY created_at",
  );
  const { data: settleGroups = [], isLoading: splitsLoading } = useQuery<{ group_id: string; user_id: string }>(
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
  /** The person sheet's ledger is collapsed by default and revealed by a
      button. When open it renders in full and must NOT get its own scroller: a
      nested scroll area inside page/modal content captures a touch swipe for
      its whole duration (see §7e of docs/plans/ui-redesign-2026-07.md). The
      modal overlay already scrolls. */
  const [showAllLines, setShowAllLines] = useState(false);
  const [newGroup, setNewGroup] = useState(false);
  const [payAnyone, setPayAnyone] = useState(false);

  function openPerson(userId: string, net: number) {
    setReminded(false);
    setShowAllLines(false);
    setPerson({ userId, name: name(userId), net });
  }
  function openSettle(userId: string, net: number) {
    setPerson(null);
    setTarget({ userId, name: name(userId), net });
    setAmount((Math.abs(net) / 100).toFixed(2));
    setAccountId("");
  }
  async function remind(p: SettleTarget) {
    const amtStr = fmt(money(Math.abs(p.net), base));
    const line = p.net > 0
      ? t("remindOwed", { name: p.name, amount: amtStr })
      : t("remindOwe", { name: p.name, amount: amtStr });
    try {
      if (typeof navigator !== "undefined" && navigator.share) await navigator.share({ text: line });
      else if (typeof navigator !== "undefined" && navigator.clipboard) { await navigator.clipboard.writeText(line); setReminded(true); }
    } catch { /* user dismissed share sheet */ }
  }
  /**
   * Record the settlement.
   *
   * `status` is "confirmed" for the manual mark-settled path (two people
   * agreeing in person — nothing to verify) and "pending" when it came from a
   * UPI hand-off, where only the payee can confirm the money actually arrived.
   */
  async function confirmSettle(status: SettlementStatus = "confirmed", upiRef?: string) {
    if (!target) return;
    const minor = Math.round((Number(amount) || 0) * 100);
    if (minor <= 0) return;
    const gid = settleGroups.find((g) => g.user_id === target.userId)?.group_id;
    if (!gid) { setBusy(false); setTarget(null); return; }
    setBusy(true);
    try {
      await settleUp({
        otherUserId: target.userId, groupId: gid, amount: minor,
        direction: target.net >= 0 ? "received" : "paid",
        accountId: accountId || null, currency: base,
        status,
        ...(upiRef ? { method: "upi_intent", upiRef } : {}),
      });
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

  // Aggregate every 1:1 balance (group per-user + direct) into one net per person
  // so "who owes whom" is answered across the whole ledger, not per group.
  const perPerson = useMemo(() => {
    const m = new Map<string, number>();
    for (const g of groups) for (const b of g.perUser) m.set(b.userId, (m.get(b.userId) ?? 0) + b.net);
    for (const d of direct) m.set(d.userId, (m.get(d.userId) ?? 0) + d.net);
    return [...m.entries()].filter(([, n]) => n !== 0).map(([userId, net]) => ({ userId, net }));
  }, [groups, direct]);
  const owedList = perPerson.filter((p) => p.net > 0).sort((a, b) => b.net - a.net);   // they owe you
  const oweList = perPerson.filter((p) => p.net < 0).sort((a, b) => a.net - b.net);     // you owe them

  // Everyone you share a group with — including people you're square with, who
  // the owes/owed lists drop by construction. Settled friends still belong in a
  // "Friends" directory; that's what makes it a directory rather than a debt list.
  const everyone = useMemo(() => {
    const nets = new Map(perPerson.map((p) => [p.userId, p.net] as const));
    const ids = new Set<string>();
    for (const g of groups) for (const uid of g.memberIds) ids.add(uid);
    for (const d of direct) ids.add(d.userId);
    return [...ids]
      .map((userId) => ({ userId, net: nets.get(userId) ?? 0 }))
      .sort((a, b) => Math.abs(b.net) - Math.abs(a.net) || name(a.userId).localeCompare(name(b.userId)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [groups, direct, perPerson, profiles]);

  // Itemised transactions for whoever's detail sheet is open.
  const ledger = usePersonLedger(person?.userId ?? "");
  const fmtDate = (d: string) => {
    const t = new Date(d);
    return Number.isNaN(t.getTime()) ? "" : t.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "2-digit" });
  };

  return (
    <div className="fade-up" style={{ display: "grid", gap: 20 }}>
      {/* Payments claimed by others, waiting on you — top of the page because
          an unconfirmed payment blocks someone else's balance from clearing. */}
      <PendingSettlements />

      <section className="card" style={{ padding: 18, display: "grid", gap: 16 }}>
        {/* The row WRAPS. Two non-shrinking buttons plus a `minWidth: 0` title
            is the recipe for the title collapsing to one character per line:
            the buttons refuse to give up width, so the only flexible item
            absorbs all of the shortfall. `flex: 1 1 <basis>` on the title gives
            it a real width to defend, and wrapping drops the buttons onto their
            own line once they no longer fit beside it. */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
          <div style={{ flex: "1 1 160px", minWidth: 0 }}>
            <div style={{ color: "var(--accent)", fontWeight: 700, fontSize: 11, letterSpacing: "0.08em" }}>{t("eyebrow")}</div>
            <h1 style={{ margin: "1px 0 0", fontSize: 22 }}>{t("yourBalance")}</h1>
          </div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button className="btn ghost" style={{ gap: 6 }} onClick={() => setPayAnyone(true)}>
              <MaterialIcon name="payments" size={16} /> {t("payAnyoneCta")}
            </button>
            <button className="btn" style={{ gap: 6 }} onClick={() => setNewGroup(true)}>
              <MaterialIcon name="add" size={16} /> {t("newGroupCta")}
            </button>
          </div>
        </div>

        {/* Net position — compact */}
        <div style={{ background: "var(--accent-ghost, rgba(0,0,0,0.04))", borderRadius: 14, padding: "14px 16px", display: "grid", gap: 10 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10 }}>
            <span className="muted" style={{ fontSize: 12.5 }}>{t("netPosition")}</span>
            <span style={{ fontSize: 26, fontWeight: 750, lineHeight: 1, color: netColor, whiteSpace: "nowrap" }}>
              {netPosition >= 0 ? "+" : "−"}{amt(netPosition)}
            </span>
          </div>
          <div style={{ width: "100%", height: 8, borderRadius: 999, overflow: "hidden", display: "flex", background: "var(--border)" }}>
            <div style={{ width: `${owePct}%`, background: "var(--negative)" }} />
            <div style={{ width: `${owedPct}%`, background: "var(--positive)" }} />
          </div>
        </div>

        {empty && splitsLoading ? (
          <ListSkeleton rows={3} />
        ) : empty ? (
          <div style={{ padding: "24px 8px", textAlign: "center", display: "grid", gap: 10, justifyItems: "center" }}>
            <div style={{ fontSize: 26 }}>◑</div>
            <h2 style={{ margin: 0 }}>{t("empty.title")}</h2>
            <p className="muted" style={{ margin: 0, maxWidth: 380 }}>{t("empty.bodyPre")}<button onClick={() => setNewGroup(true)} style={{ background: "none", border: "none", padding: 0, font: "inherit", color: "var(--accent)", cursor: "pointer" }}>{t("empty.bodyLink")}</button>{t("empty.bodyPost")}</p>
          </div>
        ) : null}
      </section>

      {/* Groups & trips — tiled; an expanded group spans the full row. */}
      {!empty && groups.length > 0 && (
        <section id="groups" style={{ display: "grid", gap: 12 }}>
          <div className="muted" style={{ fontSize: 12, fontWeight: 700, letterSpacing: "0.08em" }}>{t("sections.groupsAndTrips")}</div>
          <div className="list-grid">
            {groups.map((g) => {
              const isOpen = expanded.has(g.group.id);
              const shown = g.memberIds.slice(0, 4);
              const extra = g.memberIds.length - shown.length;
              const netTone = g.net > 0 ? "var(--positive)" : g.net < 0 ? "var(--negative)" : "var(--text-2)";
              const gOwed = g.perUser.reduce((s, b) => s + Math.max(0, b.net), 0);
              const gOwe = g.perUser.reduce((s, b) => s + Math.max(0, -b.net), 0);
              return (
                <div
                  key={g.group.id}
                  className={isOpen ? "card" : "card lift"}
                  style={{ padding: 0, overflow: "hidden", gridColumn: isOpen ? "1 / -1" : "auto", background: isOpen ? "var(--accent-ghost)" : "var(--surface)", transition: "background 0.15s" }}
                >
                  {/* EMI/loan-style tile: avatars top-left, arrow top-right,
                      title + count bottom-left, amount bottom-right. */}
                  <button
                    onClick={() => toggle(g.group.id)}
                    style={{ width: "100%", background: "none", border: "none", cursor: "pointer", padding: 16, display: "grid", gap: 14, textAlign: "left" }}
                  >
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10 }}>
                      <div style={{ display: "flex", alignItems: "center", minWidth: 0 }}>
                        {shown.map((uid, i) => (
                          <span key={uid} style={{ marginLeft: i === 0 ? 0 : -10 }}><Avatar id={uid} name={name(uid)} size={30} ring /></span>
                        ))}
                        {extra > 0 && (
                          <span style={{ marginLeft: -10, width: 30, height: 30, borderRadius: 999, background: "var(--border)", color: "var(--text-2)", display: "grid", placeItems: "center", fontWeight: 700, fontSize: 11, boxShadow: "0 0 0 2px var(--bg)", flexShrink: 0 }}>+{extra}</span>
                        )}
                      </div>
                      <span className="muted" aria-hidden style={{ transform: isOpen ? "rotate(180deg)" : "none", transition: "transform 0.15s", fontSize: 12, flexShrink: 0 }}>▾</span>
                    </div>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", gap: 12 }}>
                      <div style={{ minWidth: 0 }}>
                        <div style={{ fontWeight: 700, fontSize: 17, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{g.group.name}</div>
                        <div className="muted" style={{ fontSize: 13, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{t("membersLine", { count: g.peopleCount, kind: t(g.group.kind === "trip" ? "kind.trip" : "kind.group") })}</div>
                      </div>
                      <span style={{ fontWeight: 750, fontSize: 19, whiteSpace: "nowrap", flexShrink: 0, color: netTone }}>
                        {g.net === 0 ? amt(0) : (g.net > 0 ? "" : "−") + amt(g.net)}
                      </span>
                    </div>
                    {/* Both directions, not just the net: inside one trip you can
                        be owed by two people and owe a third, and a single net
                        figure hides that entirely. */}
                    {(gOwed > 0 || gOwe > 0) && (
                      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", fontSize: 12.5 }}>
                        {gOwed > 0 && (
                          <span style={{ display: "inline-flex", alignItems: "center", gap: 5, color: "var(--positive)" }}>
                            <MaterialIcon name="trending_up" size={14} />{t("owedInGroup", { amount: amt(gOwed) })}
                          </span>
                        )}
                        {gOwe > 0 && (
                          <span style={{ display: "inline-flex", alignItems: "center", gap: 5, color: "var(--negative)" }}>
                            <MaterialIcon name="payments" size={14} />{t("oweInGroup", { amount: amt(gOwe) })}
                          </span>
                        )}
                      </div>
                    )}
                  </button>
                  {isOpen && (
                    <div style={{ padding: "12px 16px 14px", display: "grid", gap: 10, borderTop: "1px solid var(--border)" }}>
                      {/* The two things you actually want from an open group:
                          record a shared expense in it, or go to the group. */}
                      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                        <Link href={`/transactions/new?split=${g.group.id}`} className="btn" style={{ gap: 6, padding: "7px 14px", minHeight: 0 }}>
                          <MaterialIcon name="add" size={15} /> {t("addExpense")}
                        </Link>
                        <Link href={`/groups/${g.group.id}`} className="btn ghost" style={{ gap: 6, padding: "7px 14px", minHeight: 0 }}>
                          <MaterialIcon name="chevron_right" size={15} /> {t("openGroup")}
                        </Link>
                      </div>
                      {g.perUser.length === 0 && <div className="muted" style={{ fontSize: 13 }}>{t("settledUp")}</div>}
                      {g.perUser.map((b) => (
                        <button key={b.userId} className="tap-row" onClick={() => openPerson(b.userId, b.net)}
                          style={{ background: "none", border: "none", cursor: "pointer", padding: "6px 8px", margin: "0 -8px", display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, textAlign: "left", color: "inherit" }}>
                          <span style={{ display: "flex", alignItems: "center", gap: 10, minWidth: 0 }}>
                            <Avatar id={b.userId} name={name(b.userId)} size={28} />
                            <span style={{ fontSize: 15, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{name(b.userId)}</span>
                          </span>
                          <span style={{ fontWeight: 700, fontSize: 15, flexShrink: 0, color: b.net > 0 ? "var(--positive)" : "var(--negative)" }}>{amt(b.net)}</span>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Who owes whom — every 1:1 balance aggregated across groups + direct. */}
      {!empty && perPerson.length > 0 && (
        <section style={{ display: "grid", gap: 16 }}>
          {owedList.length > 0 && (
            <div id="owed" style={{ display: "grid", gap: 10 }}>
              <div className="muted" style={{ fontSize: 12, fontWeight: 700, letterSpacing: "0.08em" }}>{t("sections.owesYou")}</div>
              <div className="list-grid">{owedList.map((b) => <BalanceRow key={b.userId} b={b} name={name} amt={amt} onOpen={openPerson} />)}</div>
            </div>
          )}
          {oweList.length > 0 && (
            <div id="owe" style={{ display: "grid", gap: 10 }}>
              <div className="muted" style={{ fontSize: 12, fontWeight: 700, letterSpacing: "0.08em" }}>{t("sections.youOwe")}</div>
              <div className="list-grid">{oweList.map((b) => <BalanceRow key={b.userId} b={b} name={name} amt={amt} onOpen={openPerson} />)}</div>
            </div>
          )}
        </section>
      )}

      {/* Friends — everyone you share a group with, settled or not. */}
      {everyone.length > 0 && (
        <section id="friends" style={{ display: "grid", gap: 10 }}>
          <div className="muted" style={{ fontSize: 12, fontWeight: 700, letterSpacing: "0.08em" }}>{t("sections.friends")}</div>
          <div className="list-grid">
            {everyone.map((b) => (
              <TransactionTile
                key={b.userId}
                raw={name(b.userId)}
                avatarIcon="person"
                avatarSeed={b.userId}
                amountMinor={Math.abs(b.net)}
                currency={base}
                type={b.net > 0 ? "income" : "expense"}
                amountText={b.net === 0 ? t("settledUp") : amt(b.net)}
                amountColor={b.net > 0 ? "var(--positive)" : b.net < 0 ? "var(--negative)" : "var(--text-2)"}
                meta={b.net === 0 ? undefined : b.net > 0 ? t("owesYouInline") : t("youOweInline")}
                card
              />
            ))}
          </div>
        </section>
      )}

      {/* Behavioural insights — only what the ledger actually supports. */}
      <FriendInsights nameOf={name} amt={amt} />


      <PayAnyone open={payAnyone} onClose={() => setPayAnyone(false)} />

      <NewGroupModal open={newGroup} onClose={(id) => { setNewGroup(false); if (id) router.push(`/groups/${id}`); }} />

      {/* Person detail sheet — opens when you tap a friend. Shows the total,
          the itemised transactions behind it, and settle/remind actions. */}
      <Modal open={!!person} onClose={() => setPerson(null)}>
        {person && (
          <div style={{ display: "grid", gap: 18 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
              <Avatar id={person.userId} name={person.name} size={52} />
              <div style={{ minWidth: 0 }}>
                <div style={{ fontWeight: 750, fontSize: 22, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{person.name}</div>
                <div style={{ fontSize: 14, color: person.net > 0 ? "var(--positive)" : "var(--negative)" }}>{person.net > 0 ? t("owesYouInline") : t("youOweInline")}</div>
              </div>
            </div>

            {/* Total at top */}
            <div style={{ background: "var(--surface-2)", borderRadius: 14, padding: "14px 16px", display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10 }}>
              <span className="muted" style={{ fontSize: 12.5 }}>{person.net > 0 ? t("totalOwedToYou") : t("totalYouOwe")}</span>
              <span style={{ fontSize: 30, fontWeight: 750, lineHeight: 1, whiteSpace: "nowrap", color: person.net > 0 ? "var(--positive)" : "var(--negative)" }}>{amt(person.net)}</span>
            </div>

            {/* The itemised ledger is behind a button, not shown by default.
                This sheet's job is "how much, and settle it" — a wall of line
                items pushed the two actions below the fold and made the sheet
                read as a statement. It's one tap away when you want to check. */}
            {ledger.lines.length > 0 && !showAllLines && (
              <button className="btn ghost" style={{ justifyContent: "center", gap: 8 }} onClick={() => setShowAllLines(true)}>
                <MaterialIcon name="receipt_long" size={16} />
                {t("viewLines", { count: ledger.lines.length, defaultValue: "View {{count}} transactions" })}
              </button>
            )}
            {ledger.lines.length > 0 && showAllLines && (
              <div className="row-stack" style={{ margin: "0 -4px", padding: "0 4px" }}>
                {ledger.lines.map((l) => (
                  <div key={l.id} className="row-tile" style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10 }}>
                    <div style={{ minWidth: 0 }}>
                      <div style={{ fontSize: 14, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{l.description}</div>
                      {l.date && <div className="muted" style={{ fontSize: 11.5 }}>{fmtDate(l.date)}{l.kind === "settlement" ? ` · ${t("settlementTag")}` : ""}</div>}
                    </div>
                    <span style={{ fontSize: 14, fontWeight: 650, whiteSpace: "nowrap", flexShrink: 0, color: l.net > 0 ? "var(--positive)" : "var(--negative)" }}>
                      {l.net > 0 ? "+" : "−"}{amt(l.net)}
                    </span>
                  </div>
                ))}
                <button className="chip" style={{ justifySelf: "start" }} onClick={() => setShowAllLines(false)}>
                  {t("hideLines", { defaultValue: "Hide transactions" })}
                </button>
              </div>
            )}

            <div style={{ display: "flex", gap: 12 }}>
              <button className="btn" style={{ flex: 1 }} onClick={() => openSettle(person.userId, person.net)}>{t("settleUp")}</button>
              <button className="btn ghost" style={{ flex: "0 0 auto", minWidth: 110 }} onClick={() => void remind(person)}>{reminded ? t("copied") : t("remind")}</button>
            </div>
          </div>
        )}
      </Modal>

      <Modal open={!!target} onClose={() => setTarget(null)}>
        {target && (
          <div style={{ display: "grid", gap: 12 }}>
            <h2 style={{ margin: 0 }}>{t("settleWith", { name: target.name })}</h2>
            <p className="muted" style={{ margin: 0, fontSize: 13 }}>{target.net >= 0 ? t("theyPayYouBack", { name: target.name }) : t("youPayThemBack", { name: target.name })}</p>
            <label style={{ display: "grid", gap: 4 }}>
              <span className="muted" style={{ fontSize: 12 }}>{t("amountLabel", { currency: base })}</span>
              <AmountInput currency={base} value={amount} onChange={setAmount} ariaLabel="Settle amount" />
            </label>
            <label style={{ display: "grid", gap: 4 }}>
              <span className="muted" style={{ fontSize: 12 }}>{target.net >= 0 ? t("receivedInto") : t("paidFrom")}</span>
              <select className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
                <option value="">{t("noneMarkSettled")}</option>
                {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
              </select>
            </label>
            {/* Pay via UPI — only when YOU owe THEM, in INR. Their handle is
                fetched just-in-time; nothing about it is stored on this device. */}
            {target.net < 0 && base === "INR" && Number(amount) > 0 && (
              <div style={{ borderTop: "1px solid var(--border)", paddingTop: 12, display: "grid", gap: 8 }}>
                <PayViaUpi
                  counterpartyId={target.userId}
                  counterpartyName={target.name}
                  amountMinor={Math.round((Number(amount) || 0) * 100)}
                  onPaid={(ref) => void confirmSettle("pending", ref)}
                />
              </div>
            )}

            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
              <button className="btn ghost" onClick={() => setTarget(null)}>{t("cancel")}</button>
              <button className="btn" onClick={() => void confirmSettle()} disabled={busy || !(Number(amount) > 0)}>{busy ? t("settling") : t("settle")}</button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}

/**
 * Headline patterns across every group you share. The ranking logic lives in
 * `@sanvya/splits-insights` (pure + unit-tested); this only renders it.
 *
 * Renders NOTHING when there isn't enough history — a section that says
 * "biggest lender: someone, ₹0" on a two-expense ledger teaches people to
 * distrust the whole page.
 */
function FriendInsights({ nameOf, amt }: { nameOf: (id: string) => string; amt: (n: number) => string }) {
  const { t } = useTranslation("splits");
  const { insights } = useFriendInsights();
  if (insights.length === 0) return null;

  const META: Record<FriendInsight["key"], { icon: MaterialIconName; tone: string }> = {
    biggest_lender: { icon: "volunteer_activism", tone: "var(--positive)" },
    owes_you_most: { icon: "trending_up", tone: "var(--positive)" },
    you_owe_most: { icon: "payments", tone: "var(--negative)" },
    always_owes: { icon: "autorenew", tone: "var(--text)" },
    always_owed: { icon: "autorenew", tone: "var(--text)" },
    fastest_settler: { icon: "bolt", tone: "var(--positive)" },
    slowest_settler: { icon: "more_horiz", tone: "var(--warning)" },
  };

  const valueFor = (i: FriendInsight): string => {
    if (i.key === "fastest_settler" || i.key === "slowest_settler") return t("insights.days", { count: Math.round(i.value) });
    if (i.key === "always_owes" || i.key === "always_owed") return t("insights.groups", { count: i.value });
    return amt(i.value);
  };

  return (
    <section style={{ display: "grid", gap: 10 }}>
      <div className="muted" style={{ fontSize: 12, fontWeight: 700, letterSpacing: "0.08em" }}>{t("sections.insights")}</div>
      <div className="list-grid">
        {insights.map((i) => (
          <div key={i.key} className="card" style={{ padding: 14, display: "flex", gap: 12, alignItems: "flex-start" }}>
            <span style={{ color: META[i.key].tone, flexShrink: 0, marginTop: 1 }}>
              <MaterialIcon name={META[i.key].icon} size={20} />
            </span>
            <div style={{ minWidth: 0, flex: 1 }}>
              <div className="muted" style={{ fontSize: 11.5, fontWeight: 700, letterSpacing: "0.04em", textTransform: "uppercase" }}>
                {t(`insights.${i.key}`)}
              </div>
              <div style={{ fontWeight: 700, fontSize: 15, marginTop: 2, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                {nameOf(i.friendId)}
              </div>
              <div style={{ fontSize: 13, color: META[i.key].tone, marginTop: 1 }}>{valueFor(i)}</div>
            </div>
          </div>
        ))}
      </div>
      <p className="muted" style={{ fontSize: 11.5, margin: 0 }}>{t("insights.footnote")}</p>
    </section>
  );
}
