"use client";

/**
 * The canonical transaction tile — one look everywhere a transaction is listed
 * (Transactions, Search, Statements, the dashboard's Recent activity).
 *
 * The design comes from the Statements page, which was the nicest of the three
 * competing row implementations this replaces:
 *   - a coloured avatar carrying the merchant's initial, so a list scans by
 *     shape and colour rather than by reading every line;
 *   - a merchant name pulled out of the bank/UPI narration, with the full
 *     narration WRAPPING underneath instead of being truncated — a UPI string
 *     ellipsised at 40 chars is unreadable, and truncation is exactly what made
 *     the old rows hard to scan;
 *   - amount and time right-aligned and never wrapped.
 *
 * It also folds in the capabilities the Statements version lacked: it links to
 * the edit page, shows Split/Scanned chips, and formats money through
 * `useMoneyFmt` so the hide-amounts privacy toggle is respected (the Statements
 * page previously called `format()` directly and leaked straight through it).
 */

import Link from "next/link";
import { money } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { useMoneyFmt } from "./Money";
import { MaterialIcon, type MaterialIconName } from "./MaterialIcon";

export type TxRow = Transaction & { labels: string | null; method_label: string | null };

/** Small "Split" pill shown on collapsed split tiles. */
export function SplitChip() {
  return (
    <span style={{
      flexShrink: 0, fontSize: 10.5, fontWeight: 700, letterSpacing: "0.03em", textTransform: "uppercase",
      color: "var(--accent)", background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)",
      borderRadius: 999, padding: "1px 7px", lineHeight: 1.5,
    }}>Split</span>
  );
}

/** Small "Scanned" pill for transactions created from a receipt photo. */
export function ScannedChip() {
  return (
    <span style={{
      flexShrink: 0, fontSize: 10.5, fontWeight: 700, letterSpacing: "0.03em", textTransform: "uppercase",
      color: "var(--text-2)", background: "var(--surface-2)", border: "1px solid var(--border)",
      borderRadius: 999, padding: "1px 7px", lineHeight: 1.5,
    }}>Scanned</span>
  );
}

/** Avatar palette — deterministic per title, so a merchant keeps its colour. */
const AV = ["#b06a4f", "#5f7a52", "#c08a3e", "#7a4a6b", "#2f6f6a", "#7c4a3a", "#9cae8e"];

export function avatarColor(s: string): string {
  return AV[[...s].reduce((a, c) => a + c.charCodeAt(0), 0) % AV.length]!;
}

/**
 * Pull a readable name out of a bank/UPI narration:
 *   "UPI/ASHISH ALA/1234/Payment" → "ASHISH ALA"
 * Falls back to the raw string. Kept deliberately dumb — the categoriser in
 * `src/categorize/normalize.ts` does the heavy normalisation; this only needs to
 * produce something a human recognises at a glance.
 */
export function merchantTitle(desc: string): string {
  const parts = desc.split("/").map((s) => s.trim()).filter(Boolean);
  if (parts.length >= 2 && /^(upi|imps|neft|ach|bil|inft|rtgs|nach|pos)$/i.test(parts[0]!)) {
    const name = parts.slice(1).find((p) => /[a-z]{3,}/i.test(p) && !/^\d+$/.test(p));
    return (name || parts[1]!).slice(0, 34);
  }
  return desc.slice(0, 40);
}

/** A small icon + text pair shown under the title (category, label, …). */
export interface MetaTag {
  icon: MaterialIconName;
  text: string;
}

/**
 * Build the standard tag row for a transaction: its category, then each label.
 * `labels` is the comma-joined GROUP_CONCAT string the list queries produce.
 * Skips a category of "Uncategorised" only when there are labels to show, so a
 * bare transaction still says something rather than nothing.
 */
