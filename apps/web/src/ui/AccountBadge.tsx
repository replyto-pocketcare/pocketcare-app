"use client";

import { colorForId } from "../colors";

export const TYPE_CODE: Record<string, string> = {
  savings: "SV", current: "CU", credit_card: "CC", cash: "$", mutual_funds: "MF", stocks: "ST",
};
export const TYPE_LABEL: Record<string, string> = {
  savings: "Savings", current: "Current", credit_card: "Credit Card", cash: "Cash", mutual_funds: "Mutual Funds", stocks: "Stocks",
};

/** Compact account-type badge: account color + 2-char type code, with tooltip. */
export function AccountBadge({ type, color, id, name }: { type: string; color?: string | null; id?: string; name?: string | undefined }) {
  const c = color || colorForId(id);
  const code = TYPE_CODE[type] ?? "•";
  const title = `${name ? name + " · " : ""}${TYPE_LABEL[type] ?? type}`;
  return (
    <span title={title}
      style={{ minWidth: 26, height: 22, padding: "0 5px", borderRadius: 7, background: `${c}1f`, border: `1px solid ${c}`, color: c, fontSize: 10.5, fontWeight: 700, display: "inline-flex", alignItems: "center", justifyContent: "center", flexShrink: 0, letterSpacing: "0.02em" }}>
      {code}
    </span>
  );
}
