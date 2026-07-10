import type { ChangeEvent } from "react";

/** Keep digits + a single decimal point. */
export function sanitizeAmount(s: string): string {
  let out = s.replace(/[^0-9.]/g, "");
  const i = out.indexOf(".");
  if (i >= 0) out = out.slice(0, i + 1) + out.slice(i + 1).replace(/\./g, "");
  return out;
}

// Currencies that use the Indian numbering system (…,00,000 — lakh/crore).
const INDIAN_CCY = new Set(["INR", "PKR", "LKR", "BDT", "NPR"]);

function groupInt(int: string, indian: boolean): string {
  if (int.length <= 3) return int;
  if (!indian) return int.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  const last3 = int.slice(-3);
  const rest = int.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ",");
  return `${rest},${last3}`;
}

/**
 * Add locale-appropriate grouping to the integer part, preserving the decimal.
 * INR (and other South-Asian currencies) use lakh/crore grouping (1,00,000).
 */
export function groupAmount(raw: string, currency?: string): string {
  if (!raw) return "";
  const dot = raw.indexOf(".");
  const int = dot >= 0 ? raw.slice(0, dot) : raw;
  const dec = dot >= 0 ? raw.slice(dot) : "";
  return groupInt(int, !!currency && INDIAN_CCY.has(currency.toUpperCase())) + dec;
}

/**
 * onChange handler for a grouped amount field: emits the raw (unformatted) value
 * and restores the caret to the correct digit position after re-grouping.
 */
export function onGroupedInput(e: ChangeEvent<HTMLInputElement>, onChange: (raw: string) => void, currency?: string): void {
  const el = e.target;
  const caret = el.selectionStart ?? el.value.length;
  const digitsBefore = (el.value.slice(0, caret).match(/\d/g) ?? []).length;
  const raw = sanitizeAmount(el.value);
  onChange(raw);
  const formatted = groupAmount(raw, currency);
  let pos = 0, seen = 0;
  while (pos < formatted.length && seen < digitsBefore) { if (/\d/.test(formatted[pos]!)) seen++; pos++; }
  requestAnimationFrame(() => { try { el.setSelectionRange(pos, pos); } catch { /* ignore */ } });
}
