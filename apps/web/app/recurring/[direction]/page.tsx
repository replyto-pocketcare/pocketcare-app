"use client";

/**
 * One side of the recurring picture: Income or Expense.
 *
 * There is no `saving` slug. Recurring savings are SIPs, and a SIP belongs to
 * the holding it funds — it is created and stopped in Investments, not here.
 *
 * Route segment is the USER-facing word ("expense"), not the stored direction
 * ("payment") — the URL is part of the interface, and /recurring/payment would
 * read oddly next to a screen titled Expense. The mapping lives here and
 * nowhere else.
 */
import { useMemo, useState } from "react";
import { notFound, useParams } from "next/navigation";
import { useTranslation } from "react-i18next";
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from "recharts";
import { money } from "@sanvya/money";
import { useBaseCurrency } from "../../../src/hooks";
import { useMoneyFmt } from "../../../src/ui/Money";
import { colorForId } from "../../../src/colors";
import { useRegisterAddAction } from "../../../src/ui/AddAction";
import { PlusIcon } from "../../../src/ui/icons";
import { useRecurringItems, removeRecurring, type RecurringItem, type RecurringDirection } from "../../../src/cashflow/recurring";
import { useCategoryNames, summarise } from "../../../src/recurring/summary";
import { RecurringModal } from "../../../src/cashflow/RecurringModal";
import { postOnce } from "../../../src/recurring/engine";
import { KebabMenu } from "../../../src/ui/KebabMenu";
import { useConfirm } from "../../../src/ui/Confirm";

const SLUGS: Record<string, { direction: RecurringDirection; title: string; sign: string; color: string }> = {
  income:  { direction: "income",  title: "Income",  sign: "+", color: "var(--positive)" },
  expense: { direction: "payment", title: "Expense", sign: "−", color: "var(--negative)" },
};

export default function RecurringDirectionPage() {
  const params = useParams<{ direction: string }>();
  const slug = SLUGS[params.direction ?? ""];
  if (!slug) notFound();

  const { t } = useTranslation("recurring");
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const confirm = useConfirm();
  const items = useRecurringItems();
  const catNames = useCategoryNames();
  const [modal, setModal] = useState<{ edit?: RecurringItem } | null>(null);

  const summary = useMemo(
    () => summarise(items, slug.direction, catNames),
    [items, slug.direction, catNames],
  );

  useRegisterAddAction(
    { type: "button", label: `Add ${slug.title}`, onClick: () => setModal({}) },
    [slug.direction],
  );

  return (
    <div style={{ display: "grid", gap: 18 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>{slug.title}</h1>
        <button className="btn" onClick={() => setModal({})} style={{ gap: 6 }}>
          <PlusIcon size={16} /> {t("add", "Add")}
        </button>
      </div>

      <section className="card" style={{ padding: 18, display: "flex", alignItems: "center", gap: 18, flexWrap: "wrap" }}>
        <div style={{ minWidth: 0 }}>
          <div className="eyebrow">{t("perMonth", "Per month")}</div>
          <div className="tabular-nums" style={{ fontSize: "clamp(26px, 6.5vw, 34px)", fontWeight: 750, color: slug.color, marginTop: 2 }}>
            {slug.sign}{fmt(money(summary.monthly, base))}
          </div>
        </div>

        {/* Category mix. Only earns its space once there's more than one slice —
            a donut of a single category is decoration, not information. */}
        {summary.categories.length > 1 && (
          <div style={{ width: 132, height: 132, flexShrink: 0, marginLeft: "auto" }}>
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie data={summary.categories} dataKey="monthly" nameKey="name" innerRadius={38} outerRadius={62} paddingAngle={2} strokeWidth={0}>
                  {summary.categories.map((c) => <Cell key={c.id} fill={colorForId(c.id)} />)}
                </Pie>
                <Tooltip
                  formatter={(v: number, n: string) => [fmt(money(Math.round(v), base)), n]}
                  contentStyle={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 10, fontSize: 12 }}
                />
              </PieChart>
            </ResponsiveContainer>
          </div>
        )}
      </section>

      {summary.categories.length > 1 && (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
          {summary.categories.map((c) => (
            <span key={c.id} className="chip" style={{ display: "inline-flex", alignItems: "center", gap: 6, cursor: "default" }}>
              <span style={{ width: 9, height: 9, borderRadius: 999, background: colorForId(c.id) }} />
              {c.name}
              <span className="muted tabular-nums">{Math.round(c.share * 100)}%</span>
            </span>
          ))}
        </div>
      )}

      {summary.items.length === 0 ? (
        <p className="muted" style={{ fontSize: 13.5, lineHeight: 1.6 }}>
          {t("emptyDirection", "Nothing recurring here yet. Add one and it'll post itself on schedule.")}
        </p>
      ) : (
        <div style={{ display: "grid", gap: 10 }}>
          {summary.items.map((it) => (
            <div key={it.ruleId} className="card" style={{ padding: "12px 14px", display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
              <span style={{ minWidth: 0 }}>
                <span style={{ display: "block", fontSize: 14, fontWeight: 650, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{it.name}</span>
                <span className="muted" style={{ fontSize: 12 }}>
                  {t(`freq.${it.frequency}`, it.frequency)}
                  {it.category_id ? ` · ${catNames.get(it.category_id) ?? ""}` : ""}
                  {it.next_due ? ` · ${t("dueOn", { date: it.next_due })}` : ""}
                </span>
              </span>
              <span style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
                <span className="tabular-nums" style={{ fontSize: 15, fontWeight: 700, color: slug.color }}>
                  {slug.sign}{fmt(money(it.amount, it.currency || base))}
                </span>
                <KebabMenu
                  items={[
                    { label: t("edit", "Edit"), onClick: () => setModal({ edit: it }) },
                    { label: t("record", "Record now"), onClick: () => void postOnce(it.ruleId) },
                    {
                      label: t("remove", "Remove"), danger: true,
                      onClick: async () => {
                        if (await confirm({ title: t("removeItemTitle", "Remove this?"), message: it.name, confirmLabel: t("remove", "Remove") })) {
                          await removeRecurring(it.ruleId);
                        }
                      },
                    },
                  ]}
                />
              </span>
            </div>
          ))}
        </div>
      )}

      {modal && (
        <RecurringModal
          direction={slug.direction}
          base={base}
          edit={modal.edit ?? null}
          onClose={() => setModal(null)}
        />
      )}
    </div>
  );
}
