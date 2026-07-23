"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { useTranslation } from "react-i18next";
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

interface Row { id: string; name: string; type: string; color: string | null; include_in_net_worth: number; is_archived: number; allow_negative: number; }

export default function EditAccountPage() {
  const { t } = useTranslation("accounts");
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { data: rows = [] } = useQuery<Row>("SELECT id, name, type, color, include_in_net_worth, is_archived, IFNULL(allow_negative,0) AS allow_negative FROM accounts WHERE id = ?", [id]);
  const acc = rows[0];

  const balances = useAccountBalances();
  const current = balances.find((b) => b.account.id === id)?.balance;

  const [name, setName] = useState("");
  const [type, setType] = useState<string>(AccountType.Savings);
  const [color, setColor] = useState<string>(COLORS[0]!);
  const [include, setInclude] = useState(true);
  const [allowNeg, setAllowNeg] = useState(false);
  const [ready, setReady] = useState(false);

  const [targetBal, setTargetBal] = useState("");
  const [balMode, setBalMode] = useState<"direct" | "transaction">("direct");
  const [balMsg, setBalMsg] = useState<string | null>(null);

  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (acc && !ready) {
      setName(acc.name); setType(acc.type); setColor(acc.color || COLORS[0]);
      setInclude(acc.include_in_net_worth !== 0); setAllowNeg(acc.allow_negative === 1); setReady(true);
    }
  }, [acc, ready]);

  async function save() {
    await getRepositories().accounts.update(id, { name: name.trim(), type: type as never, color, include_in_net_worth: include, allow_negative: allowNeg });
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
    if (delta === 0) { setBalMsg(t("balAlready")); return; }
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
    setBalMsg(t("balUpdated", { amount: format(target, "en-US") }));
    setTargetBal("");
  }

  if (!acc) return <p className="muted">{t("loading")}</p>;

  return (
    <div style={{ maxWidth: 520, display: "grid", gap: 14 }} className="fade-up">
      <h1>{t("editTitle")}</h1>
      <input className="input" value={name} onChange={(e) => setName(e.target.value)} placeholder={t("accountName")} />

      <span className="muted" style={{ fontSize: 13 }}>{t("typeLabel")}</span>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {TYPES.map((tp) => <button key={tp} className="chip" data-active={tp === type} onClick={() => setType(tp)}>{t(`type.${tp}`, tp.replace("_", " "))}</button>)}
      </div>

      <span className="muted" style={{ fontSize: 13 }}>{t("colour")}</span>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {COLORS.map((c) => (
          <button key={c} onClick={() => setColor(c)} aria-label={c}
            style={{ width: 30, height: 30, borderRadius: 999, background: c, cursor: "pointer", border: c === color ? "3px solid var(--text)" : "2px solid var(--border)" }} />
        ))}
      </div>

      <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 14 }}>
        <input type="checkbox" checked={include} onChange={(e) => setInclude(e.target.checked)} /> {t("includeShort")}
      </label>

      <label style={{ display: "flex", gap: 8, alignItems: "flex-start", fontSize: 14 }}>
        <input type="checkbox" checked={allowNeg} onChange={(e) => setAllowNeg(e.target.checked)} style={{ marginTop: 3 }} />
        <span>{t("allowNeg")}<br />
          <span className="muted" style={{ fontSize: 12 }}>{allowNeg ? t("allowNegOn") : t("allowNegOff")}</span>
        </span>
      </label>

      <div style={{ display: "flex", gap: 10 }}>
        <button className="btn" onClick={save} disabled={!name.trim()}>{t("saveChanges")}</button>
        <button className="btn ghost" onClick={() => router.push("/accounts")}>{t("cancel")}</button>
        <button className="chip" style={{ marginLeft: "auto", color: "var(--negative)", borderColor: "var(--negative)" }} onClick={() => setConfirmDelete(true)}>{t("delete")}</button>
      </div>

      <Modal open={confirmDelete} onClose={() => !deleting && setConfirmDelete(false)}>
        <h2 style={{ marginBottom: 8, color: "var(--negative)" }}>{t("deleteTitle")}</h2>
        <p className="muted" style={{ fontSize: 14, lineHeight: 1.6, marginBottom: 12 }}>
          {t("deleteBody")}
        </p>
        <div style={{ display: "grid", gap: 8 }}>
          <button className="btn" disabled={deleting} onClick={() => deleteAccount(true)}>
            {t("deleteAll")}
          </button>
          <button className="btn ghost" disabled={deleting} onClick={() => deleteAccount(false)}>
            {t("deleteKeep")}
          </button>
        </div>
        <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 16 }}>
          <button className="chip" disabled={deleting} onClick={() => setConfirmDelete(false)}>{t("cancel")}</button>
        </div>
      </Modal>

      <section className="card" style={{ padding: 20, display: "grid", gap: 12, marginTop: 8 }}>
        <h2>{t("balanceHeading")}</h2>
        <div className="muted" style={{ fontSize: 13 }}>{t("currentBalance")} <strong style={{ color: "var(--text)" }}>{current ? format(current, "en-US") : "…"}</strong></div>
        <input className="input" inputMode="decimal" placeholder={t("newBalance")} value={targetBal}
          onChange={(e) => { setTargetBal(e.target.value.replace(/[^0-9.-]/g, "")); setBalMsg(null); }} />
        <div style={{ display: "flex", gap: 8 }}>
          <button className="chip" data-active={balMode === "direct"} onClick={() => setBalMode("direct")}>{t("changeDirectly")}</button>
          <button className="chip" data-active={balMode === "transaction"} onClick={() => setBalMode("transaction")}>{t("recordAsTxn")}</button>
        </div>
        <p className="muted" style={{ fontSize: 12, marginTop: -4 }}>
          {balMode === "direct" ? t("directNote") : t("txnNote")}
        </p>
        <button className="btn ghost" onClick={applyBalance} disabled={!current || targetBal === ""}>{t("updateBalance")}</button>
        {balMsg && <span className="muted" style={{ fontSize: 13 }}>{balMsg}</span>}
      </section>
    </div>
  );
}
