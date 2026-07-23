"use client";

/**
 * Planned Cashflow (BETA) — the consolidated hub.
 *
 * Merges recurring incomes, planned payments (household + subscriptions + loan
 * EMIs), a savings/investment tracker, aggregate summaries per timeframe, and a
 * deterministic AI projection engine with interactive charts. Writes route to
 * the right synced table: incomes/household/savings → `planned_cashflow`,
 * subscriptions → `subscriptions`, loans → `loans`. Design tokens only.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { useRouter } from "next/navigation";
import { useQuery } from "@powersync/react";
import { money, fromMajor, toMajor } from "@pocketcare/money";
import { monthlyEquivalent } from "@pocketcare/finance";
import type { Period } from "@pocketcare/types";
import { useBaseCurrency, useConvert, useConvertAmount } from "../../src/hooks";
import { insertRow, updateRow, softDelete } from "../../src/write";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { Modal } from "../../src/ui/Modal";
import { KebabMenu } from "../../src/ui/KebabMenu";
import { useConfirm } from "../../src/ui/Confirm";
import { useMoneyFmt } from "../../src/ui/Money";
import {
  BUCKETS,
  TEMPLATES,
  TIMEFRAMES,
  bucketIcon,
  bucketLabel,
  computeTotals,
  blendedReturnPct,
  scaleToTimeframe,
  type Direction,
  type Timeframe,
  type PlannedItem,
  type Template,
} from "../../src/cashflow/model";
import { SplitDonut, RatioBars } from "../../src/cashflow/Charts";
import { useRecurringItems, removeRecurring, type RecurringItem, type RecurringDirection } from "../../src/cashflow/recurring";
import { ProjectionPanel } from "../../src/cashflow/Projections";

const CYCLES: Period[] = ["daily", "weekly", "monthly", "yearly"];

/** Smooth-scroll to a section by id (used by the hero cards + #hash deep-links). */
function scrollToSection(id: string) {
  if (typeof document === "undefined") return;
  document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
}

interface Sub { id: string; name: string; amount: number; currency: string; billing_cycle: Period; next_renewal: string | null }
interface Loan { id: string; lender: string; principal: number; currency: string; emi_amount: number | null }

/** Next monthly due date from a start date (simple monthly roll for display). */
function nextMonthly(start: string | null): string | null {
  if (!start) return null;
  const d = new Date(start);
  if (Number.isNaN(d.getTime())) return null;
  const now = new Date();
  while (d <= now) d.setMonth(d.getMonth() + 1);
  return d.toLocaleDateString();
}

