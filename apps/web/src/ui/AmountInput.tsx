"use client";

import type { CSSProperties } from "react";
import { groupAmount, onGroupedInput } from "./amountFormat";

/** A plain `.input` that shows thousand separators live while storing the raw value. */
export function AmountInput({
  value, onChange, placeholder, style, ariaLabel, autoFocus,
}: {
  value: string;
  onChange: (raw: string) => void;
  placeholder?: string;
  style?: CSSProperties;
  ariaLabel?: string;
  autoFocus?: boolean;
}) {
  return (
    <input
      className="input"
      inputMode="decimal"
      aria-label={ariaLabel}
      placeholder={placeholder}
      autoFocus={autoFocus}
      value={groupAmount(value)}
      onChange={(e) => onGroupedInput(e, onChange)}
      style={style}
    />
  );
}
