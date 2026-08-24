// Mindfulness insights generation.
//
// These functions accept an array of transactions (and optionally categories/labels)
// and return computed insights. They are pure functions, side-effect free.

import { fromMajor, type CurrencyCode } from "@sanvya/money";

export interface TransactionForInsight {
  id: string;
  amount: number;
  currency: string;
  occurred_at: string;
  intent?: 'need' | 'greed' | null;
  category_id?: string | null;
}

/**
 * How an insight turns an amount into words.
 *
 * A **callback**, not a currency + locale pair, for two reasons. It keeps this
 * package from having to know about locales at all; and, more importantly, web
 * passes `useMoneyFmt()` here, so an amount inside an insight is hidden by the
 * hide-amounts toggle like every other amount in the app. Before this existed
 * these bodies interpolated a bare number, which no toggle could reach.
 */
export interface InsightMoneyCtx {
  /** The currency amounts are reported in. Transactions in others are skipped. */
  currency: CurrencyCode;
  /** Formats a MINOR-unit amount. Never do arithmetic on the result. */
  fmt: (minorAmount: number) => string;
}

/** The small-purchase-drift threshold, in major units. */
const SMALL_PURCHASE_MAJOR = 200;

export interface Insight {
  id: string;
  type: string;
  title: string;
  body: string;
  severity?: 'info' | 'warn' | 'success';
}

// Tier 1 insights (no tagging required)
export function computeTier1Insights(
  txns: TransactionForInsight[],
  money: InsightMoneyCtx,
  tzOffsetStr = "+00:00",
): Insight[] {
  const insights: Insight[] = [];
  
  if (txns.length === 0) return insights;
  
  // Example: Late-night spending (22:00-04:00)
  // This is a naive implementation assuming UTC if tzOffset is missing, 
  // but a real implementation would use proper timezone handling.
  let lateNightCount = 0;
  for (const t of txns) {
    const d = new Date(t.occurred_at);
    // Rough check in UTC for demonstration
    const hour = d.getUTCHours();
    if (hour >= 22 || hour < 4) {
      lateNightCount++;
    }
  }
  
  if (lateNightCount > 0) {
    insights.push({
      id: "late_night_spending",
      type: "tier1",
      title: "Late-night spending",
      body: `You logged ${lateNightCount} transaction(s) between 22:00 and 04:00.`,
      severity: "info",
    });
  }

  // Small-purchase drift.
  //
  // The threshold is derived, not written down: `200` is a major-unit figure,
  // and 20000 minor units is 200 only in a 2-decimal currency. In JPY (0 minor
  // units) that constant meant ¥20,000, and in KWD (3) it meant 20 dinar.
  const threshold = fromMajor(SMALL_PURCHASE_MAJOR, money.currency).amount;

  // Only same-currency transactions. Summing ¥ into $ produced a number that
  // was not an amount in any currency, then labelled it with one.
  const smallTxns = txns.filter(t => t.currency === money.currency && t.amount < threshold);
  if (smallTxns.length > 5) {
    const totalSmall = smallTxns.reduce((sum, t) => sum + t.amount, 0);
    insights.push({
      id: "small_purchase_drift",
      type: "tier1",
      title: "Small-purchase drift",
      body: `You had ${smallTxns.length} spends under ${money.fmt(threshold)}, totaling ${money.fmt(totalSmall)}.`,
      severity: "info",
    });
  }

  return insights;
}

// Tier 2 insights (unlocked by Need/Greed tagging)
export function computeTier2Insights(txns: TransactionForInsight[]): Insight[] {
  const insights: Insight[] = [];
  
  const tagged = txns.filter(t => t.intent === 'need' || t.intent === 'greed');
  if (tagged.length < 20) {
    return insights; // Minimum 20 tagged items needed per plan
  }
  
  const greed = tagged.filter(t => t.intent === 'greed');
  const totalTaggedAmount = tagged.reduce((s, t) => s + t.amount, 0);
  const totalGreedAmount = greed.reduce((s, t) => s + t.amount, 0);
  
  const ratio = (totalGreedAmount / (totalTaggedAmount || 1)) * 100;
  
  insights.push({
    id: "greed_ratio",
    type: "tier2",
    title: "Greed ratio",
    body: `${ratio.toFixed(0)}% of your tagged spending was marked as Greed.`,
    severity: ratio > 50 ? "warn" : "success",
  });
  
  return insights;
}
