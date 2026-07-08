"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { useQuery } from "@powersync/react";
import { AccountType } from "@pocketcare/types";
import { money, format, fromMajor } from "@pocketcare/money";
import { getRepositories, getDb } from "../../../../src/powersync";
import { useAccountBalances } from "../../../../src/hooks";
import { Modal } from "../../../../src/ui/Modal";
import { softDelete, nowIso } from "../../../../src/write";

import { ACCOUNT_COLORS } from "../../../../src/colors";

const TYPES = Object.values(AccountType);
const COLORS = ACCOUNT_COLORS;

interface Row { id: string; name: string; type: string; color: string | null; include_in_net_worth: number; is_archived: number; }

export default function EditAccountPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { data: rows = [] } = useQuery<Row>("SELECT id, name, type, color, include_in_net_worth, is_archived FROM accounts WHERE id = ?", [id]);
  const acc = rows[0];

  const balances = useAccountBalances();
  const current = balances.find((b) => b.account.id === id)?.balance;

  const [name, setName] = useState("");
  const [type, setType] = useState<string>(AccountType.Savings);
  const [color, setColor] = useState(COLORS[0]);
  const [include, setInclude] = useState(true);
  const [ready, setReady] = useState(false);

  const [targetBal, setTargetBal] = useState("");
  const [balMode, setBalMode] = useState<"direct" | "transaction">("direct");
  const [balMsg, setBalMsg] = useState<string | null>(null);

  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (acc && !ready) {
      setName(acc.name); setType(acc.type); setColor(acc.color || COLORS[0]);
      setInclude(acc.include_in_net_worth !== 0); setReady(true);
    }
  }, [acc, ready]);

  async function save() {
    await getRepositories().accounts.update(id, { name: name.trim(), type: type as never, color, include_in_net_worth: include });
    router.push("/accounts");
  }
  
  async function archive() {
    await getRepositories().accounts.update(id, { is_archived: true });
    router.push("/accounts");
  }

  async function deleteAccount(cascade: boolean) {
    setDeleting(true);
    try {
      const db = getDb();
      if (db && cascade) {
        // Cascade delete transactions first
        await db.execute(`UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE account_id = ? AND deleted_at IS NULL`, [nowIso(), nowIso(), id]);
      }
      // Soft-delete the account itself
      await softDelete("accounts", id);
      router.push("/accounts");
    } finally {
      setDeleting(false);
    }
  }

  async function applyBalance() {
    if (!acc || !current || targetBal === "") return;
    const target = fromMajor(Number(targetBal), current.currency);
    const delta = target.amount - current.amount;
    if (delta === 0) { setBalMsg("Balance is already that amount."); return; }
    const repos = getRepositories();
    if (balMode === "direct") {
      // Silent correction: append an adjustment ledger entry (no category).
      await repos.transactions.create({
        account_id: id,
        type: "adjustment",
        amount: money(delta, current.currency),
        note: "Balance adjustment",
        occurred_at: new Date().toISOString(),
      });
    } else {
      // Record as a real income/expense so it appears in history & insights.
      await repos.transactions.create({
        account_id: id,
        type: delta > 0 ? "income" : "expense",
        amount: money(Math.abs(delta), current.currency),
        note: "Balance adjustment",
        occurred_at: new Date().toISOString(),
      });
    }
    setBalMsg(`Balance updated to ${format(target, "en-US")}.`);
    setTargetBal("");
  }

  if (!acc) return <p className="muted">Loading…</p>;

  return (
    <div style={{ maxWidth: 520, display: "grid", gap: 14 }} className="fade-up">
      <h1>Edit account</h1>
      <input className="input" value={name} onChange={(e) => setName(e.target.value)} placeholder="Account name" />

      <span className="muted" style={{ fontSize: 13 }}>Type</span>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {TYPES.map((tp) => <button key={tp} className="chip" data-active={tp === type} style={{ textTransform: "capitalize" }} onClick={() => setType(tp)}>{tp.replace("_", " ")}</button>)}
      </div>

      <span className="muted" style={{ fontSize: 13 }}>Colour</span>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {COLORS.map((c) => (
          <button key={c} onClick={() => setColor(c)} aria-label={c}
            style={{ width: 30, height: 30, borderRadius: 999, background: c, cursor: "pointer", border: c === color ? "3px solid var(--text)" : "2px solid var(--border)" }} />
        ))}
      </div>

      <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 14 }}>
        <input type="checkbox" checked={include} onChange={(e) => setInclude(e.target.checked)} /> Include in net worth
      </label>

      <div style={{ display: "flex", gap: 10 }}>
        <button className="btn" onClick={save} disabled={!name.trim()}>Save changes</button>
        <button className="btn ghost" onClick={() => router.push("/accounts")}>Cancel</button>
        <button className="chip" style={{ marginLeft: "auto", color: "var(--negative)", borderColor: "var(--negative)" }} onClick={() => setConfirmDelete(true)}>Delete</button>
      </div>

      <Modal open={confirmDelete} onClose={() => !deleting && setConfirmDelete(false)}>
        <h2 style={{ marginBottom: 8, color: "var(--negative)" }}>Delete account?</h2>
        <p className="muted" style={{ fontSize: 14, lineHeight: 1.6, marginBottom: 12 }}>
          You can delete this account and all its transactions, or keep the transactions (they will remain in your history but the account will be hidden).
        </p>
        <div style={{ display: "grid", gap: 8 }}>
          <button className="btn" disabled={deleting} onClick={() => deleteAccount(true)}>
            Delete account & all transactions
          </button>
          <button className="btn ghost" disabled={deleting} onClick={() => deleteAccount(false)}>
            Delete account but keep transactions
          </button>
        </div>
        <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 16 }}>
          <button className="chip" disabled={deleting} onClick={() => setConfirmDelete(false)}>Cancel</button>
        </div>
      </Modal>

      <section className="card" style={{ padding: 20, display: "grid", gap: 12, marginTop: 8 }}>
        <h2>Balance</h2>
        <div className="muted" style={{ fontSize: 13 }}>Current balance: <strong style={{ color: "var(--text)" }}>{current ? format(current, "en-US") : "…"}</strong></div>
        <input className="input" inputMode="decimal" placeholder="New balance" value={targetBal}
          onChange={(e) => { setTargetBal(e.target.value.replace(/[^0-9.-]/g, "")); setBalMsg(null); }} />
        <div style={{ display: "flex", gap: 8 }}>
          <button className="chip" data-active={balMode === "direct"} onClick={() => setBalMode("direct")}>Change directly</button>
          <button className="chip" data-active={balMode === "transaction"} onClick={() => setBalMode("transaction")}>Record as a transaction</button>
        </div>
        <p className="muted" style={{ fontSize: 12, marginTop: -4 }}>
          {balMode === "direct"
            ? "Adds a silent adjustment so the balance matches — not shown as income/expense."
            : "Adds an income or expense for the difference, so it appears in history & insights."}
        </p>
        <button className="btn ghost" onClick={applyBalance} disabled={!current || targetBal === ""}>Update balance</button>
        {balMsg && <span className="muted" style={{ fontSize: 13 }}>{balMsg}</span>}
      </section>
    </div>
  );
}
