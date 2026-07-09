"use client";

import { useMemo, useState } from "react";
import Link from "next/link";

interface QA { q: string; a: string }
interface Section { icon: string; color: string; title: string; items: QA[] }

const SECTIONS: Section[] = [
  {
    icon: "◧", color: "#b06a4f", title: "Getting started",
    items: [
      { q: "What is PocketCare?", a: "An offline-first personal expense & wealth manager. Your data lives on your device and syncs securely — you can use most of the app with no connection." },
      { q: "How do I begin?", a: "Add your first account (bank, cash, card, or investments) from the Dashboard or Accounts page. Then start logging transactions. Set your base currency in Settings." },
      { q: "Can I install it like an app?", a: "Yes — on mobile or desktop use your browser's “Install app” / “Add to Home Screen” option (or the Install button in the sidebar) for a full-screen, offline experience." },
      { q: "Does it work offline?", a: "Yes. You can add and edit accounts, transactions, budgets, goals and splits offline; everything syncs the next time you're online." },
    ],
  },
  {
    icon: "⇅", color: "#5f7a52", title: "Transactions",
    items: [
      { q: "How do I add a transaction?", a: "Tap Add transaction, choose Expense / Income / Transfer, enter the amount, pick an account and (optionally) a category, labels and a note." },
      { q: "Can one transaction have multiple items?", a: "Yes — on an expense, use “Add item / split” to break a bill into named items; the total is their sum." },
      { q: "Can I back-date a transaction?", a: "Yes, set the Date field when adding it. Balances recompute from your ledger automatically." },
      { q: "Can I import or export my data?", a: "Settings → Import & export. Export all transactions to CSV, or import from a CSV (including a Wallet-by-BudgetBakers importer). New accounts and categories are created automatically." },
    ],
  },
  {
    icon: "◔", color: "#c08a3e", title: "Budgets",
    items: [
      { q: "How do budgets work?", a: "Create a spending cap for a period (weekly/monthly/etc.) or for custom dates. Scope it to specific categories or labels, or leave it open for all spending." },
      { q: "Will it warn me before I overspend?", a: "Budgets flag at ~80% used and when you go over — and you'll see it surfaced in the Insights feed too." },
    ],
  },
  {
    icon: "◎", color: "#3e4a38", title: "Goals & emergency fund",
    items: [
      { q: "How do savings goals work?", a: "Create a goal with a target (e.g. a trip or a phone), then “Add funds” to reserve money from a savings account toward it. The reserved amount is blocked from your available balance." },
      { q: "What's the emergency fund for?", a: "Mark one goal as your emergency fund — it's kept liquid and filled first, and your other goals unlock once it's funded." },
    ],
  },
  {
    icon: "↻", color: "#7c4a3a", title: "Subscriptions",
    items: [
      { q: "How do I track subscriptions?", a: "Subscriptions page → Add subscription. See your total monthly and yearly load at a glance." },
      { q: "What is “Before you subscribe…”?", a: "A simulator (Premium) that shows a new subscription's true long-term cost versus investing that money instead — before you commit." },
    ],
  },
  {
    icon: "◑", color: "#b06a4f", title: "Splits & friends",
    items: [
      { q: "How do I split a bill?", a: "Open Add transaction → turn on “Split this expense” → pick a group/trip → choose who's in and how to split (equally, exact amounts, or percentages) → mark who paid. Only your own share counts in your budget; the rest is tracked as owed or lent." },
      { q: "How do I add friends?", a: "Everyone in a split must be in a shared group. Go to Groups & trips → open a group → Invite by email (they're added instantly if they're on PocketCare) or share an invite link. They join, then you can split with them." },
      { q: "Where do I see who owes whom?", a: "The Friends page shows your net balance with each person — who owes you and who you owe — across all groups, plus a per-group view inside each group." },
      { q: "How do I settle up?", a: "On Friends, tap Settle next to a person. Record the repayment into an account, or choose “None” to just mark it settled without moving money." },
      { q: "Can a trip split automatically?", a: "Yes — give a trip a date range and turn on auto-split. Any expense you add within those dates is split equally with the group (you can turn it off per transaction)." },
      { q: "Is my private data shared with friends?", a: "No. Friends only see the shared fact — the amount, who paid, and each person's share. Your accounts, payment method and categories are never shared." },
    ],
  },
  {
    icon: "▤", color: "#5f6647", title: "Cards & accounts",
    items: [
      { q: "Can I track credit cards?", a: "Yes — add a Credit Card account and its details on the Cards page. Balances and spending are tracked like any other account." },
      { q: "What about investments?", a: "Stocks and mutual-fund accounts are supported; money moves in and out via transfers, and holdings are tracked separately." },
      { q: "How is net worth calculated?", a: "It's the sum of your accounts' ledger-derived balances. You can toggle any account in or out of net worth from the Dashboard." },
    ],
  },
  {
    icon: "◱", color: "#4f46e5", title: "Insights & statements",
    items: [
      { q: "What is the Insights feed?", a: "A swipeable, TikTok-style stack of bite-sized cards — weekly recaps, budget alerts, spending patterns, savings wins and more, drawn from your own data. It's a Premium feature." },
      { q: "How do statements work?", a: "Statements (Premium) generates a clean summary for any date range that you can print or save as a PDF." },
    ],
  },
  {
    icon: "✦", color: "#b06a4f", title: "Ask PocketCare (AI)",
    items: [
      { q: "What can the assistant do?", a: "It helps you use the app and think through your own money — and can create goals, budgets, subscriptions and groups, reserve money to a goal, and log a transaction (always asking you to confirm first)." },
      { q: "What data does it see?", a: "Only an aggregated on-device snapshot (balances, average income/expense, goals, upcoming bills, split totals) — never your individual transactions. It won't write or explain code or give tax/legal/investment advice." },
      { q: "What are AI credits?", a: "Each plan includes a monthly prompt quota; you can buy extra credit packs that never expire. Free users don't have the assistant." },
    ],
  },
  {
    icon: "◇", color: "#a8503a", title: "Premium & billing",
    items: [
      { q: "What are the plans?", a: "Free (all core money tracking), Lite (₹49/mo or ₹499/yr) and Pro (₹99/mo or ₹999/yr). Lite and Pro unlock Insights, Statements, Ask PocketCare, auto-categorisation and more; Pro has a larger AI quota." },
      { q: "Is there a trial?", a: "New accounts get a 14-day free trial with full access. You'll see a countdown and can upgrade anytime from Settings." },
      { q: "Can I cancel or get invoices?", a: "Yes — cancel anytime from Settings → Plan & billing (you keep access until the cycle ends). Every payment has a downloadable invoice in your billing history." },
    ],
  },
  {
    icon: "◐", color: "#7c7264", title: "Privacy & sync",
    items: [
      { q: "Where is my data stored?", a: "Locally on your device first, then synced to your private account. Each person only ever syncs their own rows (plus the shared split facts of groups they're in)." },
      { q: "Is splitting safe for privacy?", a: "Yes — shared split tables carry no private data. Your accounts, categories and personal transactions stay entirely yours." },
    ],
  },
];

