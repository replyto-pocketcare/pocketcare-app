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
import { useRecurringItems, removeRecurring, type RecurringItem, type RecurringDirection } from "../../src/cashflow/recurring";
import { useGroupsByDirection, ensureDefaultGroups } from "../../src/recurring/groups";
import { GroupSection } from "../../src/recurring/GroupSection";
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

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <div>
          <h1 style={{ margin: 0 }}>{t("title")}</h1>
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
                <button className="chip" onClick={() => void skipOnce(r.id)}>{t("skip")}</button>
                <button className="btn" style={{ padding: "4px 12px", fontSize: 13, minHeight: 0 }} onClick={() => void postOnce(r.id)}>{t("record")}</button>
              </div>
            </div>
          ))}
        </section>
      )}

      {/* Legacy items with no group — a one-time prompt, not a permanent bucket. */}
      <TriageStrip
        items={ungrouped}
        groupsFor={(it) => groupsByDir[it.direction]}
      />

      {(["income", "payment", "saving"] as const).map((dir) => (
        <GroupSection
          key={dir}
          direction={dir}
          title={dir === "income" ? t("incomes") : dir === "payment" ? t("payments") : t("savings")}
          accent={dir === "income" ? "var(--positive)" : dir === "payment" ? "var(--negative)" : "var(--teal)"}
          groups={groupsByDir[dir]}
          items={items.filter((i) => i.direction === dir)}
          base={base}
          onAdd={() => setModal({ direction: dir })}
          onEdit={(it) => setModal({ direction: dir, edit: it })}
          onRemove={(it) => removeRecurring(it.ruleId, it.templateId)}
          onPostNow={(it) => void postOnce(it.ruleId)}
        />
      ))}

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
