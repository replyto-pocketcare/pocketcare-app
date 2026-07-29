import test from "node:test";
import assert from "node:assert/strict";
import {
  averageSettleDays,
  computeFriendStats,
  pickFriendInsights,
  THRESHOLDS,
  type FriendEdge,
  type FriendSettlement,
} from "./index.ts";

const day = (n: number) => new Date(Date.UTC(2026, 0, 1 + n)).toISOString();

// ---------------------------------------------------------------------------
// averageSettleDays — the FIFO age-of-debt engine
// ---------------------------------------------------------------------------

test("no payments means null, not zero — never settling is not settling instantly", () => {
  const r = averageSettleDays([{ at: day(0), amount: 1000 }], []);
  assert.equal(r.avgDays, null);
  assert.equal(r.clearedCount, 0);
});

test("a single debt cleared after 10 days averages 10 days", () => {
  const r = averageSettleDays([{ at: day(0), amount: 1000 }], [{ at: day(10), amount: 1000 }]);
  assert.equal(r.avgDays, 10);
  assert.equal(r.clearedCount, 1);
});

test("payments clear the OLDEST debt first", () => {
  const r = averageSettleDays(
    [{ at: day(0), amount: 1000 }, { at: day(20), amount: 1000 }],
    [{ at: day(10), amount: 1000 }],
  );
  // Must clear the day-0 debt (10 days old), not the day-20 one.
  assert.equal(r.avgDays, 10);
  assert.equal(r.clearedCount, 1);
});

test("the average is weighted by amount, not by count", () => {
  // ₹1 cleared instantly + ₹1000 cleared after 100 days. An unweighted mean
  // would say 50 days, which flatters a serial small-payer.
  const r = averageSettleDays(
    [{ at: day(0), amount: 100 }, { at: day(0), amount: 100_000 }],
    [{ at: day(0), amount: 100 }, { at: day(100), amount: 100_000 }],
  );
  assert.ok(r.avgDays !== null);
  assert.ok(r.avgDays > 99, `expected ~99.9, got ${r.avgDays}`);
});

test("a payment made before any debt exists is ignored, not counted as negative age", () => {
  const r = averageSettleDays([{ at: day(10), amount: 1000 }], [{ at: day(0), amount: 1000 }]);
  assert.equal(r.avgDays, null);
  assert.equal(r.clearedCount, 0);
});

test("payment beyond the outstanding debt is ignored", () => {
  const r = averageSettleDays([{ at: day(0), amount: 500 }], [{ at: day(4), amount: 100_000 }]);
  assert.equal(r.avgDays, 4);
  assert.equal(r.clearedCount, 1);
});

test("a partial payment clears part of a debt without marking it cleared", () => {
  const r = averageSettleDays([{ at: day(0), amount: 1000 }], [{ at: day(5), amount: 400 }]);
  assert.equal(r.avgDays, 5);
  assert.equal(r.clearedCount, 0); // still 600 outstanding
});

// ---------------------------------------------------------------------------
// computeFriendStats
// ---------------------------------------------------------------------------

const edge = (friendId: string, groupId: string, atDay: number, amount: number): FriendEdge =>
  ({ friendId, groupId, at: day(atDay), amount });
const settle = (friendId: string, atDay: number, amount: number): FriendSettlement =>
  ({ friendId, at: day(atDay), amount });

test("net nets out edges and settlements", () => {
  const [s] = computeFriendStats({
    edges: [edge("a", "g1", 0, 5000), edge("a", "g1", 1, 2000)],
    settlements: [settle("a", 2, 3000)], // they paid you 3000 back
  });
  assert.equal(s!.net, 4000);
  assert.equal(s!.youCovered, 7000);
  assert.equal(s!.theyCovered, 0);
});

test("groupsOwing / groupsOwed are per-group nets, not per-expense", () => {
  // In g1 they end up owing you; in g2 you owe them.
  const [s] = computeFriendStats({
    edges: [
      edge("a", "g1", 0, 5000), edge("a", "g1", 1, -1000),
      edge("a", "g2", 2, -4000),
    ],
    settlements: [],
  });
  assert.equal(s!.groups, 2);
  assert.equal(s!.groupsOwing, 1);
  assert.equal(s!.groupsOwed, 1);
});

