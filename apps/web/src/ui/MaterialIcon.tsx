/**
 * Material Symbols Rounded, self-hosted as a 4 KB subset (see
 * `public/fonts/README.md` for how it's generated and why it's not a CDN).
 *
 * Icons render by **codepoint, not ligature**. Ligatures (`<span>settings</span>`)
 * are the documented Material Symbols usage, but they can't be subset — every
 * icon name is spelled from the same 26 letters, so retaining the `liga` feature
 * retains ~3 000 glyphs (252 KB vs 4 KB). Codepoints also degrade better: if the
 * font fails to load, a ligature paints the literal word "space_dashboard" into
 * the navigation, whereas a codepoint paints nothing.
 */

import type { CSSProperties } from "react";

/** name → PUA codepoint in `sanvya-icons.woff2`. Keep in sync with the subset. */
export const MATERIAL_ICON = {
  account_balance: "\ue84f",
  add: "\ue145",
  apartment: "\uea40",
  arrow_back: "\ue5c4",
  auto_awesome: "\ue65f",
  autorenew: "\ue028",
  bolt: "\uea0b",
  bookmarks: "\ue98b",
  call_split: "\ue0b6",
  category: "\ue574",
  chat_bubble: "\ue0ca",
  check: "\ue5ca",
  chevron_right: "\ue409",
  close: "\ue14c",
  credit_card: "\ue870",
  currency_bitcoin: "\uebc5",
  delete: "\ue872",
  description: "\ue683",
  directions_car: "\ue531",
  donut_small: "\ue918",
  edit: "\ue150",
  expand_more: "\ue5cf",
  fitness_center: "\ueb43",
  flag: "\ue153",
  folder: "\ue2c7",
  groups: "\uf233",
  health_and_safety: "\ue1d5",
  help: "\ue887",
  home: "\ue88a",
  insights: "\uf092",
  label: "\ue892",
  more_horiz: "\ue5d3",
  notifications: "\ue7f4",
  payments: "\uef63",
  person: "\ue7fd",
  pie_chart: "\ue6c4",
  receipt: "\ue8b0",
  receipt_long: "\uef6e",
  redeem: "\ue8b1",
  request_quote: "\uf1b6",
  restaurant: "\ue56c",
  savings: "\ue2eb",
  school: "\ue80c",
  search: "\ue8b6",
  sell: "\ue54e",
  settings: "\ue8b8",
  show_chart: "\ue6e1",
  space_dashboard: "\ue66b",
  subscriptions: "\ue064",
  swap_horiz: "\ue8d4",
  sync_problem: "\ue629",
  trending_up: "\ue8e5",
  volunteer_activism: "\uea70",
  wallet: "\uf8ff",
  waterfall_chart: "\uea00",
  wifi: "\ue63e",
  work: "\ue8f9",
} as const;

export type MaterialIconName = keyof typeof MATERIAL_ICON;

/**
 * `aria-hidden` by default: these sit next to a text label in the nav, so
 * announcing them would double up. Pass `label` for a standalone icon button.
 */
export function MaterialIcon({ name, size = 20, label, style }: {
  name: MaterialIconName;
  size?: number;
  label?: string;
  /** Extra styles (colour, transform, …). Merged after the size defaults. */
  style?: CSSProperties;
}) {
  return (
    <span
      className="msym"
      style={{ fontSize: size, width: size, height: size, ...style }}
      {...(label ? { role: "img", "aria-label": label } : { "aria-hidden": true })}
    >
      {MATERIAL_ICON[name]}
    </span>
  );
}