export function txTags(categoryName: string | null | undefined, labels?: string | null): MetaTag[] {
  const out: MetaTag[] = [];
  const names = (labels ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (categoryName && !(names.length && /^uncategorised$/i.test(categoryName))) {
    out.push({ icon: "category", text: categoryName });
  }
  for (const n of names) out.push({ icon: "label", text: n });
  return out;
}

/** Icon + text, sized to sit inline with muted 11.5px copy. */
function MetaBit({ icon, text, size = 13 }: { icon: MaterialIconName; text: string; size?: number }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 4, minWidth: 0, maxWidth: "100%" }}>
      <MaterialIcon name={icon} size={size} style={{ opacity: 0.75 }} />
      <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{text}</span>
    </span>
  );
}

export interface TransactionTileProps {
  /** Raw source text — narration, description, or labels. Drives title + avatar. */
  raw: string;
  amountMinor: number;
  currency: string;
  /** Drives the sign and the amount colour. */
  type: "income" | "expense" | "transfer" | string;
  /** Right-hand meta under the amount — a time on Statements, a date elsewhere. */
  meta?: string | undefined;
  /** Shown under the title when the narration adds nothing (i.e. equals title). */
  fallbackSubtitle?: string | undefined;
  /**
   * Category / label chips, each with its own glyph so the kind of thing is
   * readable at a glance instead of everything being one run of dot-separated
   * grey text. Wraps onto as many lines as it needs.
   */
  tags?: MetaTag[];
  /**
   * The account, on its OWN line below the tags. It's a different kind of fact
   * from a category or a label — "where the money moved" rather than "what it
   * was" — and inlining it made the busiest rows read as one grey smear.
   */
  account?: string | undefined;
  href?: string | undefined;
  split?: boolean;
  scanned?: boolean;
  /** Compact variant for space-constrained tiles (the dashboard). */
  dense?: boolean;
  /** Hairline above the tile — set on every row but the first inside a card. */
  divided?: boolean;
  /** Render the tile as its own standalone card (for `.list-grid` layouts). */
  card?: boolean;
  /**
   * Draw a Material glyph in the avatar instead of the title's initial — used
   * for people, where an icon reads better than a letter. The colour is still
   * derived from `avatarSeed ?? raw`, so each person keeps a stable colour.
   */
  avatarIcon?: MaterialIconName;
  /** Override what the avatar colour hashes on (e.g. a stable user id). */
  avatarSeed?: string;
  /** Right-hand primary text when it isn't money (e.g. "settled"). */
  amountText?: string;
  /** Override the amount colour (defaults to positive for income, else text). */
  amountColor?: string;
  /** Optional trailing element (a button, chip…) after the amount. */
  trailing?: React.ReactNode;
}