export default function HelpPage() {
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState<Set<string>>(new Set());
  const toggle = (k: string) => setOpen((s) => { const n = new Set(s); n.has(k) ? n.delete(k) : n.add(k); return n; });

  const q = query.trim().toLowerCase();
  const sections = useMemo(() => {
    if (!q) return SECTIONS;
    return SECTIONS.map((s) => ({ ...s, items: s.items.filter((it) => (it.q + " " + it.a).toLowerCase().includes(q)) })).filter((s) => s.items.length);
  }, [q]);

  return (
    <div style={{ display: "grid", gap: 20, maxWidth: 760 }} className="fade-up">
      <div>
        <h1 style={{ margin: 0 }}>Help &amp; FAQ</h1>
        <p className="muted" style={{ marginTop: 6 }}>Everything PocketCare can do. Still stuck? Ask <Link href="/assistant">Ask PocketCare</Link>.</p>
      </div>

      <input className="input" placeholder="Search help — e.g. “split”, “budget”, “invoice”…" value={query} onChange={(e) => setQuery(e.target.value)} />

      {sections.length === 0 && <p className="muted">No help topics match “{query}”. Try a different word, or ask the assistant.</p>}

      {sections.map((s) => (
        <section key={s.title} style={{ display: "grid", gap: 8 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span style={{ width: 30, height: 30, borderRadius: 9, background: s.color, color: "#fff", display: "grid", placeItems: "center", fontSize: 16, flexShrink: 0 }}>{s.icon}</span>
            <h2 style={{ margin: 0, fontSize: 17 }}>{s.title}</h2>
          </div>
          <div className="card" style={{ padding: 4, overflow: "hidden" }}>
            {s.items.map((it) => {
              const key = s.title + it.q;
              const isOpen = open.has(key) || !!q;
              return (
                <div key={it.q} style={{ borderBottom: "1px solid var(--border)" }}>
                  <button onClick={() => toggle(key)} style={{ width: "100%", textAlign: "left", background: "transparent", border: "none", cursor: "pointer", padding: "13px 14px", display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, color: "var(--text)", fontSize: 14.5, fontWeight: 550 }}>
                    <span>{it.q}</span>
                    <span style={{ color: "var(--text-2)", flexShrink: 0, transition: "transform 0.15s", transform: isOpen ? "rotate(90deg)" : "none" }}>›</span>
                  </button>
                  {isOpen && <div className="muted" style={{ padding: "0 14px 14px", fontSize: 14, lineHeight: 1.55 }}>{it.a}</div>}
                </div>
              );
            })}
          </div>
        </section>
      ))}

      <p className="muted" style={{ fontSize: 12, textAlign: "center", paddingTop: 8 }}>PocketCare · your money, quietly organised.</p>
    </div>
  );
}