export default function CashflowPage() {
  const { t } = useTranslation("cashflow");
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const router = useRouter();
  const convertAmount = useConvertAmount();

  const { data: items = [] } = useQuery<PlannedItem>(
    "SELECT id, name, direction, bucket, amount, currency, frequency, timeframe, next_due, expected_return, is_active FROM planned_cashflow WHERE deleted_at IS NULL AND is_active = 1 ORDER BY created_at",
  );
  const { data: subs = [] } = useQuery<Sub>(
    "SELECT id, name, amount, currency, billing_cycle, next_renewal FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1 ORDER BY created_at",
  );
  const { data: loans = [] } = useQuery<Loan>(
    "SELECT id, lender, principal, currency, emi_amount FROM loans WHERE deleted_at IS NULL ORDER BY created_at",
  );

  const incomes = items.filter((i) => i.direction === "income");
  const household = items.filter((i) => i.direction === "payment");
  const savings = items.filter((i) => i.direction === "saving");

  // Recurring-rule-backed items (real templates + rules that post transactions).
  const recurring = useRecurringItems();
  const recIncomes = recurring.filter((r) => r.direction === "income");
  const recPayments = recurring.filter((r) => r.direction === "payment");
  const recSavings = recurring.filter((r) => r.direction === "saving");

  const [timeframe, setTimeframe] = useState<Timeframe>("monthly");
  // Adding/editing/converting recurring items happens on the dedicated /recurring page.
  const goRecurring = (direction: RecurringDirection, opts?: { name?: string; amountMinor?: number; freq?: string; convertFrom?: string }) => {
    const p = new URLSearchParams({ add: direction });
    if (opts?.name) p.set("name", opts.name);
    if (opts?.amountMinor != null) p.set("amount", String(opts.amountMinor));
    if (opts?.freq) p.set("freq", opts.freq);
    if (opts?.convertFrom) p.set("convertFrom", opts.convertFrom);
    router.push(`/recurring?${p.toString()}`);
  };

  // Deep-link support: e.g. /cashflow#payments (from the dashboard tile) scrolls
  // straight to that section. Retry briefly while synced data grows the page.
  useEffect(() => {
    const hash = typeof window !== "undefined" ? window.location.hash.slice(1) : "";
    if (!hash) return;
    let tries = 0;
    let timer: ReturnType<typeof setTimeout>;
    const tryScroll = () => {
      const el = document.getElementById(hash);
      if (el) { el.scrollIntoView({ behavior: "smooth", block: "start" }); return; }
      if (tries++ < 20) timer = setTimeout(tryScroll, 100);
    };
    timer = setTimeout(tryScroll, 200);
    return () => clearTimeout(timer);
  }, []);

  // Everything is summed in the base currency: convert each item's amount from
  // its stored currency so totals are correct even across currencies / after a
  // base-currency change.
  const cv = (amount: number, currency: string | null) => convertAmount(amount, currency || base);
  const recRow = (r: RecurringItem) => ({ amount: cv(r.amount, r.currency), frequency: r.frequency as Period });
  const totals = computeTotals({
    incomes: [...incomes.map((i) => ({ amount: cv(i.amount, i.currency), frequency: i.frequency })), ...recIncomes.map(recRow)],
    household: [...household.map((i) => ({ amount: cv(i.amount, i.currency), frequency: i.frequency })), ...recPayments.map(recRow)],
    savings: [...savings.map((i) => ({ amount: cv(i.amount, i.currency), frequency: i.frequency })), ...recSavings.map(recRow)],
    subscriptions: subs.map((s) => ({ amount: cv(s.amount, s.currency), frequency: s.billing_cycle })),
    loanEmis: loans.filter((l) => l.emi_amount).map((l) => ({ amount: cv(l.emi_amount!, l.currency), frequency: "monthly" as Period })),
  });

  const tfIncome = scaleToTimeframe(totals.income, timeframe);
  const tfPayments = scaleToTimeframe(totals.payments, timeframe);
  const tfNet = scaleToTimeframe(totals.net, timeframe);
  const tfSavings = scaleToTimeframe(totals.savings, timeframe);
  const seedReturn = blendedReturnPct(savings);
  const toMaj = (minor: number) => toMajor(money(minor, base));

  return (
    <div style={{ display: "grid", gap: 22 }} className="fade-up">
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12, flexWrap: "wrap" }}>
        <div>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <h1 style={{ margin: 0 }}>{t("title")}</h1>
            <span className="beta-badge">BETA</span>
          </div>
          <p className="muted" style={{ margin: "4px 0 0", fontSize: 13.5, maxWidth: 560 }}>
            {t("intro")}
          </p>
        </div>
        <div className="pc-segment">
          {TIMEFRAMES.map((tf) => (
            <button key={tf.key} className="pc-seg-btn" data-active={timeframe === tf.key} onClick={() => setTimeframe(tf.key)}>{tf.label}</button>
          ))}
        </div>
      </div>

      {/* Aggregate summary hero */}
      <div className="pc-hero">
        <HeroStat label={t("recurringIncome")} value={fmt(money(tfIncome, base))} tone="positive" sub={t("per", { unit: t(`timeframeNoun.${timeframe}`) })} targetId="incomes" />
        <HeroStat label={t("plannedPayments")} value={fmt(money(tfPayments, base))} tone="negative" sub={t("commitments", { count: household.length + subs.length + loans.filter((l) => l.emi_amount).length })} targetId="payments" />
        <HeroStat label={t("netDifference")} value={fmt(money(tfNet, base))} tone={tfNet >= 0 ? "positive" : "negative"} sub={t("incomeMinusPayments")} emphasis targetId="summary" />
        <HeroStat label={t("intoSavings")} value={fmt(money(tfSavings, base))} tone="teal" sub={t("plans", { count: savings.length })} targetId="savings" />
      </div>

      {/* Overview charts */}
      <div style={{ display: "grid", gap: 18, gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))" }}>
        <div className="card" style={{ padding: 18 }}>
          <div className="eyebrow" style={{ marginBottom: 8 }}>{t("whereIncomeGoes")}</div>
          <SplitDonut payments={toMaj(totals.payments)} savings={toMaj(totals.savings)} surplus={toMaj(Math.max(totals.surplus, 0))} fmt={(n) => fmt(money(fromMajor(n, base).amount, base))} />
          <Legend items={[
            { label: t("payments"), color: "var(--negative)" },
            { label: t("savings"), color: "var(--teal)" },
            { label: t("freeSurplus"), color: "var(--positive)" },
          ]} />
        </div>
        <div className="card" style={{ padding: 18 }}>
          <div className="eyebrow" style={{ marginBottom: 8 }}>{t("incomeVsPayments")}</div>
          <RatioBars income={toMaj(totals.income)} payments={toMaj(totals.payments)} savings={toMaj(totals.savings)} fmt={(n) => fmt(money(fromMajor(n, base).amount, base))} />
        </div>
      </div>

      {/* Quick-start templates */}
      <section className="card" style={{ padding: 18, display: "grid", gap: 12 }}>
        <div className="eyebrow">{t("quickAdd")}</div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {TEMPLATES.map((tpl) => (
            <button key={tpl.label} className="pc-template press" onClick={() => goRecurring(tpl.direction, { name: tpl.label, freq: tpl.frequency })}>
              <span style={{ opacity: 0.7 }}>{bucketIcon(tpl.direction, tpl.bucket)}</span> {tpl.label}
            </button>
          ))}
        </div>
        <p className="muted" style={{ fontSize: 12, margin: 0 }}>{t("quickAddNotePre")}<Link href="/recurring">{t("quickAddNoteLink")}</Link>{t("quickAddNotePost")}</p>
      </section>

      {/* Recurring incomes */}
      <Section id="incomes" title={t("recurringIncomes")} accent="positive" count={incomes.length + recIncomes.length} onAdd={() => goRecurring("income")} addLabel={t("addIncome")}
        empty={t("emptyIncomes")}>
        {recIncomes.map((r) => <RecurringRow key={r.ruleId} item={r} base={base} onEdit={() => router.push(`/recurring?edit=${r.ruleId}`)} />)}
        {incomes.map((i) => <PlannedRow key={i.id} item={i} base={base} onConvert={() => convert(i)} />)}
      </Section>

      {/* Planned payments (recurring + subscriptions + loans + legacy) */}
      <Section id="payments" title={t("plannedPaymentsTitle")} accent="negative" count={recPayments.length + household.length + subs.length + loans.length} onAdd={() => goRecurring("payment")} addLabel={t("addPayment")}
        empty={t("emptyPayments")}>
        {recPayments.map((r) => <RecurringRow key={r.ruleId} item={r} base={base} onEdit={() => router.push(`/recurring?edit=${r.ruleId}`)} />)}
        {household.map((i) => <PlannedRow key={i.id} item={i} base={base} onConvert={() => convert(i)} />)}
        {subs.map((s) => <SubRow key={s.id} sub={s} base={base} />)}
        {loans.map((l) => <LoanRow key={l.id} loan={l} base={base} />)}
      </Section>

      {/* Savings & investments */}
      <Section id="savings" title={t("savingsInvest")} accent="teal" count={savings.length + recSavings.length} onAdd={() => goRecurring("saving")} addLabel={t("addRecurringSaving")}
        empty={t("emptySavings")}>
        <PortfolioSummary base={base} />
        {recSavings.map((r) => <RecurringRow key={r.ruleId} item={r} base={base} onEdit={() => router.push(`/recurring?edit=${r.ruleId}`)} />)}
        {savings.map((i) => <PlannedRow key={i.id} item={i} base={base} showReturn onConvert={() => convert(i)} />)}
        <p className="muted" style={{ fontSize: 12, margin: 0 }}>{t("trackHoldingsPre")}<Link href="/investments">{t("trackHoldingsLink")}</Link>{t("trackHoldingsPost")}</p>
      </Section>

      {/* Financial summary + AI projections */}
      <section id="summary" className="card pc-glass" style={{ padding: 20, display: "grid", gap: 16, scrollMarginTop: 80 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
          <div className="eyebrow">{t("financialSummary")}</div>
          <span className="beta-badge">BETA</span>
        </div>
        <div className="pc-netline">
          <div>
            <div className="muted" style={{ fontSize: 13 }}>{t("netMonthly")}</div>
            <div style={{ fontSize: 34, fontWeight: 780, letterSpacing: "-0.02em", color: totals.surplus >= 0 ? "var(--positive)" : "var(--negative)" }}>
              {totals.surplus >= 0 ? "+" : "−"}{fmt(money(Math.abs(totals.surplus), base))}
            </div>
          </div>
          <p className="muted" style={{ fontSize: 12.5, margin: 0, maxWidth: 340 }}>
            {t("projNote")}
          </p>
        </div>
        <ProjectionPanel
          monthlyIncome={totals.income}
          monthlyPayments={totals.payments}
          monthlySavings={totals.savings}
          seedReturnPct={seedReturn}
          currency={base}
        />
      </section>

    </div>
  );

  // "Make it recurring" on a legacy standalone item → the /recurring page opens
  // prefilled and removes the standalone entry once the rule is created.
  function convert(i: PlannedItem) {
    goRecurring(i.direction as RecurringDirection, { name: i.name, amountMinor: i.amount, freq: i.frequency, convertFrom: i.id });
  }
}

