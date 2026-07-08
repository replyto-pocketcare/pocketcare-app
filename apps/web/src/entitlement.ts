"use client";

import { useQuery } from "@powersync/react";
import { useTier } from "./tier";

interface EntRow {
  tier?: string;
  premium_trial_start_date?: string | null;
  monthly_quota_total?: number | null;
  monthly_quota_used?: number | null;
  purchased_quota_remaining?: number | null;
  additional_purchased_quota?: number | null;
  quota_reset_date?: string | null;
  subscription_status?: string | null;
  billing_cycle?: string | null;
}

export interface Entitlement {
  /** Effective tier (server entitlements, or a non-free dev override). */
  tier: "free" | "lite" | "pro";
  /** Feature gate: any paid tier OR an active trial. */
  isPaid: boolean;
  isTrial: boolean;
  trialDaysLeft: number;
  quotaTotal: number;
  quotaUsed: number;
  purchased: number;
  quotaLeft: number;
  quotaResetDate: string | null;
  subscriptionStatus: string | null;
  cycle: string | null;
}

const normalize = (t?: string): "free" | "lite" | "pro" =>
  t === "pro" || t === "premium" ? "pro" : t === "lite" ? "lite" : "free";

/** Single source of truth for the current user's plan + AI quota. */
export function useEntitlement(): Entitlement {
  const { data = [] } = useQuery<EntRow>(
    "SELECT tier, premium_trial_start_date, monthly_quota_total, monthly_quota_used, purchased_quota_remaining, additional_purchased_quota, quota_reset_date, subscription_status, billing_cycle FROM entitlements LIMIT 1",
  );
  const override = useTier(); // dev preview toggle
  const ent = data[0];

  const serverTier = normalize(ent?.tier);
  const overrideTier = normalize(override);
  const effective = overrideTier !== "free" ? overrideTier : serverTier;

  // 14-day trial (from the new-user trigger) grants paid access while active.
  let isTrial = false;
  let trialDaysLeft = 0;
  if (ent?.premium_trial_start_date && serverTier === "free") {
    const days = Math.ceil((Date.now() - new Date(ent.premium_trial_start_date).getTime()) / 86_400_000);
    if (days <= 14) { isTrial = true; trialDaysLeft = Math.max(0, 14 - days); }
  }

  const quotaTotal = ent?.monthly_quota_total ?? 0;
  const quotaUsed = ent?.monthly_quota_used ?? 0;
  const purchased = (ent?.purchased_quota_remaining ?? 0) + (ent?.additional_purchased_quota ?? 0);
  const quotaLeft = Math.max(0, quotaTotal - quotaUsed) + purchased;

  return {
    tier: effective,
    isPaid: effective !== "free" || isTrial,
    isTrial,
    trialDaysLeft,
    quotaTotal,
    quotaUsed,
    purchased,
    quotaLeft,
    quotaResetDate: ent?.quota_reset_date ?? null,
    subscriptionStatus: ent?.subscription_status ?? null,
    cycle: ent?.billing_cycle ?? null,
  };
}
