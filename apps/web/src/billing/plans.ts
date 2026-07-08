"use client";

/** Plans, prices (₹) and AI quotas. Server mirrors these in the edge functions. */
export type PaidTier = "lite" | "pro";
export type Cycle = "monthly" | "yearly";

export interface PlanDef {
  id: PaidTier;
  label: string;
  monthly: number; // ₹
  yearly: number;  // ₹
  quota: number;   // AI prompts / month
  blurb: string;
}

export const PLANS: Record<PaidTier, PlanDef> = {
  lite: { id: "lite", label: "Lite", monthly: 49, yearly: 499, quota: 50, blurb: "Everything unlocked, with a lighter AI allowance." },
  pro: { id: "pro", label: "Pro", monthly: 99, yearly: 999, quota: 200, blurb: "Everything, plus a generous AI allowance." },
};

export const CREDIT_PACKS = [
  { id: "p50", credits: 50, price: 29 },
  { id: "p100", credits: 100, price: 49 },
  { id: "p250", credits: 250, price: 99 },
] as const;
export type CreditPackId = (typeof CREDIT_PACKS)[number]["id"];

export const price = (tier: PaidTier, cycle: Cycle): number => (cycle === "yearly" ? PLANS[tier].yearly : PLANS[tier].monthly);

/** Feature availability by tier. Free excludes these; Lite & Pro include them. */
export const PAID_FEATURES = ["insights", "statements", "assistant", "import", "auto_categorize", "stock_sync", "upcoming"] as const;
