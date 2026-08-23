"use client";

/**
 * Recurring payments & incomes — a dedicated home for salary, rent, bills and
 * other regular money in/out. Each item is a real recurring rule (template +
 * rule) that posts transactions. Opened directly, or deep-linked from Planned
 * Cashflow's "Add income / Add payment" (and quick-add / convert) via query
 * params: ?add=income|payment|saving [&name=&amount=<minor>&freq=&convertFrom=<plannedId>]
 * or ?edit=<ruleId>.
 */
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { useRegisterAddAction } from "../../src/ui/AddAction";
import { PlusIcon } from "../../src/ui/icons";
import { useRouter, useSearchParams } from "next/navigation";
import { money } from "@sanvya/money";
import { useBaseCurrency } from "../../src/hooks";
import { useMoneyFmt } from "../../src/ui/Money";
import { softDelete } from "../../src/write";
import { useRecurringItems, type RecurringItem, type RecurringDirection } from "../../src/cashflow/recurring";
import { useGroupsByDirection, ensureDefaultGroups } from "../../src/recurring/groups";
import { useRecurringSummary } from "../../src/recurring/summary";
import { TriageStrip } from "../../src/recurring/TriageStrip";
import { RecurringModal } from "../../src/cashflow/RecurringModal";

import { postOnce, skipOnce, useDueItems, type Freq } from "../../src/recurring/engine";

interface ModalState { direction: RecurringDirection; edit?: RecurringItem; prefill?: { name?: string; amount?: number; frequency?: Freq }; convertFrom?: string }
const isDir = (s: string | null): s is RecurringDirection => s === "income" || s === "payment" || s === "saving";

