"use client";

/**
 * First-run walkthrough. Plan: docs/plans/first-run-walkthrough.md
 *
 * Written for a specific person: a 60+ user who signed up, landed on the
 * dashboard, didn't know what to do, and believed "add an account" meant
 * linking their real bank. They stopped there.
 *
 * Three rules follow from that, and every step obeys them:
 *
 *  1. SAY WHAT THE APP IS, FIRST. Not what to tap — what it *is*, and what it
 *     is not. "Not connected to your bank" is the single most important
 *     sentence in this file.
 *  2. MANUAL ENTRY IS THE PRODUCT, NOT AN APOLOGY. Typing your own spends is
 *     what makes you notice them. Framed as the point, it stops being a chore.
 *  3. DON'T SEND THEM TO THE REAL FORM. `/accounts/new` offers Savings /
 *     Current / Credit card / Demat, which reads as bank onboarding. Step 2
 *     asks for a name and a number, and defaults the rest.
 *
 * Structure: Part A (1–4) is setup and ends in a real Finish. Part B (5–7) is
 * opt-in — making onboarding *longer* would be the wrong answer to "I found
 * this overwhelming".
 */

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslation } from "react-i18next";
import { fromMajor, money } from "@sanvya/money";
import type { CurrencyCode } from "@sanvya/types";
import { PLANS, price } from "../billing/plans";
import { getRepositories } from "../powersync";
import { useBaseCurrency } from "../hooks";
import { useSession } from "../account";
import { useEntitlement } from "../entitlement";
import { colorForId } from "../colors";
import { Modal } from "../ui/Modal";
import { AmountInput } from "../ui/AmountInput";
import { MaterialIcon, type MaterialIconName } from "../ui/MaterialIcon";
import { useWalkthrough } from "./useWalkthrough";

/** Body copy here is 15px, not the app's 12.5–13px muted default. See the plan. */
const BODY: React.CSSProperties = { fontSize: 15, lineHeight: 1.55, margin: 0, color: "var(--text)" };
const STRONG: React.CSSProperties = { ...BODY, fontWeight: 700 };

function StepHeader({ icon, title, step, of }: { icon: MaterialIconName; title: string; step: number; of: number }) {
  const { t } = useTranslation("onboarding");
  return (
    <div style={{ display: "grid", gap: 8 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10 }}>
        <span style={{
          width: 42, height: 42, borderRadius: 12, flexShrink: 0,
          background: "var(--accent-ghost)", color: "var(--accent)",
          display: "grid", placeItems: "center",
        }}>
          <MaterialIcon name={icon} size={24} />
        </span>
        <span className="muted" style={{ fontSize: 12.5, fontWeight: 600 }}>
          {t("wt.progress", { step, of, defaultValue: "Step {{step}} of {{of}}" })}
        </span>
      </div>
      <h2 style={{ margin: 0, fontSize: 21, lineHeight: 1.25 }}>{title}</h2>
    </div>
  );
}

/** Stacked, full-width actions — easier to hit, and the primary one is obvious. */
function Actions({ primary, onPrimary, busy, secondary, onSecondary }: {
  primary: string; onPrimary: () => void; busy?: boolean;
  secondary?: string; onSecondary?: () => void;
}) {
  return (
    <div style={{ display: "grid", gap: 10, marginTop: 4 }}>
      <button className="btn" style={{ justifyContent: "center", minHeight: 46, fontSize: 15 }} onClick={onPrimary} disabled={busy}>
        {primary}
      </button>
      {secondary && onSecondary && (
        <button
          onClick={onSecondary}
          style={{ background: "none", border: "none", cursor: "pointer", font: "inherit", fontSize: 14, color: "var(--text-2)", padding: 8, minHeight: 44 }}
        >
          {secondary}
        </button>
      )}
    </div>
  );
}

