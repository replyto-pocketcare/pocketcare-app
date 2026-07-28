import { test } from "node:test";
import assert from "node:assert/strict";

import {
  allocateItem,
  allocateProportional,
  allocateReceipt,
  AllocationError,
  balanceWithLine,
  qtyFromMajor,
  reconcile,
  rollUp,
  splitByWeights,
  splitEqual,
  subtotals,
  shouldEscalate,
  type LineAssignment,
  type ReceiptDraft,
  type ReceiptLine,
} from "./index.ts";

// --- helpers ---------------------------------------------------------------

function line(p: Partial<ReceiptLine> & { id: string; amount: number }): ReceiptLine {
  return {
    kind: "item",
    description: p.id,
    quantity: null,
    unit: null,
    unitPrice: null,
    confidence: 90,
    ...p,
  };
}

function draft(lines: ReceiptLine[], total: number | null, over: Partial<ReceiptDraft> = {}): ReceiptDraft {
  return {
    merchant: "Test Cafe",
    occurredAt: "2026-07-25",
    currency: "INR",
    lines,
    total,
    confidence: 90,
    engine: "tesseract",
    ...over,
  };
}

const sum = (xs: readonly number[]): number => xs.reduce((a, b) => a + b, 0);

// --- splitByWeights --------------------------------------------------------

test("splitByWeights: parts always sum exactly to the total", () => {
  assert.equal(sum(splitByWeights(100, [1, 1, 1])), 100);
  assert.equal(sum(splitByWeights(101, [1, 1, 1])), 101);
  assert.equal(sum(splitByWeights(1, [1, 1, 1])), 1);
  assert.equal(sum(splitByWeights(9999, [3, 5, 7, 11])), 9999);
});

test("splitByWeights: indivisible remainders go to the largest fractions first", () => {
  // 100/3 = 33.33 each; the two extra units land on the first two by index tie-break.
  assert.deepEqual(splitByWeights(100, [1, 1, 1]), [34, 33, 33]);
});

test("splitByWeights: handles negative totals (discount lines) without losing money", () => {
  assert.equal(sum(splitByWeights(-101, [1, 1])), -101);
  assert.equal(sum(splitByWeights(-100, [1, 1, 1])), -100);
  assert.equal(sum(splitByWeights(-7, [2, 5])), -7);
});

test("splitByWeights: all-zero weights yield zeros rather than NaN", () => {
  assert.deepEqual(splitByWeights(500, [0, 0]), [0, 0]);
});

test("splitByWeights: negative weights are clamped to zero", () => {
  assert.deepEqual(splitByWeights(100, [-5, 1]), [0, 100]);
});

test("splitEqual: n-way split is exact", () => {
  for (let n = 1; n <= 9; n++) assert.equal(sum(splitEqual(1000, n)), 1000);
});

// --- allocateItem ----------------------------------------------------------

test("allocateItem equal: three ways on an indivisible amount", () => {
  const out = allocateItem(1000, [{ userId: "a" }, { userId: "b" }, { userId: "c" }], "equal");
  assert.equal(sum(out.map((o) => o.amount)), 1000);
  assert.deepEqual(out.map((o) => o.amount), [334, 333, 333]);
});

test("allocateItem quantity: fractional kg weights split correctly", () => {
  // A 2.5 kg bag costing 500: one takes 1.5 kg, the other 1 kg.
  const out = allocateItem(
    500,
    [{ userId: "a", weight: qtyFromMajor(1.5) }, { userId: "b", weight: qtyFromMajor(1) }],
    "quantity",
  );
  assert.deepEqual(out, [{ userId: "a", amount: 300 }, { userId: "b", amount: 200 }]);
});

test("allocateItem quantity: 3 units of an odd price still sums exactly", () => {
  const out = allocateItem(
    1000,
    [{ userId: "a", weight: 2000 }, { userId: "b", weight: 1000 }],
    "quantity",
  );
  assert.equal(sum(out.map((o) => o.amount)), 1000);
  assert.deepEqual(out.map((o) => o.amount), [667, 333]);
});

test("allocateItem percent: 33.33/33.33/33.34 sums to the line exactly", () => {
  const out = allocateItem(
    10000,
    [{ userId: "a", weight: 3333 }, { userId: "b", weight: 3333 }, { userId: "c", weight: 3334 }],
    "percent",
  );
  assert.equal(sum(out.map((o) => o.amount)), 10000);
});

test("allocateItem exact: accepts shares that add up", () => {
  const out = allocateItem(
    900,
    [{ userId: "a", weight: 400 }, { userId: "b", weight: 500 }],
    "exact",
  );
  assert.deepEqual(out, [{ userId: "a", amount: 400 }, { userId: "b", amount: 500 }]);
});