test("contributions drive lent/borrowed independently of your own edges", () => {
  const [s] = computeFriendStats({
    edges: [edge("a", "g1", 0, 100)],
    settlements: [],
    contributions: new Map([["a", [
      { userId: "a", paid: 10_000, share: 2_000 },  // lent 8000
      { userId: "a", paid: 0, share: 3_000 },        // borrowed 3000
    ]]]),
  });
  assert.equal(s!.lent, 8_000);
  assert.equal(s!.borrowed, 3_000);
});

test("friends with no shared history are omitted entirely", () => {
  assert.deepEqual(computeFriendStats({ edges: [], settlements: [] }), []);
});

// ---------------------------------------------------------------------------
// pickFriendInsights — refuses to assert what the data doesn't support
// ---------------------------------------------------------------------------

test("an empty ledger produces no insights rather than empty superlatives", () => {
  assert.deepEqual(pickFriendInsights(computeFriendStats({ edges: [], settlements: [] })), []);
});

test("rounding dust never becomes an insight", () => {
  const stats = computeFriendStats({ edges: [edge("a", "g1", 0, 5)], settlements: [] });
  const keys = pickFriendInsights(stats).map((i) => i.key);
  assert.equal(keys.includes("owes_you_most"), false);
});

test('"always owes" requires a pattern across groups, and is one-sided', () => {
  const consistent = computeFriendStats({
    edges: [edge("a", "g1", 0, 5000), edge("a", "g2", 1, 6000)],
    settlements: [],
  });
  assert.equal(pickFriendInsights(consistent).some((i) => i.key === "always_owes"), true);

  // Same totals, but one group went the other way — no longer "always".
  const mixed = computeFriendStats({
    edges: [edge("a", "g1", 0, 5000), edge("a", "g2", 1, -6000)],
    settlements: [],
  });
  assert.equal(pickFriendInsights(mixed).some((i) => i.key === "always_owes"), false);
});

test("one group is never enough for an 'always' claim", () => {
  const stats = computeFriendStats({ edges: [edge("a", "g1", 0, 50_000)], settlements: [] });
  assert.equal(pickFriendInsights(stats).some((i) => i.key === "always_owes"), false);
  assert.equal(THRESHOLDS.consistentGroups, 2);
});

test("settle-speed rankings need two friends and enough cleared debts", () => {
  // One friend only → nobody is "fastest" relative to nobody.
  const solo = computeFriendStats({
    edges: [edge("a", "g1", 0, 1000), edge("a", "g1", 1, 1000)],
    settlements: [settle("a", 2, 2000)],
  });
  const soloKeys = pickFriendInsights(solo).map((i) => i.key);
  assert.equal(soloKeys.includes("fastest_settler"), false);

  // Two friends, each with 2 cleared debts: 'a' pays fast, 'b' drags.
  const pair = computeFriendStats({
    edges: [
      edge("a", "g1", 0, 1000), edge("a", "g1", 1, 1000),
      edge("b", "g1", 0, 1000), edge("b", "g1", 1, 1000),
    ],
    settlements: [settle("a", 2, 2000), settle("b", 90, 2000)],
  });
  const insights = pickFriendInsights(pair);
  assert.equal(insights.find((i) => i.key === "fastest_settler")?.friendId, "a");
  assert.equal(insights.find((i) => i.key === "slowest_settler")?.friendId, "b");
});

test("a friend who has never settled is not ranked as the slowest", () => {
  const stats = computeFriendStats({
    edges: [
      edge("a", "g1", 0, 1000), edge("a", "g1", 1, 1000),
      edge("b", "g1", 0, 1000), edge("b", "g1", 1, 1000),
      edge("c", "g1", 0, 9000), // never paid anything back
    ],
    settlements: [settle("a", 2, 2000), settle("b", 30, 2000)],
  });
  const slowest = pickFriendInsights(stats).find((i) => i.key === "slowest_settler");
  assert.equal(slowest?.friendId, "b");
  assert.notEqual(slowest?.friendId, "c");
});

test("every emitted insight carries a friend and supporting evidence", () => {
  const stats = computeFriendStats({
    edges: [
      edge("a", "g1", 0, 5000), edge("a", "g2", 1, 6000),
      edge("b", "g1", 0, -4000), edge("b", "g2", 1, -3000),
    ],
    settlements: [],
  });
  for (const i of pickFriendInsights(stats)) {
    assert.ok(i.friendId, `insight ${i.key} has no friend`);
    assert.ok(Number.isFinite(i.value), `insight ${i.key} has a non-finite value`);
    assert.ok(i.evidence >= 0, `insight ${i.key} has negative evidence`);
  }
});
