/**
 * @sanvya/suggestions — which parts of the app is this person not using yet?
 *
 * Pure and portable: it takes a plain count of what exists and returns an
 * ordered list of feature ids. No DB, no React, no copy — the app supplies the
 * counts and i18n supplies the words, so the same rules can drive web and both
 * native clients.
 *
 * THE DESIGN PROBLEM. A "try this" strip is one step from being an ad for your
 * own product, and a finance app is the wrong place to feel nagged. Three rules
 * keep it honest, and every one of them REMOVES suggestions:
 *
 *  1. **Earn the suggestion.** Each feature declares a prerequisite. Telling
 *     someone to split a bill before they've recorded a single transaction is
 *     noise; telling them once they have twenty is a real observation.
 *  2. **Say little.** A wall of eleven cards reads as a demand. `MAX_VISIBLE`
 *     caps what's shown, so the strip stays a nudge.
 *  3. **Dismissal is permanent and per-feature.** "Not interested" has to mean
 *     it, or the strip becomes something to endure rather than read.
 *
 * Erasable TS only, so `node --experimental-strip-types` runs the tests.
 */

/** Everything a suggestion can be about. Ids are stable — they're persisted. */
export const FEATURES = [
  "subscriptions",
  "loans",
  "budgets",
  "goals",
  "splits",
  "receipts",
  "recurring",
  "investments",
  "creditCards",
  "cashflow",
] as const;
export type FeatureId = (typeof FEATURES)[number];

/**
 * What the user already has. Every field is a row count; absent means zero.
 *
 * Counts, not booleans, because a prerequisite is usually "enough of X to make
 * Y worth mentioning", and that threshold differs per feature.
 */
export interface UsageCounts {
  accounts?: number;
  transactions?: number;
  subscriptions?: number;
  loans?: number;
  budgets?: number;
  goals?: number;
  splitGroups?: number;
  receipts?: number;
  recurring?: number;
  holdings?: number;
  creditCards?: number;
  creditCardAccounts?: number;
  plannedCashflow?: number;
}

export interface SuggestionRule {
  readonly id: FeatureId;
  /** Already used it? Then there is nothing to suggest. */
  readonly used: (u: UsageCounts) => boolean;
  /** Is it worth mentioning yet? */
  readonly eligible: (u: UsageCounts) => boolean;
  /**
   * Tie-break order, lower first. Roughly "how much of a difference does this
   * make to someone who isn't using it" — budgets before investments.
   */
  readonly weight: number;
  /** Needs a paid plan. Never suggested to a free user — see `pickSuggestions`. */
  readonly premium?: boolean;
}

const n = (v: number | undefined): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);

/**
 * The catalogue.
 *
 * Prerequisites are deliberately conservative. The failure mode that matters is
 * suggesting something irrelevant — that teaches the user the strip is worth
 * ignoring, and once learned they never read it again.
 */
export const RULES: readonly SuggestionRule[] = [
  {
    // Nearly everyone has some. Cheap to add, immediately useful, so it leads.
    id: "subscriptions",
    used: (u) => n(u.subscriptions) > 0,
    eligible: (u) => n(u.transactions) >= 5,
    weight: 10,
  },
  {
    id: "budgets",
    used: (u) => n(u.budgets) > 0,
    // A budget over three transactions is a guess. Wait for a real month.
    eligible: (u) => n(u.transactions) >= 15,
    weight: 20,
  },
  {
    id: "recurring",
    used: (u) => n(u.recurring) > 0,
    eligible: (u) => n(u.transactions) >= 15,
    weight: 30,
  },
  {
    // Only if they actually hold a credit card account — otherwise it's an ad.
    id: "creditCards",
    used: (u) => n(u.creditCards) > 0,
    eligible: (u) => n(u.creditCardAccounts) > 0,
    weight: 35,
  },
  {
    id: "loans",
    used: (u) => n(u.loans) > 0,
    eligible: (u) => n(u.transactions) >= 10,
    weight: 40,
  },
  {
    id: "goals",
    used: (u) => n(u.goals) > 0,
    eligible: (u) => n(u.transactions) >= 10,
    weight: 50,
  },
  {
    id: "splits",
    used: (u) => n(u.splitGroups) > 0,
    eligible: (u) => n(u.transactions) >= 10,
    weight: 60,
  },
  {
    id: "receipts",
    used: (u) => n(u.receipts) > 0,
    eligible: (u) => n(u.transactions) >= 10,
    weight: 70,
  },
  {
    id: "investments",
    used: (u) => n(u.holdings) > 0,
    eligible: (u) => n(u.accounts) >= 1 && n(u.transactions) >= 20,
    weight: 80,
  },
  {
    id: "cashflow",
    used: (u) => n(u.plannedCashflow) > 0,
    eligible: (u) => n(u.transactions) >= 20,
    weight: 100,
    premium: true,
  },
];

/** How many cards the strip shows at once. A long list reads as a demand. */
export const MAX_VISIBLE = 5;

export interface PickOptions {
  /** Feature ids the user has dismissed. Permanent, per feature. */
  readonly dismissed?: Iterable<string>;
  /** Paid plan? Premium suggestions are hidden from free users. */
  readonly isPaid?: boolean;
  readonly max?: number;
}

/**
 * Ordered feature ids to suggest.
 *
 * Returns `[]` freely — an empty strip is a perfectly good outcome, and the
 * caller is expected to render nothing at all rather than an empty state.
 * "You've used everything" needs no announcement.
 */
export function pickSuggestions(usage: UsageCounts, opts: PickOptions = {}): FeatureId[] {
  const dismissed = new Set<string>(opts.dismissed ?? []);
  const max = opts.max ?? MAX_VISIBLE;

  // A user with nothing at all is being onboarded, not upsold. The first-run
  // walkthrough owns that moment; a suggestion strip on top of it is clutter.
  if (n(usage.accounts) === 0 && n(usage.transactions) === 0) return [];

  return RULES.filter((r) => !dismissed.has(r.id))
    .filter((r) => !r.used(usage))
    .filter((r) => r.eligible(usage))
    // Suggesting something they'd have to pay to touch is an ad, not a tip.
    .filter((r) => !r.premium || opts.isPaid === true)
    .sort((a, b) => a.weight - b.weight)
    .slice(0, Math.max(0, max))
    .map((r) => r.id);
}

/** True when a feature id is one we know — guards persisted dismissals. */
export function isFeatureId(v: string): v is FeatureId {
  return (FEATURES as readonly string[]).includes(v);
}
