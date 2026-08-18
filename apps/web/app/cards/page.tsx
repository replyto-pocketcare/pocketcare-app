"use client";

import { useTranslation } from "react-i18next";
import { useRegisterAddAction } from "../../src/ui/AddAction";
import { PlusIcon } from "../../src/ui/icons";
import { useState } from "react";
import Link from "next/link";
import { motion } from "framer-motion";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor } from "@sanvya/money";
import { billingCycle } from "@sanvya/budget";
import { useAccountBalances, useAccountsLoading } from "../../src/hooks";
import { Skeleton, CardsSkeleton } from "../../src/ui/Skeleton";
import { useSession } from "../../src/account";
import { getRepositories, getDb } from "../../src/powersync";
import { CreditCard } from "../../src/cards/CreditCard";
import { useMoneyFmt } from "../../src/ui/Money";
import { AmountInput } from "../../src/ui/AmountInput";
import { findCoveredEmis, markEmisPaid, type CoveredEmi } from "../../src/loans/settleEmis";
import { Modal } from "../../src/ui/Modal";

const PALETTE = ["#3e4a38", "#b06a4f", "#5f6647", "#7c4a3a", "#2b2723"];

interface CardDetail { account_id: string; statement_day: number; due_day: number; credit_limit: number | null; card_last4: string | null; pending_due: number | null; due_on: string | null; }

export default function CardsPage() {
  const { t } = useTranslation("cards");
  const balances = useAccountBalances();
  const session = useSession();
  const holder = (session?.username || "").trim() || t("cardHolder");
  const cards = balances.filter((b) => b.account.type === "credit_card");
  const accountsLoading = useAccountsLoading();
  const { data: details = [] } = useQuery<CardDetail>("SELECT account_id, statement_day, due_day, credit_limit, card_last4, pending_due, due_on FROM credit_card_details");
  const detailFor = (id: string) => details.find((d) => d.account_id === id);

  useRegisterAddAction({ type: "link", href: "/accounts/new", label: t("addCard") }, [t]);

  if (cards.length === 0 && accountsLoading) {
    return (
      <div style={{ display: "grid", gap: 16 }}>
        <h1>{t("title")}</h1>
        <Skeleton h={92} r={18} />
        <CardsSkeleton count={2} minWidth={300} />
      </div>
    );
  }

  if (cards.length === 0) {
    return (
      <div className="fade-up">
        <h1>{t("title")}</h1>
        <p className="muted">{t("emptyBody")}</p>
        <a href="/accounts/new" className="btn" style={{ marginTop: 12 }}>＋ {t("newAccount")}</a>
      </div>
    );
  }

  return (
    <div className="fade-up" style={{ display: "grid", gap: 8 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h1>{t("title")}</h1>
        <Link href="/accounts/new" className="btn">＋ {t("addCard")}</Link>
      </div>
      <p className="muted" style={{ marginBottom: 8 }}>{t("subtitle")}</p>

      {/* Wallet */}
      <div style={{ position: "relative", height: 92, marginBottom: 4 }}>
        <div style={{
          position: "absolute", left: 0, right: 0, top: 20, height: 70, borderRadius: "18px 18px 22px 22px",
          background: "linear-gradient(135deg,#6b4f3d,#5f4636)", boxShadow: "0 16px 30px -18px rgba(43,39,35,0.6)",
        }} />
        <div style={{
          position: "absolute", left: 0, right: 0, top: 46, height: 46, borderRadius: "0 0 22px 22px",
          background: "linear-gradient(135deg,#7a5a44,#684d3a)", borderTop: "2px solid rgba(0,0,0,0.15)",
        }} />
        <div style={{ position: "absolute", left: 22, top: 58, color: "#e8d4a8", fontSize: 13, fontWeight: 600, letterSpacing: "0.05em" }}>{t("wallet")}</div>
      </div>

      {/* Cards spread as a list */}
      <motion.div
        initial="hidden"
        animate="visible"
        variants={{ visible: { transition: { staggerChildren: 0.12, delayChildren: 0.1 } } }}
        style={{ display: "grid", gap: 18 }}
      >
        {cards.map((b, i) => {
          const last4 = detailFor(b.account.id)?.card_last4 || "";
          return (
            <motion.div
              key={b.account.id}
              variants={{
                hidden: { opacity: 0, y: -48, scale: 0.92 },
                visible: { opacity: 1, y: 0, scale: 1, transition: { type: "spring", stiffness: 90, damping: 15 } },
              }}
              style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(300px, 100%), 1fr))", gap: 20, alignItems: "center" }}
            >
              <CreditCard name={holder} color={b.account.color || PALETTE[i % PALETTE.length]!} currency={b.account.currency} last4={last4} network={b.account.name} />
              <CardPanel
                account={b.account}
                owed={b.balance.amount}
                detail={detailFor(b.account.id)}
                sources={balances.filter((x) => x.account.id !== b.account.id && x.account.type !== "credit_card").map((x) => ({ id: x.account.id, name: x.account.name }))}
              />
            </motion.div>
          );
        })}
      </motion.div>
    </div>
  );
}