export default function RecurringPage() {
  const { t } = useTranslation("recurring");
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const router = useRouter();
  const params = useSearchParams();
  const items = useRecurringItems();
  const due = useDueItems();
  const [modal, setModal] = useState<ModalState | null>(null);

  useRegisterAddAction({
    type: "menu",
    label: t("payment"),
    items: [
      { key: "payment", label: t("payment"), icon: <PlusIcon size={17} />, onClick: () => setModal({ direction: "payment" }) },
      { key: "income", label: t("income"), icon: <PlusIcon size={17} />, onClick: () => setModal({ direction: "income" }) },
    ],
  }, [t]);
  const groupsByDir = useGroupsByDirection();

  // Seed the default groups on first visit. Idempotent and deterministic-id'd,
  // so two devices doing this at once produce identical rows (see groups.ts).
  useEffect(() => { void ensureDefaultGroups().catch(() => {}); }, []);

  // Open the modal from deep-link query params (add / edit / convert), once.
  useEffect(() => {
    const add = params.get("add");
    const editId = params.get("edit");
    if (isDir(add)) {
      const amountMinor = params.get("amount");
      const freq = params.get("freq");
      setModal({
        direction: add,
        prefill: {
          ...(params.get("name") ? { name: params.get("name")! } : {}),
          ...(amountMinor ? { amount: Number(amountMinor) } : {}),
          ...(freq ? { frequency: freq as Freq } : {}),
        },
        ...(params.get("convertFrom") ? { convertFrom: params.get("convertFrom")! } : {}),
      });
      router.replace("/recurring");
    } else if (editId) {
      const it = items.find((i) => i.ruleId === editId);
      if (it) { setModal({ direction: it.direction, edit: it }); router.replace("/recurring"); }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params, items.length]);

  const ungrouped = useMemo(() => items.filter((i) => !i.group_id), [items]);

  const summary = useRecurringSummary(items);

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1 style={{ margin: 0 }}>{t("title")}</h1>

      {/* Net monthly cashflow, with the two sides drawn to scale against each
          other. Everything is a MONTHLY equivalent (see summary.ts) so a weekly
          bill and a yearly subscription are comparable. */}
      <section className="card" style={{ padding: 18, display: "grid", gap: 14 }}>
        <div>
          <div className="eyebrow">{t("netMonthly", "Net monthly cashflow")}</div>
          <div className="tabular-nums" style={{
            fontSize: "clamp(28px, 7vw, 38px)", fontWeight: 750, letterSpacing: "-0.02em", marginTop: 2,
            color: summary.net >= 0 ? "var(--positive)" : "var(--negative)",
          }}>
            {summary.net >= 0 ? "+" : "−"}{fmt(money(Math.abs(summary.net), base))}
          </div>
        </div>

        <CashflowBar expense={summary.expense.monthly} income={summary.income.monthly} base={base} fmt={fmt} />

        <div style={{ display: "grid", gap: 10 }}>
          <DirectionCard
            href="/recurring/income"
            label={t("incomes", "Income")}
            amount={summary.income.monthly}
            sign="+"
            color="var(--positive)"
            count={summary.income.items.length}
            base={base}
            fmt={fmt}
          />
          <DirectionCard
            href="/recurring/expense"
            label={t("payments", "Expense")}
            amount={summary.expense.monthly}
            sign="−"
            color="var(--negative)"
            count={summary.expense.items.length}
            base={base}
            fmt={fmt}
          />
          {/* Savings only appear once there is one: they are transfers between
              your own accounts, so they sit outside the net figure above but
              must not become invisible. */}
          {summary.saving.items.length > 0 && (
            <DirectionCard
              href="/recurring/saving"
              label={t("savings", "Savings & SIPs")}
              amount={summary.saving.monthly}
              sign="→"
              color="var(--teal)"
              count={summary.saving.items.length}
              base={base}
              fmt={fmt}
            />
          )}
        </div>
      </section>

      {due.length > 0 && (
        <section className="card" style={{ padding: 16, display: "grid", gap: 10, borderColor: "var(--accent-soft)", background: "var(--accent-ghost)" }}>
          <strong style={{ fontSize: 14 }}>{t("dueNow")}</strong>
          {due.map((r) => (
            <div key={r.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
              <span style={{ fontSize: 14 }}>{r.template_name} <span className="muted" style={{ fontSize: 12 }}>· {t("dueOn", { date: r.next_due })}{r.amount != null ? ` · ${fmt(money(r.amount, r.currency ?? base))}` : ""}</span></span>
              <div style={{ display: "flex", gap: 8 }}>
                <button className="chip" onClick={() => void skipOnce(r.id)}>{t("skip")}</button>
                <button className="btn" style={{ padding: "4px 12px", fontSize: 13, minHeight: 0 }} onClick={() => void postOnce(r.id)}>{t("record")}</button>
              </div>
            </div>
          ))}
        </section>
      )}

      <TriageStrip items={ungrouped} groupsFor={(it) => groupsByDir[it.direction]} />

      {modal && (
        <RecurringModal
          direction={modal.direction}
          base={base}
          edit={modal.edit ?? null}
          prefill={modal.prefill ?? null}
          onClose={(saved) => {
            setModal(null);
          }}
        />
      )}
    </div>
  );
}

/**
 * Income vs expense drawn to scale against each other, so the balance is
 * legible before the numbers are read. Widths are shares of the COMBINED
 * total — the point is the ratio between the two bars, not either against some
 * fixed maximum.
 */
function CashflowBar({ expense, income, base, fmt }: {
  expense: number; income: number; base: string; fmt: (m: ReturnType<typeof money>) => string;
}) {
  const total = expense + income;
  if (total <= 0) return null;
  const expPct = (expense / total) * 100;
  return (
    <div>
      <div style={{ display: "flex", height: 34, borderRadius: 10, overflow: "hidden", border: "1px solid var(--border)" }}>
        {expense > 0 && (
          <div style={{
            width: `${expPct}%`, background: "color-mix(in srgb, var(--negative) 18%, transparent)",
            borderRight: "2px solid var(--negative)", display: "grid", placeItems: "center", minWidth: 0,
          }}>
            <span className="tabular-nums" style={{ fontSize: 12, fontWeight: 700, color: "var(--negative)", padding: "0 6px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
              −{fmt(money(expense, base))}
            </span>
          </div>
        )}
        {income > 0 && (
          <div style={{
            width: `${100 - expPct}%`, background: "color-mix(in srgb, var(--positive) 18%, transparent)",
            display: "grid", placeItems: "center", minWidth: 0,
          }}>
            <span className="tabular-nums" style={{ fontSize: 12, fontWeight: 700, color: "var(--positive)", padding: "0 6px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
              {fmt(money(income, base))}
            </span>
          </div>
        )}
      </div>
    </div>
  );
}

function DirectionCard({ href, label, amount, sign, color, count, base, fmt }: {
  href: string; label: string; amount: number; sign: string; color: string; count: number;
  base: string; fmt: (m: ReturnType<typeof money>) => string;
}) {
  return (
    <Link href={href} className="card press" style={{
      padding: "14px 16px", display: "flex", alignItems: "center", justifyContent: "space-between",
      gap: 12, background: "var(--surface-2)",
    }}>
      <span style={{ minWidth: 0 }}>
        <span style={{ display: "block", fontSize: 13.5, fontWeight: 650 }}>{label}</span>
        <span className="muted" style={{ fontSize: 12 }}>
          {count === 0 ? "Nothing yet" : `${count} item${count === 1 ? "" : "s"} · per month`}
        </span>
      </span>
      <span style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
        <span className="tabular-nums" style={{ fontSize: 19, fontWeight: 750, color }}>
          {sign}{fmt(money(amount, base))}
        </span>
        <span style={{ color: "var(--text-3)" }}>›</span>
      </span>
    </Link>
  );
}
