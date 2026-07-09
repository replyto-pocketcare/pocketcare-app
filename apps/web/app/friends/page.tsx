"use client";

import { useState } from "react";
import Link from "next/link";
import { money } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { useMoneyFmt } from "../../src/ui/Money";
import { useFriendBalances, useContacts } from "../../src/splits/hooks";
import { addContact } from "../../src/splits/write";

export default function FriendsPage() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const balances = useFriendBalances();
  const contacts = useContacts();
  const [name, setName] = useState("");

  const netByContact = new Map(balances.map((b) => [b.contactId, b.net] as const));
  const owed = balances.reduce((s, b) => s + Math.max(0, b.net), 0);

  async function add() {
    const n = name.trim();
    if (!n) return;
    await addContact(n);
    setName("");
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1>Friends</h1>

      <section className="card" style={{ padding: 20, display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12, flexWrap: "wrap" }}>
        <div>
          <div className="muted" style={{ fontSize: 13 }}>You’re owed</div>
          <div style={{ fontSize: 30, fontWeight: 750, color: "var(--positive)" }}>{fmt(money(owed, base))}</div>
        </div>
        <div className="muted" style={{ fontSize: 13 }}>{contacts.length} contact{contacts.length === 1 ? "" : "s"}</div>
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
                <span style={{ flexShrink: 0, fontWeight: 600, color: net > 0 ? "var(--positive)" : "var(--text-2)" }}>
                  {net > 0 ? `owes you ${fmt(money(net, base))}` : "settled"}
                </span>
              </div>
            );
          })}
        </div>
      )}

      <p className="muted" style={{ fontSize: 12 }}>Settling up and splitting bills a friend paid for arrive next. For now, split an expense you paid and each friend’s share is tracked here.</p>
    </div>
  );
}
