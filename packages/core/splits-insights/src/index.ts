/**
 * Behavioural insights over a shared-expense ledger — who lends, who owes, and
 * who actually pays you back.
 *
 * Pure and portable: it takes plain records, never touches the DB, and knows
 * nothing about PowerSync. All money is **integer minor units**, all dates are
 * ISO strings.
 *
 * Two deliberate limits, both stated in the UI rather than papered over:
 *  - Everything is computed from the groups YOU are in. "Lends the most" means
 *    the most within your shared ledger, not in their life.
 *  - Ranking insights need evidence. A friend with one expense is not "the
 *    slowest settler", so every ranking carries a minimum-evidence threshold
 *    and returns nothing rather than something confidently wrong.
 */

const DAY_MS = 86_400_000;

/** One pairwise edge on one expense: what `friendId` owes YOU for it. */
export interface FriendEdge {
  friendId: string;
  groupId: string;
  /** ISO timestamp of the expense. */
  at: string;
  /** Minor units. Positive = they owe you; negative = you owe them. */
  amount: number;
}

/** A settlement between you and a friend. */
export interface FriendSettlement {
  friendId: string;
  /** ISO timestamp the settlement was recorded/settled. */
  at: string;
  /** Minor units. Positive = they paid you; negative = you paid them. */
  amount: number;
}

/**
 * A participant row on a shared expense. Unlike `FriendEdge` this covers
 * everyone in the group, including expenses you weren't part of, so "who lends
 * the most" reflects the group rather than only your own edges.
 */
export interface Contribution {
  userId: string;
  /** Minor units they actually paid. */
  paid: number;
  /** Minor units they consumed. */
  share: number;
}

export interface FriendStats {
  friendId: string;
  /** Current balance. Positive = they owe you. */
  net: number;
  /** Total you have covered for them, over all time. */
  youCovered: number;
  /** Total they have covered for you, over all time. */
  theyCovered: number;
  /** Their all-time lending across the shared ledger: Σ max(0, paid − share). */
  lent: number;
  /** Their all-time borrowing: Σ max(0, share − paid). */
  borrowed: number;
  /** Distinct groups you share. */
  groups: number;
  /** Groups where they ended up owing you. */
  groupsOwing: number;
  /** Groups where you ended up owing them. */
  groupsOwed: number;
  /** Number of expenses you share. */
  expenses: number;
  /**
   * Weighted-average days a debt of theirs stayed open before their payment
   * cleared it (FIFO). `null` when they have never settled anything, which is
   * different from settling instantly.
   */
  avgSettleDays: number | null;
  /** How many debts of theirs have been cleared by a settlement. */
  settledDebts: number;
}

const days = (fromIso: string, toIso: string): number =>
  (new Date(toIso).getTime() - new Date(fromIso).getTime()) / DAY_MS;

/**
 * FIFO age-of-debt at settlement.
 *
 * Their payments clear their oldest debts first, and each cleared chunk
 * contributes `days(debt → payment)` weighted by the chunk's size. Weighting
 * matters: clearing a ₹5 debt instantly and a ₹5,000 debt after six months is
 * not "three months average" behaviour.
 *
 * A payment arriving before any debt exists is ignored rather than counted as
 * negative-age — it's a prepayment, not fast settling. Leftover payment beyond
 * the outstanding debt is ignored for the same reason.
 */
export function averageSettleDays(
  debts: { at: string; amount: number }[],
  payments: { at: string; amount: number }[],
): { avgDays: number | null; clearedCount: number } {
  const queue = debts
    .filter((d) => d.amount > 0)
    .slice()
    .sort((a, b) => a.at.localeCompare(b.at))
    .map((d) => ({ at: d.at, left: d.amount }));
  const pays = payments
    .filter((p) => p.amount > 0)
    .slice()
    .sort((a, b) => a.at.localeCompare(b.at));

  let weighted = 0;
  let weight = 0;
  let cleared = 0;
  let head = 0;

  for (const pay of pays) {
    let remaining = pay.amount;
    while (remaining > 0 && head < queue.length) {
      const debt = queue[head]!;
      // Debts incurred after this payment can't have been cleared by it.
      if (debt.at > pay.at) break;
      const chunk = Math.min(remaining, debt.left);
      const age = Math.max(0, days(debt.at, pay.at));
      weighted += age * chunk;
      weight += chunk;
      debt.left -= chunk;
      remaining -= chunk;
      if (debt.left === 0) { cleared++; head++; }
    }
  }

  return { avgDays: weight > 0 ? weighted / weight : null, clearedCount: cleared };
}

export interface ComputeInput {
  edges: FriendEdge[];
  settlements: FriendSettlement[];
  /** Optional, keyed by friend id — enables `lent` / `borrowed`. */
  contributions?: Map<string, Contribution[]>;
}

