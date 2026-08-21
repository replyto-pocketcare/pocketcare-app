"use client";

import { useSyncExternalStore } from "react";
import type { MaterialIconName } from "./ui/MaterialIcon";

/** Everything eligible for one of the four customizable bottom-bar slots
 *  (2 on each side of the center "+", so the bar reads as a balanced 3-and-3
 *  with Home/More). Home and "More" are fixed — they're not in this catalog. */
export interface NavCatalogItem {
  id: string;
  href: string;
  tkey: string;
  label: string;
  icon: MaterialIconName;
}

export const NAV_CATALOG: NavCatalogItem[] = [
  { id: "transactions", href: "/transactions", tkey: "nav.transactions", label: "Transactions", icon: "swap_horiz" },
  { id: "friends", href: "/friends", tkey: "nav.friends", label: "Splits", icon: "groups" },
  { id: "insights", href: "/insights", tkey: "nav.insights", label: "Insights", icon: "insights" },
  { id: "accounts", href: "/accounts", tkey: "nav.accounts", label: "Accounts", icon: "account_balance" },
  { id: "budgets", href: "/budgets", tkey: "nav.budgets", label: "Budgets", icon: "donut_small" },
  { id: "goals", href: "/goals", tkey: "nav.goals", label: "Goals", icon: "flag" },
  { id: "recurring", href: "/recurring", tkey: "nav.recurring", label: "Recurring", icon: "autorenew" },
  { id: "loans", href: "/loans", tkey: "nav.loans", label: "Loans", icon: "request_quote" },
  { id: "investments", href: "/investments", tkey: "nav.investments", label: "Investments", icon: "trending_up" },
  { id: "cards", href: "/cards", tkey: "nav.cards", label: "Cards", icon: "credit_card" },
  { id: "statements", href: "/statements", tkey: "nav.statements", label: "Statements", icon: "description" },
  { id: "search", href: "/search", tkey: "nav.search", label: "Search", icon: "search" },
  { id: "assistant", href: "/assistant", tkey: "nav.assistant", label: "Ask Sanvya", icon: "auto_awesome" },
  { id: "settings", href: "/settings", tkey: "nav.settings", label: "Settings", icon: "settings" },
];

export const DEFAULT_NAV_IDS = ["transactions", "accounts", "friends", "insights"];
export const NAV_SLOTS = 4;
const KEY = "pc_bottomNav";
const listeners = new Set<() => void>();

function sanitize(ids: unknown): string[] {
  if (!Array.isArray(ids)) return DEFAULT_NAV_IDS;
  const valid = ids.filter((id): id is string => typeof id === "string" && NAV_CATALOG.some((c) => c.id === id));
  const deduped = [...new Set(valid)].slice(0, NAV_SLOTS);
  if (deduped.length === 0) return DEFAULT_NAV_IDS;
  if (deduped.length < NAV_SLOTS) {
    // A save from before the bar grew to 4 slots (or a corrupted/short list) —
    // top it up with defaults rather than leaving one side of the bar short,
    // which is what actually caused the "unbalanced" layout this replaces.
    for (const id of DEFAULT_NAV_IDS) {
      if (deduped.length >= NAV_SLOTS) break;
      if (!deduped.includes(id)) deduped.push(id);
    }
  }
  return deduped;
}

export function getBottomNavIds(): string[] {
  if (typeof window === "undefined") return DEFAULT_NAV_IDS;
  try { return sanitize(JSON.parse(localStorage.getItem(KEY) || "null")); } catch { return DEFAULT_NAV_IDS; }
}
export function setBottomNavIds(ids: string[]): void {
  localStorage.setItem(KEY, JSON.stringify(sanitize(ids)));
  listeners.forEach((l) => l());
}
export function useBottomNavIds(): string[] {
  return useSyncExternalStore((cb) => { listeners.add(cb); return () => listeners.delete(cb); }, getBottomNavIds, () => DEFAULT_NAV_IDS);
}
export function navItemsFor(ids: string[]): NavCatalogItem[] {
  return ids.map((id) => NAV_CATALOG.find((c) => c.id === id)).filter((x): x is NavCatalogItem => !!x);
}