export function TransactionTile({
  raw, amountMinor, currency, type, meta, fallbackSubtitle, tags, account,
  href, split = false, scanned = false, dense = false, divided = false,
  card = false, avatarIcon, avatarSeed, amountText, amountColor, trailing,
}: TransactionTileProps) {
  const fmt = useMoneyFmt();
  const text = (raw || type).trim();
  const title = merchantTitle(text);
  // Show the full narration when it says more than the title; otherwise fall
  // back to the category so the second line is never empty.
  const subtitle = text !== title ? text : (tags?.length ? "" : (fallbackSubtitle ?? ""));

  const sign = split || type === "expense" ? "−" : type === "income" ? "+" : "";
  const color = amountColor ?? (type === "income" && !split ? "var(--positive)" : "var(--text)");
  const av = dense ? 28 : 34;

  const body = (
    <>
      <span
        aria-hidden
        style={{
          width: av, height: av, flexShrink: 0, borderRadius: 999,
          background: avatarColor(avatarSeed ?? title), color: "#fff",
          display: "grid", placeItems: "center",
          fontSize: dense ? 12 : 14, fontWeight: 700,
        }}
      >
        {avatarIcon
          ? <MaterialIcon name={avatarIcon} size={dense ? 16 : 19} />
          : (title[0] || "•").toUpperCase()}
      </span>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 6, minWidth: 0 }}>
          <span style={{ fontSize: dense ? 13.5 : 14, fontWeight: 600, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
            {title}
          </span>
          {split && <SplitChip />}
          {scanned && <ScannedChip />}
        </div>
        {subtitle && (
          <div
            className="muted"
            style={
              // Dense rows must stay one line tall or the tile's row budget
              // (useFitRows) is wrong; full rows wrap, which is the point.
              dense
                ? { fontSize: 11.5, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }
                : { fontSize: 11.5, lineHeight: 1.45, overflowWrap: "anywhere", wordBreak: "break-word" }
            }
          >
            {subtitle}
          </div>
        )}

        {/* Category + labels, each glyph-tagged, wrapping as needed. */}
        {!!tags?.length && (
          <div className="muted" style={{ display: "flex", flexWrap: dense ? "nowrap" : "wrap", gap: dense ? 8 : "3px 10px", fontSize: 11.5, marginTop: 2, minWidth: 0, overflow: dense ? "hidden" : undefined }}>
            {tags.map((tg) => <MetaBit key={`${tg.icon}:${tg.text}`} icon={tg.icon} text={tg.text} />)}
          </div>
        )}

        {/* The account gets its own line — see the prop docs for why. */}
        {account && !dense && (
          <div className="muted" style={{ fontSize: 11.5, marginTop: 2, minWidth: 0 }}>
            <MetaBit icon="account_balance" text={account} />
          </div>
        )}
      </div>

      <div style={{ textAlign: "right", flexShrink: 0 }}>
        <div style={{ fontSize: dense ? 13.5 : 14.5, fontWeight: 700, whiteSpace: "nowrap", color }}>
          {amountText ?? `${sign}${fmt(money(amountMinor, currency))}`}
        </div>
        {meta && <div className="muted" style={{ fontSize: 11, whiteSpace: "nowrap" }}>{meta}</div>}
      </div>
      {trailing}
    </>
  );

  const style: React.CSSProperties = {
    display: "flex", gap: dense ? 10 : 12, alignItems: "flex-start",
    padding: dense ? "8px 10px" : "12px 14px",
    borderTop: divided ? "1px solid var(--border)" : "none",
    color: "inherit", width: "100%", boxSizing: "border-box", minWidth: 0,
  };
  // `.tx-tile` already supplies surface, border, radius and the hover lift —
  // and its `padding: !important` would beat the inline padding above, so it is
  // used alone rather than alongside `.card`.
  const cls = card ? "tx-tile" : "tap-row";

  return href
    ? <Link href={href} className={cls} style={style}>{body}</Link>
    : <div className={card ? cls : undefined} style={style}>{body}</div>;
}

/** Group rows by calendar day, newest first, with a friendly label + day net. */
export function groupTxnsByDay<T extends { occurred_at: string; type: string; amount: number }>(
  rows: T[],
  labels: { today: string; yesterday: string },
): { day: string; label: string; items: T[]; net: number }[] {
  const map = new Map<string, T[]>();
  for (const r of rows) {
    const day = r.occurred_at.slice(0, 10);
    (map.get(day) ?? map.set(day, []).get(day)!).push(r);
  }
  const todayStr = new Date().toISOString().slice(0, 10);
  const yStr = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);
  return [...map.entries()]
    .sort((a, b) => b[0].localeCompare(a[0]))
    .map(([day, items]) => {
      const sorted = [...items].sort((a, b) => b.occurred_at.localeCompare(a.occurred_at));
      const net = sorted.reduce((s, r) => s + (r.type === "income" ? r.amount : r.type === "expense" ? -r.amount : 0), 0);
      const label = day === todayStr ? labels.today : day === yStr ? labels.yesterday
        : new Date(day + "T00:00:00").toLocaleDateString(undefined, { day: "numeric", month: "short", year: "2-digit" });
      return { day, label, items: sorted, net };
    });
}