test("allocateItem exact: rejects shares that do not add up", () => {
  assert.throws(
    () => allocateItem(900, [{ userId: "a", weight: 400 }, { userId: "b", weight: 400 }], "exact"),
    AllocationError,
  );
});

test("allocateItem: a single participant takes the whole line", () => {
  assert.deepEqual(allocateItem(777, [{ userId: "a" }], "equal"), [{ userId: "a", amount: 777 }]);
});

test("allocateItem: unfilled quantity weights fall back to equal, not to nobody", () => {
  const out = allocateItem(300, [{ userId: "a" }, { userId: "b" }], "quantity");
  assert.deepEqual(out.map((o) => o.amount), [150, 150]);
});

test("allocateItem: no participants yields no shares", () => {
  assert.deepEqual(allocateItem(100, [], "equal"), []);
});

test("allocateItem: proportional is rejected at the line level", () => {
  assert.throws(() => allocateItem(100, [{ userId: "a" }], "proportional"), AllocationError);
});

// --- allocateProportional --------------------------------------------------

test("allocateProportional: tax follows each person's item subtotal", () => {
  const sub = new Map([["a", 8000], ["b", 2000]]);
  const out = allocateProportional(1000, ["a", "b"], sub);
  assert.deepEqual(out, [{ userId: "a", amount: 800 }, { userId: "b", amount: 200 }]);
});

test("allocateProportional: a participant who ate nothing pays no tax", () => {
  const sub = new Map([["a", 5000], ["b", 0]]);
  const out = allocateProportional(500, ["a", "b"], sub);
  assert.deepEqual(out, [{ userId: "a", amount: 500 }, { userId: "b", amount: 0 }]);
});

test("allocateProportional: falls back to equal when nobody has a subtotal", () => {
  const out = allocateProportional(300, ["a", "b"], new Map());
  assert.deepEqual(out.map((o) => o.amount), [150, 150]);
});

test("allocateProportional: rounding still sums exactly", () => {
  const sub = new Map([["a", 3333], ["b", 3333], ["c", 3334]]);
  const out = allocateProportional(1001, ["a", "b", "c"], sub);
  assert.equal(sum(out.map((o) => o.amount)), 1001);
});

// --- rollUp ----------------------------------------------------------------

test("rollUp: sums a user's shares across lines", () => {
  const perLine = new Map([
    ["l1", [{ userId: "a", amount: 100 }, { userId: "b", amount: 200 }]],
    ["l2", [{ userId: "a", amount: 50 }]],
  ]);
  const out = rollUp(perLine);
  assert.equal(out.get("a"), 150);
  assert.equal(out.get("b"), 200);
});

// --- allocateReceipt (the whole bill) --------------------------------------

test("allocateReceipt: restaurant bill with proportional tax and service charge", () => {
  const lines = [
    line({ id: "i1", amount: 40000, description: "Biryani" }),
    line({ id: "i2", amount: 20000, description: "Lassi" }),
    line({ id: "tax", kind: "tax", amount: 3000, description: "GST" }),
    line({ id: "svc", kind: "service_charge", amount: 3000, description: "Service charge" }),
  ];
  const assignments: LineAssignment[] = [
    { lineId: "i1", mode: "equal", shares: [{ userId: "a" }, { userId: "b" }] },
    { lineId: "i2", mode: "equal", shares: [{ userId: "a" }] },
    { lineId: "tax", mode: "proportional", shares: [{ userId: "a" }, { userId: "b" }] },
    { lineId: "svc", mode: "equal", shares: [{ userId: "a" }, { userId: "b" }] },
  ];
  const r = allocateReceipt(lines, assignments);

  assert.equal(r.total, 66000);
  // a ate 20000 + 20000 = 40000; b ate 20000.
  assert.equal(r.itemSubtotalByUser.get("a"), 40000);
  assert.equal(r.itemSubtotalByUser.get("b"), 20000);
  // Tax is 2:1 in a's direction; service charge is split down the middle.
  assert.equal(r.byUser.get("a"), 40000 + 2000 + 1500);
  assert.equal(r.byUser.get("b"), 20000 + 1000 + 1500);
  assert.equal(sum([...r.byUser.values()]), r.total);
});