/** Per-friend rollup. Friends with no shared history are omitted. */
export function computeFriendStats({ edges, settlements, contributions }: ComputeInput): FriendStats[] {
  const byFriend = new Map<string, FriendStats>();
  const perGroup = new Map<string, Map<string, number>>();

  const ensure = (friendId: string): FriendStats => {
    let s = byFriend.get(friendId);
    if (!s) {
      s = {
        friendId, net: 0, youCovered: 0, theyCovered: 0, lent: 0, borrowed: 0,
        groups: 0, groupsOwing: 0, groupsOwed: 0, expenses: 0,
        avgSettleDays: null, settledDebts: 0,
      };
      byFriend.set(friendId, s);
      perGroup.set(friendId, new Map());
    }
    return s;
  };

  for (const e of edges) {
    const s = ensure(e.friendId);
    s.net += e.amount;
    s.expenses += 1;
    if (e.amount > 0) s.youCovered += e.amount;
    else if (e.amount < 0) s.theyCovered += -e.amount;
    const g = perGroup.get(e.friendId)!;
    g.set(e.groupId, (g.get(e.groupId) ?? 0) + e.amount);
  }

  for (const st of settlements) {
    const s = ensure(st.friendId);
    // They paid you → reduces what they owe. You paid them → reduces what you owe.
    s.net -= st.amount;
  }

  for (const [friendId, s] of byFriend) {
    const g = perGroup.get(friendId)!;
    s.groups = g.size;
    for (const net of g.values()) {
      if (net > 0) s.groupsOwing += 1;
      else if (net < 0) s.groupsOwed += 1;
    }

    const debts = edges.filter((e) => e.friendId === friendId && e.amount > 0).map((e) => ({ at: e.at, amount: e.amount }));
    const pays = settlements.filter((x) => x.friendId === friendId && x.amount > 0).map((x) => ({ at: x.at, amount: x.amount }));
    const { avgDays, clearedCount } = averageSettleDays(debts, pays);
    s.avgSettleDays = avgDays;
    s.settledDebts = clearedCount;

    for (const c of contributions?.get(friendId) ?? []) {
      const delta = c.paid - c.share;
      if (delta > 0) s.lent += delta;
      else if (delta < 0) s.borrowed += -delta;
    }
  }

  return [...byFriend.values()];
}

export type InsightKey =
  | "biggest_lender"
  | "owes_you_most"
  | "you_owe_most"
  | "always_owes"
  | "always_owed"
  | "fastest_settler"
  | "slowest_settler";

export interface FriendInsight {
  key: InsightKey;
  friendId: string;
  /** Minor units for money insights, days for settle-speed, group count otherwise. */
  value: number;
  /** Supporting count — groups, cleared debts — for "based on N" copy. */
  evidence: number;
}

/** Minimum evidence before a ranking is asserted at all. */
export const THRESHOLDS = {
  /** "Always owes/owed" needs a pattern, and two groups is the smallest one. */
  consistentGroups: 2,
  /** Settle-speed needs cleared debts; one payment is an anecdote. */
  settledDebts: 2,
  /** Ignore rounding dust when ranking money. */
  minAmount: 100,
} as const;

const best = <T>(xs: T[], score: (x: T) => number): T | null => {
  let top: T | null = null;
  let topScore = -Infinity;
  for (const x of xs) {
    const s = score(x);
    if (s > topScore) { topScore = s; top = x; }
  }
  return top;
};

/**
 * Pick the headline insights. Returns only what the data actually supports —
 * an empty array is a valid, honest answer for a thin ledger.
 */
export function pickFriendInsights(stats: FriendStats[]): FriendInsight[] {
  const out: FriendInsight[] = [];
  const push = (key: InsightKey, s: FriendStats | null, value: number, evidence: number) => {
    if (s && value >= THRESHOLDS.minAmount) out.push({ key, friendId: s.friendId, value, evidence });
  };

  const lender = best(stats.filter((s) => s.lent > 0), (s) => s.lent);
  push("biggest_lender", lender, lender?.lent ?? 0, lender?.expenses ?? 0);

  const owesYou = best(stats.filter((s) => s.net > 0), (s) => s.net);
  push("owes_you_most", owesYou, owesYou?.net ?? 0, owesYou?.expenses ?? 0);

  const youOwe = best(stats.filter((s) => s.net < 0), (s) => -s.net);
  push("you_owe_most", youOwe, youOwe ? -youOwe.net : 0, youOwe?.expenses ?? 0);

  // "Always" means exactly that: every shared group lands the same way, across
  // at least `consistentGroups` of them. One-sided by construction.
  const alwaysOwes = best(
    stats.filter((s) => s.groupsOwing >= THRESHOLDS.consistentGroups && s.groupsOwed === 0),
    (s) => s.groupsOwing,
  );
  if (alwaysOwes) out.push({ key: "always_owes", friendId: alwaysOwes.friendId, value: alwaysOwes.groupsOwing, evidence: alwaysOwes.groups });

  const alwaysOwed = best(
    stats.filter((s) => s.groupsOwed >= THRESHOLDS.consistentGroups && s.groupsOwing === 0),
    (s) => s.groupsOwed,
  );
  if (alwaysOwed) out.push({ key: "always_owed", friendId: alwaysOwed.friendId, value: alwaysOwed.groupsOwed, evidence: alwaysOwed.groups });

  const settlers = stats.filter((s) => s.avgSettleDays !== null && s.settledDebts >= THRESHOLDS.settledDebts);
  if (settlers.length >= 2) {
    const fastest = best(settlers, (s) => -(s.avgSettleDays!));
    const slowest = best(settlers, (s) => s.avgSettleDays!);
    // Only worth saying when they're actually different people.
    if (fastest && slowest && fastest.friendId !== slowest.friendId) {
      out.push({ key: "fastest_settler", friendId: fastest.friendId, value: fastest.avgSettleDays!, evidence: fastest.settledDebts });
      out.push({ key: "slowest_settler", friendId: slowest.friendId, value: slowest.avgSettleDays!, evidence: slowest.settledDebts });
    }
  }

  return out;
}
