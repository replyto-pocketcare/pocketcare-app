"use client";

/**
 * The per-item breakdown of an itemized bill.
 *
 * Read-only by design: editing a split after the fact means rewriting ledger
 * postings, which is the edit-transaction flow's job. This exists to answer
 * "why do I owe this much?", which is the question people actually ask after
 * a group dinner.
 */
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { money } from "@pocketcare/money";
import { qtyToMajor } from "@pocketcare/receipts";

import { useMoneyFmt } from "../ui/Money";
import { useExpenseItems, useItemShareMap, useMyUserId, useUserProfiles } from "./hooks";

export function ItemBreakdown({
  expenseId,
  currency,
  /** Restrict to one person's lines. Defaults to showing everyone. */
  defaultUserId,
}: {
  expenseId: string;
  currency: string;
  defaultUserId?: string;
}) {
  const { t } = useTranslation("receipts");
  const fmt = useMoneyFmt();
  const me = useMyUserId();
  const profiles = useUserProfiles();
  const items = useExpenseItems(expenseId);
  const shareMap = useItemShareMap(expenseId);
  const [filter, setFilter] = useState<string>(defaultUserId ?? "");

  if (items.length === 0) return null;

  const everyone = [...new Set([...shareMap.values()].flatMap((m) => [...m.keys()]))];
  const nameOf = (id: string) => (id === me ? t("split.you", "You") : profiles.get(id)?.name ?? t("split.someone", "Member"));

  const visible = filter
    ? items.filter((i) => (shareMap.get(i.id)?.get(filter) ?? 0) !== 0)
    : items;

  const shown = (itemId: string, amount: number) =>
    filter ? shareMap.get(itemId)?.get(filter) ?? 0 : amount;

  const total = visible.reduce((s, i) => s + shown(i.id, i.amount), 0);
  const cur = currency as Parameters<typeof money>[1];

  return (
    <div style={{ display: "grid", gap: 10, minWidth: 0 }}>
      {everyone.length > 1 && (
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          <button className="chip" type="button" data-active={filter === ""} onClick={() => setFilter("")}>
            {t("breakdown.everyone", "Everyone")}
          </button>
          {everyone.map((uid) => (
            <button key={uid} className="chip" type="button" data-active={filter === uid} onClick={() => setFilter(uid)}>
              {nameOf(uid)}
            </button>
          ))}
        </div>
      )}

      <div style={{ overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13.5, minWidth: 360 }}>
          <tbody>
            {visible.map((item) => {
              const shares = shareMap.get(item.id);
              return (
                <tr key={item.id} style={{ borderTop: "1px solid var(--border)" }}>
                  <td style={{ padding: "8px 4px", minWidth: 0 }}>
                    <div style={{ display: "flex", gap: 6, alignItems: "baseline", flexWrap: "wrap" }}>
                      <span>{item.description || t(`kind.${item.kind}`, item.kind)}</span>
                      {item.kind !== "item" && (
                        <span className="chip" style={{ fontSize: 10.5 }}>{t(`kind.${item.kind}`, item.kind)}</span>
                      )}
                      {item.quantity !== null && (
                        <span className="muted" style={{ fontSize: 11.5 }}>
                          {qtyToMajor(item.quantity)}{item.unit ? ` ${item.unit}` : "×"}
                        </span>
                      )}
                    </div>
                    {!filter && shares && shares.size > 0 && (
                      <div className="muted" style={{ fontSize: 11.5, marginTop: 2 }}>
                        {[...shares.entries()]
                          .filter(([, amt]) => amt !== 0)
                          .map(([uid, amt]) => `${nameOf(uid)} ${fmt(money(amt, cur))}`)
                          .join(" · ")}
                      </div>
                    )}
                  </td>
                  <td style={{ padding: "8px 4px", textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
                    {fmt(money(shown(item.id, item.amount), cur))}
                  </td>
                </tr>
              );
            })}
          </tbody>
          <tfoot>
            <tr style={{ borderTop: "2px solid var(--border)", fontWeight: 700 }}>
              <td style={{ padding: "8px 4px" }}>
                {filter ? t("breakdown.personTotal", "{{name}} owes", { name: nameOf(filter) }) : t("split.total", "Total")}
              </td>
              <td style={{ padding: "8px 4px", textAlign: "right", fontVariantNumeric: "tabular-nums" }}>
                {fmt(money(total, cur))}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
}