test("allocateReceipt: grocery bill split by quantity", () => {
  const lines = [
    line({ id: "rice", amount: 25000, quantity: qtyFromMajor(5), unit: "kg", unitPrice: 5000 }),
    line({ id: "milk", amount: 6000, quantity: qtyFromMajor(3), unit: "L", unitPrice: 2000 }),
  ];
  const assignments: LineAssignment[] = [
    { lineId: "rice", mode: "quantity", shares: [{ userId: "a", weight: qtyFromMajor(3) }, { userId: "b", weight: qtyFromMajor(2) }] },
    { lineId: "milk", mode: "quantity", shares: [{ userId: "b", weight: qtyFromMajor(3) }] },
  ];
  const r = allocateReceipt(lines, assignments);
  assert.equal(r.byUser.get("a"), 15000);
  assert.equal(r.byUser.get("b"), 10000 + 6000);
  assert.equal(sum([...r.byUser.values()]), r.total);
});

test("allocateReceipt: a discount line reduces shares and still balances", () => {
  const lines = [
    line({ id: "i1", amount: 10000 }),
    line({ id: "disc", kind: "discount", amount: -1500, description: "10% off" }),
  ];
  const assignments: LineAssignment[] = [
    { lineId: "i1", mode: "equal", shares: [{ userId: "a" }, { userId: "b" }] },
    { lineId: "disc", mode: "proportional", shares: [{ userId: "a" }, { userId: "b" }] },
  ];
  const r = allocateReceipt(lines, assignments);
  assert.equal(r.total, 8500);
  assert.equal(sum([...r.byUser.values()]), 8500);
  assert.equal(r.byUser.get("a"), 4250);
});

test("allocateReceipt: rounding across two passes never drifts from the total", () => {
  // Deliberately awkward: prime-ish amounts, 3 people, proportional tax.
  const lines = [
    line({ id: "i1", amount: 3337 }),
    line({ id: "i2", amount: 1009 }),
    line({ id: "tax", kind: "tax", amount: 787, description: "GST" }),
  ];
  const assignments: LineAssignment[] = [
    { lineId: "i1", mode: "equal", shares: [{ userId: "a" }, { userId: "b" }, { userId: "c" }] },
    { lineId: "i2", mode: "equal", shares: [{ userId: "b" }, { userId: "c" }] },
    { lineId: "tax", mode: "proportional", shares: [{ userId: "a" }, { userId: "b" }, { userId: "c" }] },
  ];
  const r = allocateReceipt(lines, assignments);
  assert.equal(r.total, 3337 + 1009 + 787);
  assert.equal(sum([...r.byUser.values()]), r.total);
});

test("allocateReceipt: an unassigned line is a hard error, not a silent loss", () => {
  const lines = [line({ id: "i1", amount: 100 }), line({ id: "i2", amount: 200 })];
  const assignments: LineAssignment[] = [
    { lineId: "i1", mode: "equal", shares: [{ userId: "a" }] },
  ];
  assert.throws(() => allocateReceipt(lines, assignments), AllocationError);
});

test("allocateReceipt: an item line may not use proportional mode", () => {
  const lines = [line({ id: "i1", amount: 100 })];
  const assignments: LineAssignment[] = [
    { lineId: "i1", mode: "proportional", shares: [{ userId: "a" }] },
  ];
  assert.throws(() => allocateReceipt(lines, assignments), AllocationError);
});

test("allocateReceipt: solo scan (one person on everything) gives them the total", () => {
  const lines = [
    line({ id: "i1", amount: 4500 }),
    line({ id: "tax", kind: "tax", amount: 225, description: "GST" }),
  ];
  const r = allocateReceipt(lines, [
    { lineId: "i1", mode: "equal", shares: [{ userId: "me" }] },
    { lineId: "tax", mode: "proportional", shares: [{ userId: "me" }] },
  ]);
  assert.equal(r.byUser.get("me"), 4725);
});

// --- subtotals / reconcile -------------------------------------------------

test("subtotals: buckets each kind and computes the sum", () => {
  const s = subtotals([
    line({ id: "i1", amount: 1000 }),
    line({ id: "t", kind: "tax", amount: 50 }),
    line({ id: "s", kind: "service_charge", amount: 100 }),
    line({ id: "tp", kind: "tip", amount: 200 }),
    line({ id: "d", kind: "discount", amount: -150 }),
  ]);
  assert.equal(s.items, 1000);
  assert.equal(s.tax, 50);
  assert.equal(s.serviceCharge, 100);
  assert.equal(s.tip, 200);
  assert.equal(s.discount, -150);
  assert.equal(s.computed, 1200);
});

test("reconcile: balanced draft passes", () => {
  const r = reconcile(draft([line({ id: "i1", amount: 500 }), line({ id: "t", kind: "tax", amount: 25 })], 525));
  assert.equal(r.ok, true);
  assert.equal(r.reason, "balanced");
  assert.equal(r.delta, 0);
});