// --- Building blocks -------------------------------------------------------

function HeroStat({ label, value, tone, sub, emphasis, targetId }: { label: string; value: string; tone: "positive" | "negative" | "teal"; sub?: string; emphasis?: boolean; targetId?: string }) {
  const color = tone === "positive" ? "var(--positive)" : tone === "negative" ? "var(--negative)" : "var(--teal)";
  return (
    <button
      type="button"
      onClick={() => targetId && scrollToSection(targetId)}
      className="card lift press"
      style={{ padding: 18, display: "grid", gap: 4, textAlign: "left", cursor: "pointer", width: "100%", font: "inherit", color: "inherit", borderColor: emphasis ? color : undefined, borderWidth: emphasis ? 1.5 : 1 }}
    >
      <span className="eyebrow" style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 6 }}>
        {label}<span aria-hidden style={{ color: "var(--text-3)", fontWeight: 700 }}>↓</span>
      </span>
      <div style={{ fontSize: emphasis ? 27 : 24, fontWeight: 760, letterSpacing: "-0.015em", color }}>{value}</div>
      {sub && <span className="muted" style={{ fontSize: 11.5, textTransform: "capitalize" }}>{sub}</span>}
    </button>
  );
}

function Section({ id, title, accent, count, onAdd, addLabel, empty, children }: {
  id?: string; title: string; accent: "positive" | "negative" | "teal"; count: number; onAdd: () => void; addLabel: string; empty: string; children: React.ReactNode;
}) {
  const color = accent === "positive" ? "var(--positive)" : accent === "negative" ? "var(--negative)" : "var(--teal)";
  return (
    <section id={id} style={{ display: "grid", gap: 12, scrollMarginTop: 80 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12 }}>
        <h2 style={{ margin: 0, display: "flex", alignItems: "center", gap: 10, fontSize: 18 }}>
          <span style={{ width: 10, height: 10, borderRadius: 999, background: color }} /> {title}
          <span className="muted" style={{ fontSize: 13, fontWeight: 500 }}>{count}</span>
        </h2>
        <button className="btn ghost" style={{ padding: "8px 14px", fontSize: 13 }} onClick={onAdd}>+ {addLabel}</button>
      </div>
      {count > 0 ? (
        <div className="list-grid">{children}</div>
      ) : (
        <div className="card" style={{ padding: 24, textAlign: "center", color: "var(--text-3)", fontSize: 13 }}>{empty}</div>
      )}
    </section>
  );
}

