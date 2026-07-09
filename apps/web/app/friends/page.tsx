"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { useMoneyFmt } from "../../src/ui/Money";
import { Modal } from "../../src/ui/Modal";
import { useFriendBalances, useUserProfiles, useConnections } from "../../src/splits/hooks";
import { settleUp } from "../../src/splits/write";

interface SettleTarget { userId: string; name: string; net: number }

export default function FriendsPage() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const balances = useFriendBalances();
  const profiles = useUserProfiles();
  const connections = useConnections();
  const { data: accounts = [] } = useQuery<{ id: string; name: string }>(
    "SELECT id, name FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real' ORDER BY created_at",
  );
  const { data: settleGroups = [] } = useQuery<{ group_id: string; user_id: string }>(
    "SELECT group_id, user_id FROM split_group_members WHERE deleted_at IS NULL",
  );

  const netByUser = new Map(balances.map((b) => [b.userId, b.net] as const));
  const owed = balances.reduce((s, b) => s + Math.max(0, b.net), 0);
  const owe = balances.reduce((s, b) => s + Math.max(0, -b.net), 0);
  const name = (id: string) => profiles.get(id)?.name ?? "Someone";

  // People to show: everyone you have a balance with, plus your connections.
  const people = useMemo(() => {
    const ids = new Set<string>([...balances.map((b) => b.userId), ...connections.map((c) => c.id)]);
    return [...ids];
  }, [balances, connections]);

  const [target, setTarget] = useState<SettleTarget | null>(null);
  const [amount, setAmount] = useState("");
  const [accountId, setAccountId] = useState("");
  const [busy, setBusy] = useState(false);

  function openSettle(userId: string, net: number) {
    setTarget({ userId, name: name(userId), net });
    setAmount((Math.abs(net) / 100).toFixed(2));
    setAccountId("");
  }
  async function confirmSettle() {
    if (!target) return;
    const minor = Math.round((Number(amount) || 0) * 100);
    if (minor <= 0) return;
    // pick a shared group with this person to attach the settlement to
    const gid = settleGroups.find((g) => g.user_id === target.userId)?.group_id;
    if (!gid) { setBusy(false); setTarget(null); return; }
    setBusy(true);
    try {
      await settleUp({ otherUserId: target.userId, groupId: gid, amount: minor, direction: target.net >= 0 ? "received" : "paid", accountId: accountId || null, currency: base });
      setTarget(null);
    } finally { setBusy(false); }
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>Friends</h1>
        <Link href="/groups" className="btn ghost">Groups &amp; trips</Link>
      </div>

      <section className="card" style={{ padding: 20, display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12, flexWrap: "wrap" }}>
        <div><div className="muted" style={{ fontSize: 13 }}>You’re owed</div><div style={{ fontSize: 30, fontWeight: 750, color: "var(--positive)" }}>{fmt(money(owed, base))}</div></div>
        <div style={{ textAlign: "right" }}><div className="muted" style={{ fontSize: 13 }}>You owe</div><div style={{ fontSize: 20, fontWeight: 700, color: "var(--negative)" }}>{fmt(money(owe, base))}</div></div>
      </section>

      {people.length === 0 ? (
        <div className="card" style={{ padding: 32, textAlign: "center", display: "grid", gap: 10, justifyItems: "center" }}>
          <div style={{ fontSize: 26 }}>◑</div>
          <h2 style={{ margin: 0 }}>No friends yet</h2>
          <p className="muted" style={{ margin: 0, maxWidth: 380 }}>Create a group and invite people from <Link href="/groups">Groups &amp; trips</Link>. Once they join, you can split and settle here.</p>
        </div>
      ) : (
        <div className="card" style={{ padding: 8 }}>
          {people.map((uid) => {
            const net = netByUser.get(uid) ?? 0;
            const canSettle = net !== 0 && settleGroups.some((g) => g.user_id === uid);
            return (
              <div key={uid} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "12px 14px", borderBottom: "1px solid var(--border)" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 10, minWidth: 0 }}>
                  <span style={{ width: 30, height: 30, borderRadius: 999, flexShrink: 0, background: "var(--accent)", color: "#fff", display: "grid", placeItems: "center", fontWeight: 700, fontSize: 13 }}>{name(uid).charAt(0).toUpperCase()}</span>
                  <span style={{ whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{name(uid)}</span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 10, flexShrink: 0 }}>
                  <span style={{ fontWeight: 600, color: net > 0 ? "var(--positive)" : net < 0 ? "var(--negative)" : "var(--text-2)" }}>
                    {net > 0 ? `owes you ${fmt(money(net, base))}` : net < 0 ? `you owe ${fmt(money(-net, base))}` : "settled"}
                  </span>
                  {canSettle && <button className="chip" style={{ fontSize: 12, padding: "3px 10px" }} onClick={() => openSettle(uid, net)}>Settle</button>}
                </div>
              </div>
            );
          })}
        </div>
      )}

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
