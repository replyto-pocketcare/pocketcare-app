"use client";

import { format, type Money as MoneyT } from "@pocketcare/money";
import { useAmountsHidden } from "../prefs";

/**
 * Renders a Money value, respecting the sitewide "hide amounts" privacy setting.
 * Use this everywhere an amount/balance is shown so masking is consistent.
 */
export function Money({ value, sign = "", locale = "en-US", mask = "••••" }: {
  value: MoneyT;
  /** Optional leading sign/prefix (e.g. "−", "+", "⇄ ") shown even when masked. */
  sign?: string;
  locale?: string;
  mask?: string;
}) {
  const hidden = useAmountsHidden();
  return <>{sign}{hidden ? mask : format(value, locale)}</>;
}

/**
 * Hook returning a masking money formatter — a drop-in for `format(m, "en-US")`
 * that respects the "hide amounts" setting. Works inside template strings too.
 */
export function useMoneyFmt(mask = "••••") {
  const hidden = useAmountsHidden();
  return (m: MoneyT, _locale = "en-US"): string => (hidden ? mask : format(m, "en-US"));
}