function CardPanel({ account, owed, detail, sources }: {
  account: { id: string; currency: string };
  owed: number;
  detail: CardDetail | undefined;
  sources: { id: string; name: string }[];
}) {
  const { t } = useTranslation("cards");
  const fmt = useMoneyFmt();
  const cycle = detail ? billingCycle(detail.statement_day, detail.due_day, new Date()) : null;

  /**
   * Spend posted to this card SINCE the last statement closed — an EMI charged
   * to the card, a purchase, anything.
   *
   * Deliberately separate from `pending_due`, which is the statement amount the
   * user types in. On a real card a spend made today lands on the NEXT
   * statement; folding it into "due this cycle" would overstate what's actually
   * payable by the due date. Shown as its own line so a charge is visible
   * immediately without misstating the bill.
   */
  const { data: cycleRows = [] } = useQuery<{ total: number }>(
    `SELECT COALESCE(SUM(amount), 0) AS total FROM transactions
      WHERE account_id = ? AND deleted_at IS NULL AND type = 'expense' AND occurred_at >= ?`,
    [account.id, cycle ? cycle.cycleStart.toISOString() : new Date().toISOString()],
  );
  const newSpend = cycleRows[0]?.total ?? 0;

  // Charges that make up the outstanding balance — newest first.
  const { data: cardTxns = [] } = useQuery<{ id: string; description: string | null; amount: number; occurred_at: string }>(
    `SELECT id, description, amount, occurred_at FROM transactions
      WHERE account_id = ? AND deleted_at IS NULL AND type = 'expense' ORDER BY occurred_at DESC LIMIT 200`,
    [account.id],
  );
  const chargesTotal = cardTxns.reduce((s, x) => s + x.amount, 0);
  const [showTxns, setShowTxns] = useState(false);

  const [stmt, setStmt] = useState(String(detail?.statement_day ?? 1));
  const [due, setDue] = useState(String(detail?.due_day ?? 20));
  const [creditLimit, setCreditLimit] = useState(detail?.credit_limit ? String(toMajor(money(detail.credit_limit, account.currency))) : "");
  const [dueAmt, setDueAmt] = useState(detail?.pending_due != null ? String(toMajor(money(detail.pending_due, account.currency))) : "");
  const [last4, setLast4] = useState(detail?.card_last4 ?? "");
  const [editing, setEditing] = useState(false);
  const [fromId, setFromId] = useState<string | null>(null);
  const [amount, setAmount] = useState("");
  const owedMoney = money(Math.abs(owed), account.currency);

  async function saveCycle() {
    const sDay = Math.min(28, Math.max(1, Number(stmt) || 1));
    const dDay = Math.min(28, Math.max(1, Number(due) || 20));
    await getRepositories().creditCards.upsertDetails({
      account_id: account.id, statement_day: sDay, due_day: dDay,
      credit_limit: creditLimit ? fromMajor(Number(creditLimit), account.currency).amount : (detail?.credit_limit ?? null),
      card_last4: last4 ? last4.slice(-4) : null,
    });
    // pending_due / due_on aren't in the repo type — persist directly. Recompute
    // due_on from the (possibly new) cycle so "pay by" stays correct.
    const c = billingCycle(sDay, dDay, new Date());
    await getDb()?.execute(
      "UPDATE credit_card_details SET pending_due = ?, due_on = ?, updated_at = ? WHERE account_id = ?",
      [dueAmt ? fromMajor(Number(dueAmt), account.currency).amount : null, c.dueDate.toISOString().slice(0, 10), new Date().toISOString(), account.id],
    );
    setEditing(false);
  }
  /**
   * Settle the bill, then ASK whether the EMIs it covers should be marked paid.
   *
   * Deliberately a question, not an action: this infers loan state from a
   * payment amount, and a partial payment would otherwise silently clear an
   * instalment the user hasn't actually cleared.
   */
  const [coveredEmis, setCoveredEmis] = useState<CoveredEmi[]>([]);
  const [settledAt, setSettledAt] = useState<string>("");

  async function settle() {
    const from = fromId ?? sources[0]?.id;
    if (!from || !amount) return;
    const when = new Date().toISOString();
    const minor = fromMajor(Number(amount), account.currency).amount;
    await getRepositories().creditCards.settle({ fromAccountId: from, cardAccountId: account.id, amount: fromMajor(Number(amount), account.currency), occurredAt: when });
    setAmount("");
    const covered = await findCoveredEmis(account.id, minor);
    if (covered.length > 0) { setSettledAt(when); setCoveredEmis(covered); }
  }

  return (
    <details className="card" style={{ padding: 20 }}>
      <summary style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", cursor: "pointer", userSelect: "none", outline: "none" }}>
        <div>
          <div className="muted" style={{ fontSize: 12 }}>{t("spentThisCycle")}</div>
          <div style={{ fontSize: 28, fontWeight: 750, color: "var(--negative)" }}>{fmt(owedMoney)}</div>
          {detail?.credit_limit ? (
            <div className="muted" style={{ fontSize: 12, marginTop: 2 }}>
              {t("ofLimit", { limit: fmt(money(detail.credit_limit, account.currency)) })}
            </div>
          ) : null}
        </div>
        {cycle && !editing && (() => {
          const dueOn = detail?.due_on ? new Date(detail.due_on) : cycle.dueDate;
          const rolledToNext = detail?.pending_due != null && dueOn.getTime() > cycle.dueDate.getTime();
          const dueThisCycle = detail?.pending_due != null ? (rolledToNext ? 0 : detail.pending_due) : null;
          return (
            <div style={{ textAlign: "right" }}>
              {dueThisCycle != null && (
                <>
                  <div className="muted" style={{ fontSize: 12 }}>{t("dueThisCycle")}</div>
                  <div style={{ fontWeight: 750, fontSize: 20, color: dueThisCycle > 0 ? "var(--negative)" : "var(--positive)" }}>{fmt(money(dueThisCycle, account.currency))}</div>
                </>
              )}
              <div className="muted" style={{ fontSize: 12, marginTop: dueThisCycle != null ? 4 : 0 }}>{t("payBy")}</div>
              <div style={{ fontWeight: 650 }}>{dueOn.toLocaleDateString()}</div>
              {rolledToNext && detail?.pending_due ? (
                <div className="muted" style={{ fontSize: 11, marginTop: 2 }}>{t("dueNextCycle", { amount: fmt(money(detail.pending_due, account.currency)) })}</div>
              ) : null}
              {newSpend > 0 && (
                <div className="muted" style={{ fontSize: 11, marginTop: 2 }}>
                  {t("newSpendThisCycle", { amount: fmt(money(newSpend, account.currency)), defaultValue: "+{{amount}} new spend since the last statement" })}
                </div>
              )}
              <div className="muted" style={{ fontSize: 11, marginTop: 4 }}>{t("clickToManage")}</div>
            </div>
          );
        })()}
      </summary>

      <div style={{ display: "grid", gap: 12, marginTop: 16 }}>
        {detail?.credit_limit ? (
          <div className="muted" style={{ fontSize: 12 }}>
            <span style={{ color: "var(--positive)" }}>{t("availableCredit", { amount: fmt(money(Math.max(0, detail.credit_limit - Math.abs(owed)), account.currency)) })}</span>
          </div>
        ) : null}
        {cycle && !editing && (
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
            <div className="muted" style={{ fontSize: 11 }}>{t("statement", { date: cycle.statementDate.toLocaleDateString() })}</div>
            <div style={{ display: "flex", gap: 6 }}>
              {cardTxns.length > 0 && (
                <button className="chip" style={{ padding: "2px 8px", fontSize: 11 }} onClick={(e) => { e.preventDefault(); setShowTxns(true); }}>
                  {t("viewTransactions", { count: cardTxns.length, defaultValue: "View transactions" })}
                </button>
              )}
              <button className="chip" style={{ padding: "2px 8px", fontSize: 11 }} onClick={() => setEditing(true)}>{t("editDetails")}</button>
            </div>
          </div>
        )}

        {(!cycle || editing) && (
          <div style={{ display: "grid", gap: 8, marginTop: cycle ? 8 : 0 }}>
            <div style={{ display: "flex", gap: 8, alignItems: "flex-end", flexWrap: "wrap" }}>
              <label className="muted" style={{ fontSize: 12 }}>{t("statementDay")}
                <input className="input" style={{ width: 90 }} value={stmt} onChange={(e) => setStmt(e.target.value.replace(/\D/g, ""))} />
              </label>
              <label className="muted" style={{ fontSize: 12 }}>{t("dueDay")}
                <input className="input" style={{ width: 80 }} value={due} onChange={(e) => setDue(e.target.value.replace(/\D/g, ""))} />
              </label>
              <label className="muted" style={{ fontSize: 12 }}>{t("creditLimit")}
                <AmountInput style={{ width: 120 }} currency={account.currency} value={creditLimit} onChange={setCreditLimit} ariaLabel={t("creditLimit")} />
              </label>
              <label className="muted" style={{ fontSize: 12 }}>{t("amountDue")}
                <AmountInput style={{ width: 120 }} currency={account.currency} value={dueAmt} onChange={setDueAmt} ariaLabel={t("amountDue")} />
              </label>
            </div>
            <label className="muted" style={{ fontSize: 12 }}>{t("cardNumber")}
              <input className="input" inputMode="numeric" placeholder={t("cardNumberPlaceholder")} value={last4}
                onChange={(e) => setLast4(e.target.value.replace(/\D/g, "").slice(0, 4))} />
            </label>
            <div style={{ display: "flex", gap: 8 }}>
              <button className="btn ghost" onClick={saveCycle}>{t("save")}</button>
              {editing && <button className="chip" onClick={() => setEditing(false)}>{t("cancel")}</button>}
            </div>
          </div>
        )}

        <div style={{ display: "grid", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 12 }}>
          <span className="muted" style={{ fontSize: 12 }}>{t("settleFrom")}</span>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            {sources.map((s) => <button key={s.id} className="chip" data-active={(fromId ?? sources[0]?.id) === s.id} onClick={() => setFromId(s.id)}>{s.name}</button>)}
          </div>
          <div style={{ display: "flex", gap: 8 }}>
            <AmountInput placeholder={t("amountPlaceholder")} currency={account.currency} value={amount} onChange={setAmount} ariaLabel={t("settle")} />
            <button className="btn" onClick={settle} disabled={!amount || sources.length === 0}>{t("settle")}</button>
          </div>
        </div>
      </div>

      {/* Charges that add up to the amount due — newest first. */}
      <Modal open={showTxns} onClose={() => setShowTxns(false)} label={t("cardTxnsTitle", "Card transactions")}>
        <div style={{ display: "grid", gap: 12 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8 }}>
            <h2 style={{ margin: 0 }}>{t("cardTxnsTitle", "Card transactions")}</h2>
            <span className="muted" style={{ fontSize: 13 }}>{t("cardTxnsTotal", { amount: fmt(money(chargesTotal, account.currency)), defaultValue: "Total {{amount}}" })}</span>
          </div>
          <div className="card" style={{ padding: 0, overflow: "hidden", maxHeight: "60vh", overflowY: "auto" }}>
            {cardTxns.map((tx, i) => (
              <div key={tx.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "10px 14px", borderTop: i === 0 ? "none" : "1px solid var(--border)", minWidth: 0 }}>
                <div style={{ minWidth: 0, flex: 1 }}>
                  <div style={{ fontSize: 14, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{tx.description || t("uncategorised", "Transaction")}</div>
                  <div className="muted" style={{ fontSize: 11.5 }}>{new Date(tx.occurred_at).toLocaleDateString()}</div>
                </div>
                <strong style={{ flexShrink: 0, whiteSpace: "nowrap" }}>{fmt(money(tx.amount, account.currency))}</strong>
              </div>
            ))}
            {cardTxns.length === 0 && <p className="muted" style={{ padding: 14, margin: 0 }}>{t("noCardTxns", "No charges on this card yet.")}</p>}
          </div>
        </div>
      </Modal>

      {/* EMIs charged to this card that the payment just covered. Asked, never
          assumed — see src/loans/settleEmis.ts. */}
      <Modal open={coveredEmis.length > 0} onClose={() => setCoveredEmis([])} label={t("emiCoveredTitle", "Mark EMIs paid?")}>
        <div style={{ display: "grid", gap: 14 }}>
          <h2 style={{ margin: 0 }}>{t("emiCoveredTitle", "Mark EMIs paid?")}</h2>
          <p className="muted" style={{ margin: 0, fontSize: 13.5 }}>
            {t("emiCoveredBody", { count: coveredEmis.length, defaultValue: "This payment covers {{count}} instalment(s) charged to this card. Mark them paid?" })}
          </p>
          <div className="row-stack">
            {coveredEmis.map((c) => (
              <div key={`${c.loanId}:${c.emiNo}`} className="row-tile" style={{ display: "flex", justifyContent: "space-between", gap: 10 }}>
                <span style={{ minWidth: 0 }}>
                  <strong style={{ fontSize: 14 }}>{t("emiNo", { n: c.emiNo, defaultValue: "EMI #{{n}}" })}</strong>
                  {c.lender ? <span className="muted" style={{ fontSize: 12 }}> · {c.lender}</span> : null}
                  <div className="muted" style={{ fontSize: 11.5 }}>{new Date(c.dueDate + "T00:00:00").toLocaleDateString()}</div>
                </span>
                <span style={{ fontWeight: 700, whiteSpace: "nowrap" }}>{fmt(money(c.amount, account.currency))}</span>
              </div>
            ))}
          </div>
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
            <button className="btn ghost" onClick={() => setCoveredEmis([])}>{t("emiCoveredSkip", "Not now")}</button>
            <button className="btn" onClick={async () => { await markEmisPaid(coveredEmis, settledAt); setCoveredEmis([]); }}>
              {t("emiCoveredConfirm", "Mark paid")}
            </button>
          </div>
        </div>
      </Modal>
    </details>
  );
}
