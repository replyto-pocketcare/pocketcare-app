import { test } from "node:test";
import assert from "node:assert/strict";
import { checksum, rowChecksum, reconcile, type Row } from "./index.ts";

/** Simulate 10 transactions created offline. */
function offlineBatch(n = 10): Row[] {
  const rows: Row[] = [];
  for (let i = 0; i < n; i++) {
    rows.push({
      id: `tx_${String(i).padStart(3, "0")}`,
      account_id: "acc_1",
      type: i % 3 === 0 ? "income" : "expense",
      amount: 100 * (i + 1),
      currency: "INR",
      note: `offline entry ${i}`,
      occurred_at: `2026-07-${String((i % 28) + 1).padStart(2, "0")}T10:00:00Z`,
      created_at: "2026-07-10T00:00:00Z",
      updated_at: "2026-07-10T00:00:00Z",
    });
  }
  return rows;
}

test("10 offline transactions reconcile to 100% fidelity after sync", () => {
  const local = offlineBatch(10);
  // Server echoes identical rows (only server-managed updated_at may differ).
  const remote = local.map((r) => ({ ...r, updated_at: "2026-07-10T00:00:05Z" }));
  const report = reconcile(local, remote, { ignore: ["updated_at"] });
  assert.equal(report.inSync, true, JSON.stringify(report));
  assert.equal(checksum(local, { ignore: ["updated_at"] }), checksum(remote, { ignore: ["updated_at"] }));
});

test("checksum is order-independent (shuffled sync order still matches)", () => {
  const local = offlineBatch(10);
  const shuffled = [...local].sort(() => Math.random() - 0.5);
  assert.equal(checksum(local), checksum(shuffled));
});

test("detects a row that never reached the server (missingRemote)", () => {
  const local = offlineBatch(10);
  const remote = local.slice(0, 9); // one didn't sync
  const report = reconcile(local, remote);
  assert.equal(report.inSync, false);
  assert.deepEqual(report.missingRemote, ["tx_009"]);
});

test("detects a row not yet pulled to the client (missingLocal)", () => {
  const local = offlineBatch(9);
  const remote = offlineBatch(10);
  const report = reconcile(local, remote);
  assert.equal(report.inSync, false);
  assert.deepEqual(report.missingLocal, ["tx_009"]);
});

test("detects content tampering / divergence (mismatched)", () => {
  const local = offlineBatch(10);
  const remote = local.map((r) => (r.id === "tx_005" ? { ...r, amount: 999999 } : { ...r }));
  const report = reconcile(local, remote);
  assert.equal(report.inSync, false);
  assert.deepEqual(report.mismatched, ["tx_005"]);
});

test("a single-field change flips the row checksum", () => {
  const a: Row = { id: "x", amount: 100, note: "a" };
  const b: Row = { id: "x", amount: 100, note: "b" };
  assert.notEqual(rowChecksum(a), rowChecksum(b));
});

test("empty sets are trivially in sync", () => {
  assert.equal(reconcile([], []).inSync, true);
  assert.equal(checksum([]), checksum([]));
});

test("duplicate/extra rows change the set checksum (count is mixed in)", () => {
  const rows = offlineBatch(3);
  const withDupe = [...rows, { ...rows[0]! }];
  assert.notEqual(checksum(rows), checksum(withDupe));
});
