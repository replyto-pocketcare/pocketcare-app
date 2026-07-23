"use client";

/**
 * Recurring payments & incomes — a dedicated home for salary, rent, bills and
 * other regular money in/out. Each item is a real recurring rule (template +
 * rule) that posts transactions. Opened directly, or deep-linked from Planned
 * Cashflow's "Add income / Add payment" (and quick-add / convert) via query
 * params: ?add=income|payment|saving [&name=&amount=<minor>&freq=&convertFrom=<plannedId>]
 * or ?edit=<ruleId>.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { useRouter, useSearchParams } from "next/navigation";
import { money } from "@pocketcare/money";
import { monthlyEquivalent } from "@pocketcare/finance";
import type { Period } from "@pocketcare/types";
import { useBaseCurrency, useConvert } from "../../src/hooks";
import { useMoneyFmt } from "../../src/ui/Money";
import { KebabMenu } from "../../src/ui/KebabMenu";
import { useConfirm } from "../../src/ui/Confirm";
import { softDelete } from "../../src/write";
import { useRecurringItems, removeRecurring, type RecurringItem, type RecurringDirection } from "../../src/cashflow/recurring";
import { RecurringModal } from "../../src/cashflow/RecurringModal";
import { useDueRules } from "../../src/templates/hooks";
import { postRuleOnce, skipRuleOnce, type Freq } from "../../src/templates/write";

interface ModalState { direction: RecurringDirection; edit?: RecurringItem; prefill?: { name?: string; amount?: number; frequency?: Freq }; convertFrom?: string }
const isDir = (s: string | null): s is RecurringDirection => s === "income" || s === "payment" || s === "saving";

export default function RecurringPage() {
  const { t } = useTranslation("recurring");
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const router = useRouter();
  const params = useSearchParams();
  const items = useRecurringItems();
  const due = useDueRules();
  const [modal, setModal] = useState<ModalState | null>(null);

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

  const incomes = items.filter((i) => i.direction === "income");
  const payments = items.filter((i) => i.direction === "payment");
  const savings = items.filter((i) => i.direction === "saving");

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <div>
          <h1 style={{ margin: 0 }}>{t("title")}</h1>
          <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>{t("subtitlePre")}<Link href="/cashflow">{t("subtitleLink")}</Link>.</p>
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <button className="btn ghost" onClick={() => setModal({ direction: "income" })}>+ {t("income")}</button>
          <button className="btn" onClick={() => setModal({ direction: "payment" })}>+ {t("payment")}</button>
        </div>
      </div>

      {due.length > 0 && (
        <section className="card" style={{ padding: 16, display: "grid", gap: 10, borderColor: "var(--accent-soft)", background: "var(--accent-ghost)" }}>
          <strong style={{ fontSize: 14 }}>{t("dueNow")}</strong>
          {due.map((r) => (
            <div key={r.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
              <span style={{ fontSize: 14 }}>{r.template_name} <span className="muted" style={{ fontSize: 12 }}>· {t("dueOn", { date: r.next_due })}{r.amount != null ? ` · ${fmt(money(r.amount, r.currency ?? base))}` : ""}</span></span>
              <div style={{ display: "flex", gap: 8 }}>
                <button className="chip" onClick={() => void skipRuleOnce(r.id)}>{t("skip")}</button>
                <button className="btn" style={{ padding: "4px 12px", fontSize: 13, minHeight: 0 }} onClick={() => void postRuleOnce(r.id)}>{t("record")}</button>
              </div>
            </div>
          ))}
        </section>
      )}

      <RecurringSection title={t("incomes")} accent="var(--positive)" items={incomes} base={base} emptyLabel={t("emptyIncome")}
        onAdd={() => setModal({ direction: "income" })} onEdit={(it) => setModal({ direction: "income", edit: it })} />
      <RecurringSection title={t("payments")} accent="var(--negative)" items={payments} base={base} emptyLabel={t("emptyPayment")}
        onAdd={() => setModal({ direction: "payment" })} onEdit={(it) => setModal({ direction: "payment", edit: it })} />
      <RecurringSection title={t("savings")} accent="var(--teal)" items={savings} base={base} emptyLabel={t("emptySaving")}
        onAdd={() => setModal({ direction: "saving" })} onEdit={(it) => setModal({ direction: "saving", edit: it })} />

      {modal && (
        <RecurringModal
          direction={modal.direction}
          base={base}
          edit={modal.edit ?? null}
          prefill={modal.prefill ?? null}
          onClose={(saved) => {
            if (saved && modal.convertFrom) softDelete("planned_cashflow", modal.convertFrom);
            setModal(null);
          }}
        />
      )}
    </div>
  );
}

function RecurringSection({ title, accent, items, base, emptyLabel, onAdd, onEdit }: {
  title: string; accent: string; items: RecurringItem[]; base: string; emptyLabel: string;
  onAdd: () => void; onEdit: (it: RecurringItem) => void;
}) {
  const { t } = useTranslation("recurring");
  return (
    <section style={{ display: "grid", gap: 8 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h2 style={{ margin: 0, fontSize: 17, display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ width: 8, height: 8, borderRadius: 999, background: accent }} />{title}
          <span className="muted" style={{ fontSize: 13, fontWeight: 400 }}>{items.length}</span>
        </h2>
        <button className="chip" onClick={onAdd}>+ {t("add")}</button>
      </div>
      {items.length === 0 ? (
        <p className="muted" style={{ fontSize: 13, margin: 0 }}>{emptyLabel}</p>
      ) : (
        <div className="list-grid">
          {items.map((it) => <RecurringRow key={it.ruleId} item={it} base={base} onEdit={() => onEdit(it)} />)}
        </div>
      )}
    </section>
  );
}

function RecurringRow({ item, base, onEdit }: { item: RecurringItem; base: string; onEdit: () => void }) {
  const { t } = useTranslation("recurring");
  const fmt = useMoneyFmt();
  const conv = useConvert();
  const confirm = useConfirm();
  const monthly = monthlyEquivalent(item.amount, item.frequency as Period);
  const cur = item.currency || base;
  const nextDue = item.next_due ? new Date(item.next_due + "T00:00:00").toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" }) : "—";
  return (
    <div className="card lift" style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "12px 14px" }}>
      <div style={{ minWidth: 0 }}>
        <div style={{ fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{item.name}</div>
        <div className="muted" style={{ fontSize: 12 }}>{t(`freq.${item.frequency}`, item.frequency)} · {t("next", { date: nextDue })} · {item.auto_post ? t("autoPosts") : t("confirm")}</div>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 10, flexShrink: 0 }}>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontWeight: 650, fontSize: 14 }}>{fmt(conv(money(item.amount, cur)))}</div>
          <div className="muted" style={{ fontSize: 11 }}>{fmt(conv(money(monthly, cur)))}{t("perMonth")}</div>
        </div>
        <KebabMenu label={t("actions", { name: item.name })} items={[
          { label: t("postNow"), onClick: () => void postRuleOnce(item.ruleId) },
          { label: t("edit"), onClick: onEdit },
          { label: t("remove"), danger: true, onClick: async () => { if (await confirm({ title: t("removeTitle"), message: t("removeMsg", { name: item.name }), confirmLabel: t("remove") })) removeRecurring(item.ruleId, item.templateId); } },
        ]} />
      </div>
    </div>
  );
}
