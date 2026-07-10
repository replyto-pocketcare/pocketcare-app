import type { ChangeEvent } from "react";

/** Keep digits + a single decimal point. */
export function sanitizeAmount(s: string): string {
  let out = s.replace(/[^0-9.]/g, "");
  const i = out.indexOf(".");
  if (i >= 0) out = out.slice(0, i + 1) + out.slice(i + 1).replace(/\./g, "");
  return out;
}

/** Add thousand separators to the integer part, preserving a trailing/decimal part. */
export function groupAmount(raw: string): string {
  if (!raw) return "";
  const dot = raw.indexOf(".");
  const int = dot >= 0 ? raw.slice(0, dot) : raw;
  const dec = dot >= 0 ? raw.slice(dot) : "";
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return grouped + dec;
}

/**
 * onChange handler for a grouped amount field: emits the raw (unformatted) value
 * and restores the caret to the correct digit position after re-grouping.
 */
export function onGroupedInput(e: ChangeEvent<HTMLInputElement>, onChange: (raw: string) => void): void {
  const el = e.target;
  const caret = el.selectionStart ?? el.value.length;
  const digitsBefore = (el.value.slice(0, caret).match(/\d/g) ?? []).length;
  const raw = sanitizeAmount(el.value);
  onChange(raw);
  const formatted = groupAmount(raw);
  let pos = 0, seen = 0;
  while (pos < formatted.length && seen < digitsBefore) { if (/\d/.test(formatted[pos]!)) seen++; pos++; }
  requestAnimationFrame(() => { try { el.setSelectionRange(pos, pos); } catch { /* ignore */ } });
}