function Legend({ items }: { items: { label: string; color: string }[] }) {
  return (
    <div style={{ display: "flex", gap: 16, justifyContent: "center", flexWrap: "wrap", marginTop: 6 }}>
      {items.map((i) => (
        <span key={i.label} style={{ display: "inline-flex", alignItems: "center", gap: 6, fontSize: 12, color: "var(--text-2)" }}>
          <span style={{ width: 9, height: 9, borderRadius: 999, background: i.color }} /> {i.label}
        </span>
      ))}
    </div>
  );
}

function RowShell({ icon, title, subtitle, right, actions, href }: { icon: string; title: string; subtitle: string; right: React.ReactNode; actions: React.ReactNode; href?: string }) {
  const info = (
    <>
      <span className="pc-row-icon">{icon}</span>
      <div style={{ minWidth: 0, flex: 1 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <strong style={{ fontSize: 14.5, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{title}</strong>
        </div>
        <div className="muted" style={{ fontSize: 12 }}>{subtitle}</div>
      </div>
    </>
  );
  return (
    <div className="card lift" style={{ padding: "14px 16px", display: "flex", alignItems: "center", gap: 14 }}>
      {href ? (
        <Link href={href} style={{ display: "flex", alignItems: "center", gap: 14, flex: 1, minWidth: 0, color: "inherit" }}>{info}</Link>
      ) : (
        <div style={{ display: "flex", alignItems: "center", gap: 14, flex: 1, minWidth: 0 }}>{info}</div>
      )}
      <div style={{ textAlign: "right", display: "grid", gap: 2 }}>{right}</div>
      {actions}
    </div>
  );
}

/** Read-only invested-portfolio summary (cost + current) linking to /investments.
 *  Uses current_value (else cost) so it works without the live market feed. */
function PortfolioSummary({ base }: { base: string }) {
  const { t } = useTranslation("cashflow");
  const fmt = useMoneyFmt();
  const convertAmount = useConvertAmount();
  const { data: holdings = [] } = useQuery<{ quantity: number; avg_cost: number | null; current_value: number | null; currency: string }>(
    "SELECT quantity, avg_cost, current_value, currency FROM holdings WHERE deleted_at IS NULL",
  );
  if (holdings.length === 0) return null;
  let cost = 0, value = 0;
  for (const h of holdings) {
    const c = Math.round((h.avg_cost ?? 0) * h.quantity);
    cost += convertAmount(c, h.currency);
    value += convertAmount(h.current_value ?? c, h.currency);
  }
  const gain = value - cost;
  const up = gain >= 0;
  return (
    <Link href="/investments" className="card lift" style={{ padding: 14, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, color: "inherit", background: "linear-gradient(135deg, var(--teal-ghost, var(--surface-2)), transparent)" }}>
      <div>
        <div className="eyebrow">{t("portfolioTitle")}</div>
        <div className="muted" style={{ fontSize: 12 }}>{t("portfolioMeta", { count: holdings.length, amount: fmt(money(Math.round(cost), base)) })}</div>
      </div>
      <div style={{ textAlign: "right" }}>
        <div style={{ fontSize: 18, fontWeight: 740 }}>{fmt(money(Math.round(value), base))}</div>
        <div style={{ fontSize: 12, color: up ? "var(--positive)" : "var(--negative)", fontWeight: 600 }}>{up ? "+" : "−"}{fmt(money(Math.round(Math.abs(gain)), base))}</div>
      </div>
    </Link>
  );
}

function PlannedRow({ item, base, showReturn, onConvert }: { item: PlannedItem; base: string; showReturn?: boolean; onConvert?: () => void }) {
  const { t } = useTranslation("cashflow");
  const fmt = useMoneyFmt();
  const conv = useConvert();
  const confirm = useConfirm();
  const [editing, setEditing] = useState(false);
  const monthly = monthlyEquivalent(item.amount, item.frequency);
  const cur = item.currency || base;
  if (editing) return <EditPlanned item={item} onDone={() => setEditing(false)} />;
  return (
    <RowShell
      icon={bucketIcon(item.direction, item.bucket)}
      title={item.name}
      subtitle={`${bucketLabel(item.direction, item.bucket)} · ${t(`freq.${item.frequency}`, item.frequency)}${showReturn && item.expected_return != null ? ` · ${t("perAnnum", { pct: (item.expected_return / 100).toFixed(1) })}` : ""} · ${t("oneOff")}`}
      right={<>
        <span style={{ fontWeight: 650, fontSize: 14 }}>{fmt(conv(money(item.amount, cur)))}</span>
        <span className="muted" style={{ fontSize: 11 }}>{fmt(conv(money(monthly, cur)))}{t("perMonth")}</span>
      </>}
      actions={
        <KebabMenu label={t("actions", { name: item.name })} items={[
          ...(onConvert ? [{ label: t("makeRecurring"), onClick: onConvert }] : []),
          { label: t("edit"), onClick: () => setEditing(true) },
          { label: t("remove"), danger: true, onClick: async () => { if (await confirm({ title: t("removeItemTitle"), message: t("removeItemMsg", { name: item.name }), confirmLabel: t("remove") })) softDelete("planned_cashflow", item.id); } },
        ]} />
      }
    />
  );
}

/** A recurring-rule-backed row (real template + rule that posts transactions). */
function RecurringRow({ item, base, onEdit }: { item: RecurringItem; base: string; onEdit: () => void }) {
  const { t } = useTranslation("cashflow");
  const fmt = useMoneyFmt();
  const conv = useConvert();
  const confirm = useConfirm();
  const monthly = monthlyEquivalent(item.amount, item.frequency as Period);
  const cur = item.currency || base;
  const icon = item.direction === "income" ? "＋" : item.direction === "saving" ? "▲" : "↻";
  const nextDue = item.next_due ? new Date(item.next_due + "T00:00:00").toLocaleDateString(undefined, { day: "numeric", month: "short" }) : "—";
  return (
    <RowShell
      icon={icon}
      title={item.name}
      subtitle={`${t(`freq.${item.frequency}`, item.frequency)} · ${t("next", { date: nextDue })} · ${item.auto_post ? t("autoPosts") : t("confirm")}`}
      right={<>
        <span style={{ fontWeight: 650, fontSize: 14 }}>{fmt(conv(money(item.amount, cur)))}</span>
        <span className="muted" style={{ fontSize: 11 }}>{fmt(conv(money(monthly, cur)))}{t("perMonth")}</span>
      </>}
      actions={
        <KebabMenu label={t("actions", { name: item.name })} items={[
          { label: t("edit"), onClick: onEdit },
          { label: t("remove"), danger: true, onClick: async () => { if (await confirm({ title: t("removeRecurringTitle"), message: t("removeRecurringMsg", { name: item.name }), confirmLabel: t("remove") })) removeRecurring(item.ruleId, item.templateId); } },
        ]} />
      }
    />
  );
}

function SubRow({ sub, base }: { sub: Sub; base: string }) {
  const { t } = useTranslation("cashflow");
  const fmt = useMoneyFmt();
  const conv = useConvert();
  const confirm = useConfirm();
  const monthly = monthlyEquivalent(sub.amount, sub.billing_cycle);
  const due = nextMonthly(sub.next_renewal);
  const cur = sub.currency || base;
  return (
    <RowShell
      icon="↻"
      title={sub.name}
      subtitle={`${t("subscription")} · ${t(`freq.${sub.billing_cycle}`, sub.billing_cycle)}${due ? ` · ${t("next", { date: due })}` : ""}`}
      right={<>
        <span style={{ fontWeight: 650, fontSize: 14 }}>{fmt(conv(money(sub.amount, cur)))}</span>
        <span className="muted" style={{ fontSize: 11 }}>{fmt(conv(money(monthly, cur)))}{t("perMonth")}</span>
      </>}
      actions={
        <KebabMenu label={t("actions", { name: sub.name })} items={[
          { label: t("remove"), danger: true, onClick: async () => { if (await confirm({ title: t("removeSubTitle"), message: t("removeSubMsg", { name: sub.name }), confirmLabel: t("remove") })) softDelete("subscriptions", sub.id); } },
        ]} />
      }
    />
  );
}

function LoanRow({ loan, base }: { loan: Loan; base: string }) {
  const { t } = useTranslation("cashflow");
  const fmt = useMoneyFmt();
  const conv = useConvert();
  const confirm = useConfirm();
  const cur = loan.currency || base;
  return (
    <RowShell
      icon="≈"
      href={`/loans/${loan.id}`}
      title={loan.lender || t("loanFallback")}
      subtitle={t("loanSubtitle", { amount: fmt(conv(money(loan.principal, cur))) })}
      right={<>
        <span style={{ fontWeight: 650, fontSize: 14 }}>{loan.emi_amount ? fmt(conv(money(loan.emi_amount, cur))) : "—"}</span>
        <span className="muted" style={{ fontSize: 11 }}>{t("emiPerMonth")}</span>
      </>}
      actions={
        <KebabMenu label={t("actions", { name: loan.lender || t("loanFallback") })} items={[
          { label: t("viewSchedule"), onClick: () => { window.location.href = `/loans/${loan.id}`; } },
          { label: t("remove"), danger: true, onClick: async () => { if (await confirm({ title: t("removeLoanTitle"), message: t("removeLoanMsg", { name: loan.lender || t("loanFallback") }), confirmLabel: t("remove") })) softDelete("loans", loan.id); } },
        ]} />
      }
    />
  );
}

function EditPlanned({ item, onDone }: { item: PlannedItem; onDone: () => void }) {
  const { t } = useTranslation("cashflow");
  const [name, setName] = useState(item.name);
  const [amount, setAmount] = useState(String(toMajor(money(item.amount, item.currency))));
  const [freq, setFreq] = useState<Period>(item.frequency);
  const [ret, setRet] = useState(item.expected_return != null ? String(item.expected_return / 100) : "");
  async function save() {
    await updateRow("planned_cashflow", item.id, {
      name: name.trim() || item.name,
      amount: fromMajor(Number(amount) || 0, item.currency).amount,
      frequency: freq,
      expected_return: item.direction === "saving" ? Math.round((Number(ret) || 0) * 100) : null,
    });
    onDone();
  }
  return (
    <div className="card" style={{ padding: 16, display: "grid", gap: 10 }}>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <FloatingInput label={t("name")} value={name} onChange={setName} style={{ flex: 1, minWidth: 150 }} />
        <FloatingInput label={t("amount")} group currency={item.currency} value={amount} onChange={setAmount} style={{ width: 130 }} />
        {item.direction === "saving" && <FloatingInput label={t("returnPct")} inputMode="decimal" value={ret} onChange={(v) => setRet(v.replace(/[^0-9.]/g, ""))} style={{ width: 110 }} />}
      </div>
      <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        <div style={{ display: "flex", gap: 6 }}>{CYCLES.map((c) => <button key={c} className="chip" data-active={c === freq} onClick={() => setFreq(c)}>{t(`freq.${c}`)}</button>)}</div>
        <button className="btn" onClick={save}>{t("save")}</button>
        <button className="chip" onClick={onDone}>{t("cancel")}</button>
      </div>
    </div>
  );
}

function AddModal({ ctx, base, onClose }: { ctx: { direction: Direction; seed?: Template }; base: string; onClose: () => void }) {
  const { t } = useTranslation("cashflow");
  const { direction, seed } = ctx;
  const [bucket, setBucket] = useState(seed?.bucket ?? BUCKETS[direction][0]!.key);
  const [name, setName] = useState(seed?.label ?? "");
  const [amount, setAmount] = useState("");
  const [freq, setFreq] = useState<Period>(seed?.frequency ?? "monthly");
  const [ret, setRet] = useState(seed?.expectedReturnPct != null ? String(seed.expectedReturnPct) : "");
  const [start, setStart] = useState(new Date().toISOString().slice(0, 10));

  const isSub = direction === "payment" && bucket === "subscription";
  const isLoan = direction === "payment" && bucket === "loan"; // loans are managed on /loans; the modal redirects there
  const title = direction === "income" ? t("addIncomeTitle") : direction === "saving" ? t("addSavingsTitle") : t("addPaymentTitle");

  async function submit() {
    if (!name.trim() || !amount) return;
    const minor = fromMajor(Number(amount), base).amount;
    if (isSub) {
      await insertRow("subscriptions", { name: name.trim(), amount: minor, currency: base, billing_cycle: freq, purchased_on: start || null, next_renewal: start || null, is_active: 1 });
    } else {
      await insertRow("planned_cashflow", {
        name: name.trim(), direction, bucket, amount: minor, currency: base, frequency: freq,
        timeframe: freq === "yearly" ? "yearly" : "monthly", next_due: start || null,
        expected_return: direction === "saving" ? Math.round((Number(ret) || 0) * 100) : null, is_active: 1,
      });
    }
    onClose();
  }

  return (
    <Modal open onClose={onClose}>
      <div style={{ display: "grid", gap: 14 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <h2 style={{ margin: 0 }}>{title}</h2>
          <span className="beta-badge">BETA</span>
        </div>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {BUCKETS[direction].map((b) => (
            <button key={b.key} className="chip" data-active={b.key === bucket} onClick={() => { setBucket(b.key); }}>
              <span style={{ opacity: 0.7, marginRight: 4 }}>{b.icon}</span>{b.label}
            </button>
          ))}
        </div>
        {isLoan ? (
          <div style={{ display: "grid", gap: 12, padding: "6px 0" }}>
            <p className="muted" style={{ margin: 0, fontSize: 13.5, lineHeight: 1.5 }}>
              {t("loanNote")}
            </p>
            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
              <button className="btn ghost" onClick={onClose}>{t("cancel")}</button>
              <Link href="/loans" className="btn" onClick={onClose}>{t("goToLoans")}</Link>
            </div>
          </div>
        ) : (
          <>
            <FloatingInput label={t("name")} value={name} onChange={setName} />
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              <FloatingInput label={t("amountCur", { base })} group currency={base} value={amount} onChange={setAmount} style={{ flex: 1, minWidth: 130 }} />
              {direction === "saving" && <FloatingInput label={t("returnPa")} inputMode="decimal" value={ret} onChange={(v) => setRet(v.replace(/[^0-9.]/g, ""))} style={{ width: 120 }} />}
            </div>
            <div style={{ display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap" }}>
              <span className="muted" style={{ fontSize: 12 }}>{t("frequency")}</span>
              {CYCLES.map((c) => <button key={c} className="chip" data-active={c === freq} onClick={() => setFreq(c)}>{t(`freq.${c}`)}</button>)}
            </div>
            {(isSub || direction !== "payment") && (
              <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>{direction === "income" ? t("nextExpected") : isSub ? t("startedRenewal") : t("nextDue")}
                <input className="input" type="date" value={start} onChange={(e) => setStart(e.target.value)} />
              </label>
            )}
            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
              <button className="btn ghost" onClick={onClose}>{t("cancel")}</button>
              <button className="btn" onClick={submit} disabled={!name.trim() || !amount}>{t("add")}</button>
            </div>
          </>
        )}
      </div>
    </Modal>
  );
}
