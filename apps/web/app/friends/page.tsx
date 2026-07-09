"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { useMoneyFmt } from "../../src/ui/Money";
import { Modal } from "../../src/ui/Modal";
import { useFriendBalances, useContacts } from "../../src/splits/hooks";
import { addContact, settleUp } from "../../src/splits/write";

interface SettleTarget { contactId: string; name: string; net: number }

export default function FriendsPage() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const balances = useFriendBalances();
  const contacts = useContacts();
  const { data: accounts = [] } = useQuery<{ id: string; name: string }>(
    "SELECT id, name FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real' ORDER BY created_at",
  );
  const [name, setName] = useState("");

  const netByContact = new Map(balances.map((b) => [b.contactId, b.net] as const));
  const owed = balances.reduce((s, b) => s + Math.max(0, b.net), 0);
  const owe = balances.reduce((s, b) => s + Math.max(0, -b.net), 0);

  // settle dialog
  const [target, setTarget] = useState<SettleTarget | null>(null);
  const [amount, setAmount] = useState("");
  const [accountId, setAccountId] = useState<string>(""); // "" = None
  const [busy, setBusy] = useState(false);

  async function add() {
    const n = name.trim();
    if (!n) return;
    await addContact(n);
    setName("");
  }

  function openSettle(t: SettleTarget) {
    setTarget(t);
    setAmount((Math.abs(t.net) / 100).toFixed(2));
    setAccountId("");
  }
  async function confirmSettle() {
    if (!target) return;
    const minor = Math.round((Number(amount) || 0) * 100);
    if (minor <= 0) return;
    setBusy(true);
    try {
      await settleUp({
        contactId: target.contactId,
        amount: minor,
        direction: target.net >= 0 ? "received" : "paid",
        accountId: accountId || null,
        currency: base,
      });
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
        <div>
          <div className="muted" style={{ fontSize: 13 }}>You’re owed</div>
          <div style={{ fontSize: 30, fontWeight: 750, color: "var(--positive)" }}>{fmt(money(owed, base))}</div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div className="muted" style={{ fontSize: 13 }}>You owe</div>
          <div style={{ fontSize: 20, fontWeight: 700, color: "var(--negative)" }}>{fmt(money(owe, base))}</div>
        </div>
      </section>

      <div style={{ display: "flex", gap: 8 }}>
        <input className="input" placeholder="Add a contact…" value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void add(); } }} />
        <button className="btn" onClick={() => void add()} disabled={!name.trim()}>Add</button>
      </div>

      {contacts.length === 0 ? (
        <div className="card" style={{ padding: 32, textAlign: "center", display: "grid", gap: 10, justifyItems: "center" }}>
          <div style={{ fontSize: 26 }}>◑</div>
          <h2 style={{ margin: 0 }}>No friends yet</h2>
          <p className="muted" style={{ margin: 0, maxWidth: 360 }}>Add a contact, then split an expense with them from the <Link href="/transactions/new">Add transaction</Link> screen.</p>
        </div>
      ) : (
        <div className="card" style={{ padding: 8 }}>
          {contacts.map((c) => {
            const net = netByContact.get(c.id) ?? 0;
            return (
              <div key={c.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "12px 14px", borderBottom: "1px solid var(--border)" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 10, minWidth: 0 }}>
                  <span style={{ width: 30, height: 30, borderRadius: 999, flexShrink: 0, background: c.avatar_color ?? "var(--accent)", color: "#fff", display: "grid", placeItems: "center", fontWeight: 700, fontSize: 13 }}>
                    {c.name.charAt(0).toUpperCase()}
                  </span>
                  <span style={{ whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{c.name}</span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 10, flexShrink: 0 }}>
                  <span style={{ fontWeight: 600, color: net > 0 ? "var(--positive)" : net < 0 ? "var(--negative)" : "var(--text-2)" }}>
                    {net > 0 ? `owes you ${fmt(money(net, base))}` : net < 0 ? `you owe ${fmt(money(-net, base))}` : "settled"}
                  </span>
                  {net !== 0 && (
                    <button className="chip" style={{ fontSize: 12, padding: "3px 10px" }} onClick={() => openSettle({ contactId: c.id, name: c.name, net })}>Settle</button>
                  )}
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
            <p className="muted" style={{ margin: 0, fontSize: 13 }}>
              {target.net >= 0 ? `${target.name} pays you back.` : `You pay ${target.name} back.`}
            </p>
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
