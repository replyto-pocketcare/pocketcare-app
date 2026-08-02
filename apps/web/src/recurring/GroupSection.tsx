"use client";

/**
 * One section of /recurring (Income / Expenses / Savings) as a grid of group
 * cards. Plan: docs/plans/ui-redesign-2026-07.md §3.
 *
 * A card shows the group's monthly total and item count and expands IN PLACE to
 * its items — the same pattern as the /friends group tiles, so there's one way
 * to drill into a group in this app rather than two.
 */

import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { money } from "@sanvya/money";
import { monthlyEquivalent } from "@sanvya/finance";
import type { Period } from "@sanvya/types";
import { useConvert } from "../hooks";
import { useMoneyFmt } from "../ui/Money";
import { Modal } from "../ui/Modal";
import { MaterialIcon, type MaterialIconName } from "../ui/MaterialIcon";
import { KebabMenu } from "../ui/KebabMenu";
import { Pill, Field, EmiIcon } from "../loans/ui";
import { useConfirm } from "../ui/Confirm";
import type { RecurringItem, RecurringDirection } from "../cashflow/recurring";
import { createGroup, deleteGroup, type RecurringGroup } from "./groups";

const isIconName = (v: string | null): v is MaterialIconName => !!v;

export function GroupSection({ title, accent, direction, groups, items, base, onAdd, onEdit, onRemove, onPostNow }: {
  title: string;
  accent: string;
  direction: RecurringDirection;
  groups: RecurringGroup[];
  items: RecurringItem[];
  base: string;
  onAdd: () => void;
  onEdit: (it: RecurringItem) => void;
  onRemove: (it: RecurringItem) => void;
  onPostNow: (it: RecurringItem) => void;
}) {
  const { t } = useTranslation("recurring");
  const fmt = useMoneyFmt();
  const conv = useConvert();
  const [open, setOpen] = useState<string | null>(null);
  const [newOpen, setNewOpen] = useState(false);
  const [newName, setNewName] = useState("");
  const [deleting, setDeleting] = useState<RecurringGroup | null>(null);

  const byGroup = useMemo(() => {
    const m = new Map<string, RecurringItem[]>();
    for (const it of items) {
      if (!it.group_id) continue; // handled by the triage strip, not here
      const a = m.get(it.group_id) ?? [];
      a.push(it);
      m.set(it.group_id, a);
    }
    return m;
  }, [items]);

  const monthlyOf = (list: RecurringItem[]) =>
    list.reduce((s, it) => s + conv(money(monthlyEquivalent(it.amount, it.frequency as Period), it.currency || base)).amount, 0);

  const sectionTotal = monthlyOf(items.filter((i) => !!i.group_id));
  const sectionCount = items.filter((i) => !!i.group_id).length;

  return (
    <section style={{ display: "grid", gap: 10 }}>
      {/* Header row wraps: `.btn` is nowrap, and a non-shrinking button beside a
          flexible title collapses the title to one character per line. */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10, flexWrap: "wrap" }}>
        <h2 style={{ margin: 0, fontSize: 17, display: "flex", alignItems: "center", gap: 8, flex: "1 1 160px", minWidth: 0 }}>
          <span style={{ width: 8, height: 8, borderRadius: 999, background: accent, flexShrink: 0 }} />
          {title}
          <span className="muted" style={{ fontSize: 13, fontWeight: 400 }}>
            {t("itemCount", { count: sectionCount })}
          </span>
        </h2>
        <span style={{ fontSize: 14, fontWeight: 700, whiteSpace: "nowrap" }}>
          {fmt(money(sectionTotal, base))}<span className="muted" style={{ fontWeight: 400 }}>{t("perMonth")}</span>
        </span>
      </div>

      <div className="list-grid">
        {groups.map((g) => {
          const list = byGroup.get(g.id) ?? [];
          const isOpen = open === g.id;
          return (
            <div key={g.id} className="card" style={{ padding: 0, overflow: "hidden", gridColumn: isOpen ? "1 / -1" : "auto" }}>
              <button
                aria-expanded={isOpen}
                onClick={() => setOpen(isOpen ? null : g.id)}
                style={{ width: "100%", background: "none", border: "none", cursor: "pointer", padding: 14, display: "grid", gap: 10, textAlign: "left", color: "inherit" }}
              >
                <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10 }}>
                  <span style={{ display: "inline-flex", alignItems: "center", gap: 8, minWidth: 0 }}>
                    <span style={{ width: 34, height: 34, borderRadius: 10, flexShrink: 0, background: "var(--surface-2)", color: accent, display: "grid", placeItems: "center" }}>
                      <MaterialIcon name={isIconName(g.icon) ? (g.icon as MaterialIconName) : "folder"} size={19} />
                    </span>
                    <span style={{ fontWeight: 650, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{g.name}</span>
                  </span>
                  <MaterialIcon name="expand_more" size={18} style={{ transform: isOpen ? "rotate(180deg)" : undefined, transition: "transform .15s", opacity: 0.6 }} />
                </div>
                <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 10 }}>
                  <span className="muted" style={{ fontSize: 12.5 }}>{t("itemCount", { count: list.length })}</span>
                  <span style={{ fontWeight: 700, fontSize: 15, whiteSpace: "nowrap" }}>
                    {fmt(money(monthlyOf(list), base))}<span className="muted" style={{ fontWeight: 400, fontSize: 12 }}>{t("perMonth")}</span>
                  </span>
                </div>
              </button>

              {isOpen && (
                <div style={{ padding: "0 14px 14px", display: "grid", gap: 8, borderTop: "1px solid var(--border)" }}>
                  {list.length === 0 ? (
                    <p className="muted" style={{ fontSize: 13, margin: "12px 0 0" }}>{t("groupEmpty")}</p>
                  ) : (
                    <div style={{ display: "grid", gap: 8, marginTop: 12 }}>
                      {list.map((it) => (
                        <ItemRow key={it.ruleId} item={it} base={base} onEdit={() => onEdit(it)} onRemove={() => onRemove(it)} onPostNow={() => onPostNow(it)} />
                      ))}
                    </div>
                  )}
                  <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 4 }}>
                    <button className="chip" onClick={onAdd}>+ {t("add")}</button>
                    <button className="chip" onClick={() => setDeleting(g)}>{t("groupDelete")}</button>
                  </div>
                </div>
              )}
            </div>
          );
        })}

        <button
          className="card lift"
          onClick={() => { setNewName(""); setNewOpen(true); }}
          style={{ padding: 14, cursor: "pointer", display: "grid", placeItems: "center", gap: 6, minHeight: 96, border: "1px dashed var(--border-strong)", background: "transparent", color: "var(--text-2)" }}
        >
          <MaterialIcon name="add" size={22} />
          <span style={{ fontSize: 13, fontWeight: 600 }}>{t("groupNewCta")}</span>
        </button>
      </div>

      <Modal open={newOpen} onClose={() => setNewOpen(false)} label={t("groupNewCta")}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>{t("groupNewCta")}</h2>
          <input className="input" autoFocus value={newName} onChange={(e) => setNewName(e.target.value)} placeholder={t("groupNewEg")} />
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
            <button className="btn ghost" onClick={() => setNewOpen(false)}>{t("cancel")}</button>
            <button className="btn" disabled={!newName.trim()} onClick={async () => { await createGroup({ name: newName, direction }); setNewOpen(false); }}>
              {t("create")}
            </button>
          </div>
        </div>
      </Modal>

      {deleting && (
        <DeleteGroupDialog
          group={deleting}
          itemCount={(byGroup.get(deleting.id) ?? []).length}
          others={groups.filter((g) => g.id !== deleting.id)}
          onClose={() => setDeleting(null)}
        />
      )}
    </section>
  );
}

