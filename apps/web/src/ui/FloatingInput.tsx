"use client";

import type { CSSProperties } from "react";
import { groupAmount, onGroupedInput } from "./amountFormat";

/** Text/number input whose label floats to the top once filled, so the hint
 *  stays visible after you type. Pass `group` for live thousand separators on
 *  amount fields (emits the raw unformatted value). */
export function FloatingInput({
  label, value, onChange, type = "text", inputMode, style, multiline, rows, group, currency,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
  inputMode?: "decimal" | "numeric" | "text" | "email";
  style?: CSSProperties;
  multiline?: boolean;
  rows?: number;
  group?: boolean;
  currency?: string;
}) {
  return (
    <div className="floating" style={style}>
      {multiline ? (
        <textarea placeholder=" " rows={rows ?? 2} value={value} onChange={(e) => onChange(e.target.value)} style={{ resize: "vertical" }} />
      ) : group ? (
        <input placeholder=" " inputMode="decimal" value={groupAmount(value, currency)} onChange={(e) => onGroupedInput(e, onChange, currency)} />
      ) : (
        <input placeholder=" " type={type} inputMode={inputMode} value={value} onChange={(e) => onChange(e.target.value)} />
      )}
      <label>{label}</label>
    </div>
  );
}
