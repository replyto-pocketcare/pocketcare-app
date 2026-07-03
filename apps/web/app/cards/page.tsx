"use client";

import { useState } from "react";
import Link from "next/link";
import { motion } from "framer-motion";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor } from "@pocketcare/money";
import { billingCycle } from "@pocketcare/budget";
import { useAccountBalances } from "../../src/hooks";
import { useSession } from "../../src/account";
import { getRepositories } from "../../src/powersync";
import { CreditCard } from "../../src/cards/CreditCard";

const PALETTE = ["#3e4a38", "#b06a4f", "#5f6647", "#7c4a3a", "#2b2723"];

interface CardDetail { account_id: string; statement_day: number; due_day: number; credit_limit: number | null; card_last4: string | null; }

export default function CardsPage() {
  const balances = useAccountBalances();
  const session = useSession();
  const holder = (session?.username || "").trim() || "Card Holder";
  const cards = balances.filter((b) => b.account.type === "credit_card");
  const { data: details = [] } = useQuery<CardDetail>("SELECT account_id, statement_day, due_day, credit_limit, card_last4 FROM credit_card_details");
  const detailFor = (id: string) => details.find((d) => d.account_id === id);

  if (cards.length === 0) {
    return (
      <div className="fade-up">
        <h1>Cards</h1>
        <p className="muted">Add a Credit Card account to see your wallet come to life.</p>
        <a href="/accounts/new" className="btn" style={{ marginTop: 12 }}>＋ New account</a>
      </div>
    );
  }

  return (
    <div className="fade-up" style={{ display: "grid", gap: 8 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h1>Cards</h1>
        <Link href="/accounts/new" className="btn">＋ Add card</Link>
      </div>
      <p className="muted" style={{ marginBottom: 8 }}>Your cards, straight from the wallet.</p>

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
        <div style={{ position: "absolute", left: 22, top: 58, color: "#e8d4a8", fontSize: 13, fontWeight: 600, letterSpacing: "0.05em" }}>WALLET</div>
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
              <CreditCard name={holder} color={b.account.color || PALETTE[i % PALETTE.length]} currency={b.account.currency} last4={last4} network={b.account.name} />
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
  const cycle = detail ? billingCycle(detail.statement_day, detail.due_day, new Date()) : null;
  const [stmt, setStmt] = useState(String(detail?.statement_day ?? 1));
  const [due, setDue] = useState(String(detail?.due_day ?? 20));
  const [creditLimit, setCreditLimit] = useState(detail?.credit_limit ? String(toMajor(money(detail.credit_limit, account.currency))) : "");
  const [last4, setLast4] = useState(detail?.card_last4 ?? "");
  const [editing, setEditing] = useState(false);
  const [fromId, setFromId] = useState<string | null>(null);
  const [amount, setAmount] = useState("");
  const owedMoney = money(Math.abs(owed), account.currency);

  async function saveCycle() {
    await getRepositories().creditCards.upsertDetails({
      account_id: account.id, statement_day: Number(stmt) || 1, due_day: Number(due) || 20,
      credit_limit: creditLimit ? fromMajor(Number(creditLimit), account.currency).amount : (detail?.credit_limit ?? null),
      card_last4: last4 ? last4.slice(-4) : null,
    });
    setEditing(false);
  }
  async function settle() {
    const from = fromId ?? sources[0]?.id;
    if (!from || !amount) return;
    await getRepositories().creditCards.settle({ fromAccountId: from, cardAccountId: account.id, amount: fromMajor(Number(amount), account.currency), occurredAt: new Date().toISOString() });
    setAmount("");
  }

  return (
    <div className="card" style={{ padding: 20, display: "grid", gap: 12 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
        <div>
          <div className="muted" style={{ fontSize: 12 }}>Spent this cycle</div>
          <div style={{ fontSize: 28, fontWeight: 750, color: "var(--negative)" }}>{format(owedMoney, "en-US")}</div>
          {detail?.credit_limit ? (
            <div className="muted" style={{ fontSize: 12, marginTop: 2 }}>
              of {format(money(detail.credit_limit, account.currency), "en-US")} limit ·{" "}
              <span style={{ color: "var(--positive)" }}>{format(money(Math.max(0, detail.credit_limit - Math.abs(owed)), account.currency), "en-US")} available</span>
            </div>
          ) : null}
        </div>
        {cycle && !editing && (
          <div style={{ textAlign: "right" }}>
            <div className="muted" style={{ fontSize: 12 }}>Payment due</div>
            <div style={{ fontWeight: 650 }}>{cycle.dueDate.toLocaleDateString()}</div>
            <div className="muted" style={{ fontSize: 11 }}>Statement {cycle.statementDate.toLocaleDateString()}</div>
            <button className="chip" style={{ padding: "2px 8px", fontSize: 11, marginTop: 4 }} onClick={() => setEditing(true)}>Edit card</button>
          </div>
        )}
      </div>

      {(!cycle || editing) && (
        <div style={{ display: "grid", gap: 8 }}>
          <div style={{ display: "flex", gap: 8, alignItems: "flex-end", flexWrap: "wrap" }}>
            <label className="muted" style={{ fontSize: 12 }}>Statement day
              <input className="input" style={{ width: 90 }} value={stmt} onChange={(e) => setStmt(e.target.value.replace(/\D/g, ""))} />
            </label>
            <label className="muted" style={{ fontSize: 12 }}>Due day
              <input className="input" style={{ width: 80 }} value={due} onChange={(e) => setDue(e.target.value.replace(/\D/g, ""))} />
            </label>
            <label className="muted" style={{ fontSize: 12 }}>Credit limit
              <input className="input" style={{ width: 120 }} inputMode="decimal" value={creditLimit} onChange={(e) => setCreditLimit(e.target.value.replace(/[^0-9.]/g, ""))} />
            </label>
          </div>
          <label className="muted" style={{ fontSize: 12 }}>Card number (optional — last 4 shown)
            <input className="input" inputMode="numeric" placeholder="•••• (optional)" value={last4}
              onChange={(e) => setLast4(e.target.value.replace(/\D/g, "").slice(0, 4))} />
          </label>
          <div style={{ display: "flex", gap: 8 }}>
            <button className="btn ghost" onClick={saveCycle}>Save</button>
            {editing && <button className="chip" onClick={() => setEditing(false)}>Cancel</button>}
          </div>
        </div>
      )}

      <div style={{ display: "grid", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 12 }}>
        <span className="muted" style={{ fontSize: 12 }}>Settle bill from</span>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {sources.map((s) => <button key={s.id} className="chip" data-active={(fromId ?? sources[0]?.id) === s.id} onClick={() => setFromId(s.id)}>{s.name}</button>)}
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <input className="input" inputMode="decimal" placeholder="Amount" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
          <button className="btn" onClick={settle} disabled={!amount || sources.length === 0}>Settle</button>
        </div>
      </div>
    </div>
  );
}
