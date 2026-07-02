"use client";

import type { CSSProperties } from "react";

/** Text/number input whose label floats to the top once filled, so the hint
 *  stays visible after you type. */
export function FloatingInput({
  label, value, onChange, type = "text", inputMode, style, multiline, rows,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
  inputMode?: "decimal" | "numeric" | "text" | "email";
  style?: CSSProperties;
  multiline?: boolean;
  rows?: number;
}) {
  return (
    <div className="floating" style={style}>
      {multiline ? (
        <textarea placeholder=" " rows={rows ?? 2} value={value} onChange={(e) => onChange(e.target.value)} style={{ resize: "vertical" }} />
      ) : (
        <input placeholder=" " type={type} inputMode={inputMode} value={value} onChange={(e) => onChange(e.target.value)} />
      )}
      <label>{label}</label>
    </div>
  );
}
