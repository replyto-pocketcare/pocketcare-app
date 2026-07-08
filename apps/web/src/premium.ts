"use client";

import { useEntitlement } from "./entitlement";

/**
 * Back-compat wrapper over useEntitlement. `isPremiumUser` now means any PAID
 * tier (Lite or Pro), and the trial is reported separately.
 */
export function usePremiumStatus() {
  const e = useEntitlement();
  return {
    isPremiumUser: e.tier !== "free",
    hasActiveTrial: e.isTrial,
    daysRemaining: e.trialDaysLeft,
  };
}
