"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { money } from "@pocketcare/money";
import { useBaseCurrency } from "../../../src/hooks";
import { useMoneyFmt } from "../../../src/ui/Money";
import { updateRow } from "../../../src/write";
import { Modal } from "../../../src/ui/Modal";
import { useGroup, useGroupExpenses, useGroupBalances, useGroupMemberIds, useUserProfiles } from "../../../src/splits/hooks";
import { createInvite } from "../../../src/splits/write";

export default function GroupDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params.id;
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const group = useGroup(id);
  const expenses = useGroupExpenses(id);
  const balances = useGroupBalances(id);
  const memberIds = useGroupMemberIds(id);
  const profiles = useUserProfiles();

  const name = (uid: string) => profiles.get(uid)?.name ?? "Someone";
  const total = expenses.reduce((s, e) => s + e.amount, 0);
  const owed = balances.reduce((s, b) => s + Math.max(0, b.net), 0);
  const owe = balances.reduce((s, b) => s + Math.max(0, -b.net), 0);

  const [inviteOpen, setInviteOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [inviteLink, setInviteLink] = useState<string | null>(null);
  const [inviteMsg, setInviteMsg] = useState<string | null>(null);
  const [inviting, setInviting] = useState(false);
  const [copied, setCopied] = useState(false);

  async function invite(withEmail: boolean) {
    setInviting(true); setInviteMsg(null); setInviteLink(null);
    try {
      const r = await createInvite(id, withEmail ? email.trim() : undefined);
      if (r.added) { setInviteMsg(r.already ? `${r.name} is already in this group.` : `Added ${r.name} to the group.`); setEmail(""); }
      else { setInviteLink(r.link ?? null); setCopied(false); }
    } catch (e) { setInviteMsg(`Error: ${(e as Error).message}`); }
    finally { setInviting(false); }
  }

  if (!group) return <div className="fade-up"><p className="muted">Group not found. <Link href="/groups">Back to groups</Link></p></div>;

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12, flexWrap: "wrap" }}>
        <div>
          <Link href="/groups" className="muted" style={{ fontSize: 13 }}>← Groups</Link>
          <h1 style={{ margin: "6px 0 0" }}>{group.name} <span className="muted" style={{ fontSize: 14 }}>· {group.kind}</span></h1>
          {group.start_date && <div className="muted" style={{ fontSize: 13 }}>{group.start_date}{group.end_date ? ` → ${group.end_date}` : ""}</div>}
        </div>
        <button className="btn" onClick={() => { setInviteOpen(true); setInviteLink(null); setInviteMsg(null); }}>+ Invite</button>
      </div>

      <section className="card" style={{ padding: 20, display: "flex", gap: 24, flexWrap: "wrap" }}>
        <div><div className="muted" style={{ fontSize: 13 }}>Total spent</div><div style={{ fontSize: 26, fontWeight: 750 }}>{fmt(money(total, base))}</div></div>
        <div><div className="muted" style={{ fontSize: 13 }}>You’re owed</div><div style={{ fontSize: 20, fontWeight: 700, color: "var(--positive)" }}>{fmt(money(owed, base))}</div></div>
        <div><div className="muted" style={{ fontSize: 13 }}>You owe</div><div style={{ fontSize: 20, fontWeight: 700, color: "var(--negative)" }}>{fmt(money(owe, base))}</div></div>
      </section>

      {group.start_date && group.end_date && (
        <label className="card" style={{ padding: 14, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, cursor: "pointer" }}>
          <span style={{ fontSize: 14 }}><strong>Auto-split</strong><span className="muted"> — expenses within {group.start_date}–{group.end_date} split equally with this {group.kind}.</span></span>
          <input type="checkbox" checked={group.auto_split === 1} onChange={(e) => void updateRow("split_groups", group.id, { auto_split: e.target.checked ? 1 : 0 })} />
        </label>
      )}

      <section style={{ display: "grid", gap: 8 }}>
        <h2 style={{ margin: 0 }}>Members</h2>
        <div className="card" style={{ padding: 8 }}>
          {memberIds.map((uid) => (
            <div key={uid} style={{ display: "flex", justifyContent: "space-between", padding: "10px 14px", borderBottom: "1px solid var(--border)", fontSize: 14 }}>
              <span>{name(uid)}</span>
              <span style={{ color: (balances.find((b) => b.userId === uid)?.net ?? 0) > 0 ? "var(--positive)" : (balances.find((b) => b.userId === uid)?.net ?? 0) < 0 ? "var(--negative)" : "var(--text-2)" }}>
                {(() => { const n = balances.find((b) => b.userId === uid)?.net ?? 0; return n > 0 ? `owes you ${fmt(money(n, base))}` : n < 0 ? `you owe ${fmt(money(-n, base))}` : "settled"; })()}
              </span>
            </div>
          ))}
        </div>
      </section>

      <section style={{ display: "grid", gap: 8 }}>
        <h2 style={{ margin: 0 }}>Expenses</h2>
        {expenses.length === 0 ? (
          <p className="muted" style={{ fontSize: 13 }}>No expenses yet. Add one from <Link href="/transactions/new">Add transaction</Link> and choose this {group.kind}.</p>
        ) : (
          <div className="card" style={{ padding: 8 }}>
            {expenses.map((e) => (
              <div key={e.id} style={{ display: "flex", justifyContent: "space-between", padding: "10px 14px", borderBottom: "1px solid var(--border)", fontSize: 14, gap: 8 }}>
                <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{e.description || "Expense"} <span className="muted" style={{ fontSize: 12 }}>· {new Date(e.occurred_at).toLocaleDateString()}</span></span>
                <span style={{ flexShrink: 0, fontWeight: 600 }}>{fmt(money(e.amount, base))}</span>
              </div>
            ))}
          </div>
        )}
      </section>

      <Modal open={inviteOpen} onClose={() => setInviteOpen(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>Invite to {group.name}</h2>
          <p className="muted" style={{ margin: 0, fontSize: 13 }}>Enter a friend’s email. If they’re on PocketCare they’re added right away; otherwise we’ll give you a link to share.</p>
          <div style={{ display: "flex", gap: 8 }}>
            <input className="input" type="email" inputMode="email" placeholder="friend@email.com" value={email} onChange={(e) => setEmail(e.target.value)} />
            <button className="btn" onClick={() => void invite(true)} disabled={inviting || !email.trim()}>{inviting ? "…" : "Invite"}</button>
          </div>
          <button className="chip" style={{ justifySelf: "start" }} onClick={() => void invite(false)} disabled={inviting}>Or create a shareable link</button>
          {inviteMsg && <div className="card" style={{ padding: 10, fontSize: 13, background: "var(--surface-2)" }}>{inviteMsg}</div>}
          {inviteLink && (
            <div style={{ display: "grid", gap: 6 }}>
              <input className="input" readOnly value={inviteLink} onFocus={(e) => e.currentTarget.select()} />
              <button className="btn" style={{ justifySelf: "end" }} onClick={async () => { try { await navigator.clipboard.writeText(inviteLink); setCopied(true); } catch { /* ignore */ } }}>{copied ? "Copied ✓" : "Copy link"}</button>
            </div>
          )}
        </div>
      </Modal>
    </div>
  );
}