test("reconcile: a one-unit mismatch fails (we do not absorb rounding)", () => {
  const r = reconcile(draft([line({ id: "i1", amount: 500 })], 501));
  assert.equal(r.ok, false);
  assert.equal(r.reason, "mismatch");
  assert.equal(r.delta, 1);
});

test("reconcile: missing total is reported distinctly from a mismatch", () => {
  const r = reconcile(draft([line({ id: "i1", amount: 500 })], null));
  assert.equal(r.ok, false);
  assert.equal(r.reason, "missing_total");
});

test("reconcile: empty draft is reported as no_lines", () => {
  assert.equal(reconcile(draft([], 100)).reason, "no_lines");
});

// --- escalation gate -------------------------------------------------------

test("shouldEscalate: balanced high-confidence draft stays on-device", () => {
  assert.equal(shouldEscalate(draft([line({ id: "i1", amount: 100 })], 100, { confidence: 95 })), false);
});

test("shouldEscalate: low confidence escalates even when it balances", () => {
  assert.equal(shouldEscalate(draft([line({ id: "i1", amount: 100 })], 100, { confidence: 40 })), true);
});

test("shouldEscalate: a mismatch escalates even at high confidence", () => {
  assert.equal(shouldEscalate(draft([line({ id: "i1", amount: 100 })], 250, { confidence: 99 })), true);
});

test("shouldEscalate: an AI draft is never escalated again", () => {
  assert.equal(shouldEscalate(draft([line({ id: "i1", amount: 100 })], 250, { engine: "claude", confidence: 10 })), false);
});

// --- balanceWithLine -------------------------------------------------------

test("balanceWithLine: absorbs a shortfall as an item line", () => {
  const d = balanceWithLine(draft([line({ id: "i1", amount: 500 })], 620), "fix", "Unmatched");
  const r = reconcile(d);
  assert.equal(r.ok, true);
  assert.equal(d.lines.length, 2);
  assert.equal(d.lines[1]!.amount, 120);
  assert.equal(d.lines[1]!.kind, "item");
});

test("balanceWithLine: absorbs an overshoot as a discount line", () => {
  const d = balanceWithLine(draft([line({ id: "i1", amount: 700 })], 650), "fix", "Unmatched");
  assert.equal(reconcile(d).ok, true);
  assert.equal(d.lines[1]!.kind, "discount");
  assert.equal(d.lines[1]!.amount, -50);
});

test("balanceWithLine: a balanced draft is returned untouched", () => {
  const d0 = draft([line({ id: "i1", amount: 500 })], 500);
  assert.equal(balanceWithLine(d0, "fix", "Unmatched"), d0);
});

test("balanceWithLine: a draft with no total cannot be balanced", () => {
  const d0 = draft([line({ id: "i1", amount: 500 })], null);
  assert.equal(balanceWithLine(d0, "fix", "Unmatched"), d0);
});

// --- end-to-end sanity -----------------------------------------------------

test("end to end: parse-shaped draft reconciles then allocates to the exact total", () => {
  const lines = [
    line({ id: "1", amount: 32000, description: "Paneer Tikka", quantity: qtyFromMajor(1) }),
    line({ id: "2", amount: 18000, description: "Naan", quantity: qtyFromMajor(4), unitPrice: 4500 }),
    line({ id: "3", amount: 12000, description: "Cold Coffee", quantity: qtyFromMajor(2), unitPrice: 6000 }),
    line({ id: "4", kind: "service_charge", amount: 3100, description: "Service Charge 5%" }),
    line({ id: "5", kind: "tax", amount: 3255, description: "CGST+SGST" }),
  ];
  const d = draft(lines, 68355);
  assert.equal(reconcile(d).ok, true);

  const r = allocateReceipt(lines, [
    { lineId: "1", mode: "equal", shares: [{ userId: "a" }, { userId: "b" }, { userId: "c" }] },
    { lineId: "2", mode: "quantity", shares: [{ userId: "a", weight: qtyFromMajor(2) }, { userId: "b", weight: qtyFromMajor(1) }, { userId: "c", weight: qtyFromMajor(1) }] },
    { lineId: "3", mode: "equal", shares: [{ userId: "b" }, { userId: "c" }] },
    { lineId: "4", mode: "equal", shares: [{ userId: "a" }, { userId: "b" }, { userId: "c" }] },
    { lineId: "5", mode: "proportional", shares: [{ userId: "a" }, { userId: "b" }, { userId: "c" }] },
  ]);
  assert.equal(sum([...r.byUser.values()]), 68355);
  assert.equal(r.total, d.total);
});
