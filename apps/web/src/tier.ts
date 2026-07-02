"use client";

import { useSyncExternalStore } from "react";
import type { Tier } from "@pocketcare/types";

/**
 * Local, reactive entitlement override used for the Free/Premium preview toggle.
 * Kept client-side (localStorage) so it's instant and offline — real billing
 * (RevenueCat) would set the synced entitlements row in production.
 */
const KEY = "tierOverride";
const listeners = new Set<() => void>();

export function getTier(): Tier {
  if (typeof window === "undefined") return "free";
  return (localStorage.getItem(KEY) as Tier) || "free";
}

export function setTier(tier: Tier): void {
  localStorage.setItem(KEY, tier);
  listeners.forEach((l) => l());
}

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

/** Reactive across all components that read it. */
export function useTier(): Tier {
  return useSyncExternalStore(subscribe, getTier, () => "free");
}
