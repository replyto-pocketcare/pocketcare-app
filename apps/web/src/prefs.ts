"use client";

import { useSyncExternalStore } from "react";

/** Reactive base currency (default INR). Changing it updates the whole app. */
const CUR_KEY = "baseCurrency";
const DEFAULT_CURRENCY = "INR";
const curListeners = new Set<() => void>();

export function getBaseCurrency(): string {
  if (typeof window === "undefined") return DEFAULT_CURRENCY;
  return localStorage.getItem(CUR_KEY) || DEFAULT_CURRENCY;
}
export function setBaseCurrency(c: string): void {
  localStorage.setItem(CUR_KEY, c);
  curListeners.forEach((l) => l());
}
export function useBaseCurrency(): string {
  return useSyncExternalStore((cb) => { curListeners.add(cb); return () => curListeners.delete(cb); }, getBaseCurrency, () => DEFAULT_CURRENCY);
}

/** Reactive "hide amounts" (privacy) toggle. */
const HIDE_KEY = "amountsHidden";
const hideListeners = new Set<() => void>();

export function getAmountsHidden(): boolean {
  if (typeof window === "undefined") return false;
  return localStorage.getItem(HIDE_KEY) === "1";
}
export function setAmountsHidden(hidden: boolean): void {
  localStorage.setItem(HIDE_KEY, hidden ? "1" : "0");
  hideListeners.forEach((l) => l());
}
export function useAmountsHidden(): boolean {
  return useSyncExternalStore((cb) => { hideListeners.add(cb); return () => hideListeners.delete(cb); }, getAmountsHidden, () => false);
}