/**
 * Deleting a group must never strand its items. When the group has any, a
 * destination is REQUIRED — there is no "delete anyway".
 */
function DeleteGroupDialog({ group, itemCount, others, onClose }: {
  group: RecurringGroup; itemCount: number; others: RecurringGroup[]; onClose: () => void;
}) {
  const { t } = useTranslation("recurring");
  const [moveTo, setMoveTo] = useState(others[0]?.id ?? "");
  const [busy, setBusy] = useState(false);
  const needsDestination = itemCount > 0;
  const canDelete = !needsDestination || !!moveTo;

  return (
    <Modal open onClose={onClose} label={t("groupDelete")}>
      <div style={{ display: "grid", gap: 12 }}>
        <h2 style={{ margin: 0 }}>{t("groupDeleteTitle", { name: group.name })}</h2>
        {needsDestination ? (
          <>
            <p className="muted" style={{ margin: 0, fontSize: 13.5 }}>{t("groupDeleteMove", { count: itemCount })}</p>
            {others.length === 0 ? (
              // The last group in a section can only go once it's empty —
              // otherwise its items would have nowhere to land.
              <p style={{ margin: 0, fontSize: 13.5, color: "var(--negative)" }}>{t("groupDeleteLast")}</p>
            ) : (
              <select className="input" value={moveTo} onChange={(e) => setMoveTo(e.target.value)}>
                {others.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
              </select>
            )}
          </>
        ) : (
          <p className="muted" style={{ margin: 0, fontSize: 13.5 }}>{t("groupDeleteEmpty")}</p>
        )}
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
          <button className="btn ghost" onClick={onClose}>{t("cancel")}</button>
          <button
            className="btn"
            disabled={busy || !canDelete || (needsDestination && others.length === 0)}
            onClick={async () => {
              setBusy(true);
              try { await deleteGroup(group.id, needsDestination ? moveTo : null); onClose(); }
              finally { setBusy(false); }
            }}
          >
            {t("remove")}
          </button>
        </div>
      </div>
    </Modal>
  );
}

/**
 * One recurring item, in the EMI card language from `src/loans/ui.tsx`:
 * status icon + title + pill on top, a divided two-column footer below.
 *
 * The previous version put the name, cadence, amount, monthly equivalent and
 * three action chips in a single flex row — far more than fits a group card on
 * a phone, so it overflowed and read as noise. Actions now live in a kebab,
 * and the two numbers get their own labelled footer fields.
 */
function ItemRow({ item, base, onEdit, onRemove, onPostNow }: {
  item: RecurringItem; base: string; onEdit: () => void; onRemove: () => void; onPostNow: () => void;
}) {
  const { t } = useTranslation("recurring");
  const fmt = useMoneyFmt();
  const conv = useConvert();
  const confirm = useConfirm();
  const monthly = monthlyEquivalent(item.amount, item.frequency as Period);
  const cur = item.currency || base;

  const today = new Date().toISOString().slice(0, 10);
  const isDue = !!item.next_due && item.next_due <= today;
  const nextDue = item.next_due
    ? new Date(item.next_due + "T00:00:00").toLocaleDateString(undefined, { day: "numeric", month: "short", year: "2-digit" })
    : "—";

  return (
    <div className="card" style={{ padding: 0, overflow: "hidden", borderColor: isDue ? "var(--accent-soft)" : undefined }}>
      <div style={{ padding: "11px 13px", display: "flex", alignItems: "center", gap: 10, background: isDue ? "var(--accent-ghost)" : "transparent" }}>
        <EmiIcon state={isDue ? "due" : "idle"} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 650, fontSize: 14.5, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{item.name}</div>
          <div className="muted" style={{ fontSize: 11.5 }}>{t(`freq.${item.frequency}`, item.frequency)}</div>
        </div>
        <div style={{ display: "grid", gap: 3, justifyItems: "end", flexShrink: 0 }}>
          <Pill tone={item.auto_post ? "positive" : "muted"}>
            {item.auto_post ? t("autoPosts") : t("confirm")}
          </Pill>
          <span className="muted" style={{ fontSize: 11, whiteSpace: "nowrap" }}>{t("next", { date: nextDue })}</span>
        </div>
        <KebabMenu
          label={t("actions", { name: item.name })}
          items={[
            { label: t("postNow"), onClick: onPostNow },
            { label: t("edit"), onClick: onEdit },
            {
              label: t("remove"),
              danger: true,
              onClick: async () => {
                if (await confirm({ title: t("removeTitle"), message: t("removeMsg", { name: item.name }), confirmLabel: t("remove") })) onRemove();
              },
            },
          ]}
        />
      </div>
      <div style={{ borderTop: "1px solid var(--border)", padding: "9px 13px", display: "flex", justifyContent: "space-between", gap: 12 }}>
        <Field label={t("amountLabel", "Amount")} value={fmt(conv(money(item.amount, cur)))} />
        <Field label={t("perMonthLabel", "Per month")} align="right" value={fmt(conv(money(monthly, cur)))} />
      </div>
    </div>
  );
}