export function Walkthrough() {
  const { t } = useTranslation("onboarding");
  const { open, skip, finish } = useWalkthrough();
  const router = useRouter();
  const base = useBaseCurrency();
  const session = useSession();
  const entitlement = useEntitlement();

  const [step, setStep] = useState(1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Step 2 — account
  const [accName, setAccName] = useState("");
  const [accBalance, setAccBalance] = useState("");
  const [accountId, setAccountId] = useState<string | null>(null);

  // Step 3 — first spend
  const [spendWhat, setSpendWhat] = useState("");
  const [spendAmount, setSpendAmount] = useState("");

  const isGuest = !!session?.isGuest;
  const onTrial = !isGuest && entitlement.isTrial;

  const placeholders = useMemo(
    () => [t("wt.acc.eg1", "HDFC savings"), t("wt.acc.eg2", "Cash in purse")].join(" · "),
    [t],
  );

  /**
   * Create the first account with two fields. Everything else takes a sane
   * default — a nervous first-timer never meets the type/currency/overdraft
   * form. All of it is editable later at /accounts/<id>/edit.
   */
  async function saveAccount() {
    const name = accName.trim();
    if (!name || busy) return;
    setBusy(true);
    setError(null);
    try {
      const repos = getRepositories();
      const account = await repos.accounts.create({
        name, type: "savings", currency: base, icon: null,
        color: colorForId(name), is_archived: false, allow_negative: false,
      });
      setAccountId(account.id);
      const major = Number(accBalance);
      if (Number.isFinite(major) && major > 0) {
        await repos.accounts.setOpeningBalance(account.id, fromMajor(major, base as CurrencyCode), new Date().toISOString());
      }
      setStep(3);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  /** Record the first spend against the account we just made. */
  async function saveSpend() {
    const desc = spendWhat.trim();
    const minor = Math.round((Number(spendAmount) || 0) * 100);
    if (!desc || minor <= 0 || busy) return;
    setBusy(true);
    setError(null);
    try {
      const repos = getRepositories();
      let target = accountId;
      if (!target) {
        const all = await repos.accounts.list();
        target = all[0]?.id ?? null;
      }
      if (!target) { setStep(4); return; }
      await repos.transactions.create({
        account_id: target,
        type: "expense",
        amount: money(minor, base as CurrencyCode),
        description: desc,
        occurred_at: new Date().toISOString(),
        labels: [],
      });
      setStep(4);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  if (!open) return null;

  const partA = step <= 4;
  const num = partA ? step : step - 4;
  const of = partA ? 4 : 3;

  return (
    <Modal open={open} onClose={skip} label={t("wt.dialogLabel", "Getting started with Sanvya")}>
      <div style={{ display: "grid", gap: 18 }}>
        {/* ---- Step 1: what this app IS ---- */}
        {step === 1 && (
          <>
            <StepHeader icon="volunteer_activism" step={num} of={of} title={t("wt.intro.title", "Welcome to Sanvya")} />
            <p style={BODY}>{t("wt.intro.p1", "Sanvya is your private money diary. You write down what you spend and earn, and it shows you where your money is actually going.")}</p>
            <p style={STRONG}>{t("wt.intro.p2", "It is not connected to your bank.")}</p>
            <p style={BODY}>{t("wt.intro.p3", "We never ask for your bank login, card number or OTP, and we can't see your bank at all.")}</p>
            <p style={BODY}>{t("wt.intro.p4", "Nothing is tracked automatically — you'll type your spends in yourself. That's deliberate: the few seconds it takes is what makes you notice where your money goes, and noticing is the whole point.")}</p>
            <Actions
              primary={t("wt.intro.cta", "Show me how")} onPrimary={() => setStep(2)}
              secondary={t("wt.skip", "I'll look around myself")} onSecondary={skip}
            />
          </>
        )}

        {/* ---- Step 2: first account, inline ---- */}
        {step === 2 && (
          <>
            <StepHeader icon="account_balance" step={num} of={of} title={t("wt.acc.title", "Where do you keep your money?")} />
            <p style={BODY}>{t("wt.acc.p1", "An \"account\" here is just your own note of somewhere money sits — your bank, the cash in your purse, a credit card. It's a name and a number you type. Nothing is linked to the real bank.")}</p>
            <p style={BODY}>{t("wt.acc.p2", "Start with the one you use most. You can add others later.")}</p>

            <label style={{ display: "grid", gap: 6 }}>
              <span style={{ fontSize: 14, fontWeight: 600 }}>{t("wt.acc.nameLabel", "Give it a name")}</span>
              <input
                className="input" value={accName} onChange={(e) => setAccName(e.target.value)}
                placeholder={placeholders} style={{ fontSize: 16, minHeight: 46 }}
              />
            </label>
            <label style={{ display: "grid", gap: 6 }}>
              <span style={{ fontSize: 14, fontWeight: 600 }}>{t("wt.acc.balLabel", "Roughly how much is in it now?")}</span>
              <AmountInput value={accBalance} onChange={setAccBalance} />
              <span className="muted" style={{ fontSize: 13 }}>{t("wt.acc.balHelp", "An approximate number is fine — you can correct it any time.")}</span>
            </label>

            {error && <p style={{ ...BODY, color: "var(--negative)" }}>{error}</p>}
            <Actions
              primary={busy ? t("wt.saving", "Saving…") : t("wt.acc.cta", "Save")} onPrimary={() => void saveAccount()} busy={busy || !accName.trim()}
              secondary={t("wt.later", "Skip this for now")} onSecondary={() => setStep(3)}
            />
          </>
        )}

        {/* ---- Step 3: first spend, inline ---- */}
        {step === 3 && (
          <>
            <StepHeader icon="receipt_long" step={num} of={of} title={t("wt.spend.title", "Now write down one thing you spent")} />
            <p style={BODY}>{t("wt.spend.p1", "Think of the last thing you paid for — tea, groceries, a bill.")}</p>
            <p style={BODY}>{t("wt.spend.p2", "When you record a spend, Sanvya subtracts it from that account, so the number stays true to real life.")}</p>
            <p style={STRONG}>{t("wt.spend.p3", "This is the one habit that matters — everything else in the app is built from it.")}</p>

            <label style={{ display: "grid", gap: 6 }}>
              <span style={{ fontSize: 14, fontWeight: 600 }}>{t("wt.spend.whatLabel", "What was it for?")}</span>
              <input
                className="input" value={spendWhat} onChange={(e) => setSpendWhat(e.target.value)}
                placeholder={t("wt.spend.whatEg", "Groceries")} style={{ fontSize: 16, minHeight: 46 }}
              />
            </label>
            <label style={{ display: "grid", gap: 6 }}>
              <span style={{ fontSize: 14, fontWeight: 600 }}>{t("wt.spend.amountLabel", "How much?")}</span>
              <AmountInput value={spendAmount} onChange={setSpendAmount} />
            </label>

            {error && <p style={{ ...BODY, color: "var(--negative)" }}>{error}</p>}
            <Actions
              primary={busy ? t("wt.saving", "Saving…") : t("wt.spend.cta", "Save")}
              onPrimary={() => void saveSpend()}
              busy={busy || !spendWhat.trim() || !(Number(spendAmount) > 0)}
              secondary={t("wt.later", "Skip this for now")} onSecondary={() => setStep(4)}
            />
          </>
        )}

        {/* ---- Step 4: where to look, and a real exit ---- */}
        {step === 4 && (
          <>
            <StepHeader icon="check" step={num} of={of} title={t("wt.done.title", "That's it — you're set up")} />
            <div style={{ display: "grid", gap: 12 }}>
              <Where icon="space_dashboard" title={t("wt.done.dashTitle", "Dashboard")} body={t("wt.done.dashBody", "Your money at a glance.")} />
              <Where icon="swap_horiz" title={t("wt.done.txnTitle", "Transactions")} body={t("wt.done.txnBody", "Everything you've written down.")} />
              <Where icon="donut_small" title={t("wt.done.budgetTitle", "Budgets")} body={t("wt.done.budgetBody", "Set a monthly limit and Sanvya tells you when to slow down.")} />
            </div>
            <p className="muted" style={{ fontSize: 13.5, lineHeight: 1.5, margin: 0 }}>
              {t("wt.done.privacy", "Your data is yours. It stays on your device and in your private account — we don't share it, and nobody else can see it.")}
            </p>
            <Actions
              primary={t("wt.done.cta", "Finish")} onPrimary={finish}
              secondary={t("wt.done.more", "See what else it does →")} onSecondary={() => setStep(5)}
            />
          </>
        )}

        {/* ---- Step 5: insights ---- */}
        {step === 5 && (
          <>
            <StepHeader icon="insights" step={num} of={of} title={t("wt.insights.title", "Sanvya reads your entries back to you")} />
            <p style={BODY}>{t("wt.insights.p1", "Once you've written a few things down, Sanvya starts pointing things out on its own: which category is eating the most, a month running hotter than the last, a subscription you may have forgotten.")}</p>
            <div className="card" style={{ padding: 12, background: "var(--surface-2)" }}>
              <p style={{ ...BODY, fontSize: 14, fontStyle: "italic" }}>{t("wt.insights.eg", "\"You've spent 32% more on eating out this month than last.\"")}</p>
            </div>
            <p style={BODY}>{t("wt.insights.p2", "You don't have to build a single chart or spreadsheet. The more you write down, the more it has to tell you.")}</p>
            <Actions primary={t("wt.next", "Next")} onPrimary={() => setStep(6)} secondary={t("wt.done.cta", "Finish")} onSecondary={finish} />
          </>
        )}

        {/* ---- Step 6: Ask Sanvya ---- */}
        {step === 6 && (
          <>
            <StepHeader icon="auto_awesome" step={num} of={of} title={t("wt.ask.title", "Or just ask, in your own words")} />
            <p style={BODY}>{t("wt.ask.p1", "Type or say things like \"how much did I spend on groceries last month?\" or \"can I afford ₹15,000 this week?\" — and it answers from your own entries.")}</p>
            <p style={BODY}>{t("wt.ask.p2", "No menus to learn. If you'd rather ask a question than hunt for a screen, this is the shortcut.")}</p>
            <p className="muted" style={{ fontSize: 13.5, lineHeight: 1.5, margin: 0 }}>
              {t("wt.ask.privacy", "It only ever reads your own entries, and nothing is sent anywhere until you ask it something.")}
            </p>
            <Actions primary={t("wt.next", "Next")} onPrimary={() => setStep(7)} secondary={t("wt.done.cta", "Finish")} onSecondary={finish} />
          </>
        )}

        {/* ---- Step 7: trial (or, for guests, an account) ---- */}
        {step === 7 && (
          <>
            {isGuest ? (
              <>
                <StepHeader icon="person" step={num} of={of} title={t("wt.guest.title", "You're using Sanvya as a guest")} />
                <p style={BODY}>{t("wt.guest.p1", "Your entries live only on this device, and guest data is deleted after a few days. Create a free account to keep it — and you'll get 14 days with everything unlocked.")}</p>
                <Actions
                  primary={t("wt.guest.cta", "Create a free account")}
                  onPrimary={() => { finish(); router.push("/login"); }}
                  secondary={t("wt.guest.later", "Later")} onSecondary={finish}
                />
              </>
            ) : (
              <>
                <StepHeader icon="redeem" step={num} of={of}
                  title={onTrial
                    ? t("wt.plan.titleTrial", "Everything is already unlocked for 14 days")
                    : t("wt.plan.title", "What's free, and what's not")} />
                {onTrial && (
                  <p style={BODY}>{t("wt.plan.trial", "Insights, Ask Sanvya and Statements are on right now — no card, nothing to set up. Use them and see whether they're worth it to you.")}</p>
                )}
                <p style={BODY}>{t("wt.plan.free", "The basics stay free forever: your accounts, transactions, budgets and search.")}</p>

                <div style={{ display: "grid", gap: 10 }}>
                  {(["lite", "pro"] as const).map((id) => (
                    <div key={id} className="card" style={{ padding: 14, background: "var(--surface-2)", display: "grid", gap: 4 }}>
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10, flexWrap: "wrap" }}>
                        <strong style={{ fontSize: 16 }}>{PLANS[id].label}</strong>
                        <span style={{ fontSize: 15, fontWeight: 700 }}>
                          {t("wt.plan.perMonth", { amount: price(id, "monthly"), defaultValue: "₹{{amount}}/month" })}
                        </span>
                      </div>
                      <span className="muted" style={{ fontSize: 13.5 }}>
                        {t("wt.plan.quota", { count: PLANS[id].quota, defaultValue: "{{count}} Ask Sanvya questions a month · everything else unlocked" })}
                      </span>
                    </div>
                  ))}
                </div>

                <Actions
                  primary={t("wt.plan.cta", "Done")} onPrimary={finish}
                  secondary={t("wt.plan.see", "See plans")} onSecondary={() => { finish(); router.push("/settings"); }}
                />
              </>
            )}
          </>
        )}
      </div>
    </Modal>
  );
}

function Where({ icon, title, body }: { icon: MaterialIconName; title: string; body: string }) {
  return (
    <div style={{ display: "flex", gap: 12, alignItems: "flex-start" }}>
      <span style={{ color: "var(--accent)", flexShrink: 0, marginTop: 1 }}><MaterialIcon name={icon} size={20} /></span>
      <div style={{ minWidth: 0 }}>
        <div style={{ fontSize: 15, fontWeight: 650 }}>{title}</div>
        <div className="muted" style={{ fontSize: 13.5, lineHeight: 1.45 }}>{body}</div>
      </div>
    </div>
  );
}
