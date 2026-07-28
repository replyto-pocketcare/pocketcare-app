import { test } from "node:test";
import assert from "node:assert/strict";

import {
  allocateReceipt,
  findDate,
  findNumbers,
  groupIntoLines,
  linesFromText,
  parseMoney,
  parseReceipt,
  parseReceiptText,
  qtyToMajor,
  reconcile,
  subtotals,
  type OcrToken,
} from "./index.ts";
import { FIXTURES } from "./fixtures.ts";

const TODAY = "2026-07-27";

// ---------------------------------------------------------------------------
// parseMoney
// ---------------------------------------------------------------------------

test("parseMoney: plain and grouped decimals", () => {
  assert.equal(parseMoney("120.00"), 12000);
  assert.equal(parseMoney("1,234.56"), 123456);
  assert.equal(parseMoney("1234.5"), 123450);
  assert.equal(parseMoney("99"), 9900);
});

test("parseMoney: Indian lakh grouping", () => {
  assert.equal(parseMoney("1,23,456.78"), 12345678);
  assert.equal(parseMoney("1,50,000"), 15000000);
});

test("parseMoney: European decimal comma", () => {
  assert.equal(parseMoney("1.234,56"), 123456);
  assert.equal(parseMoney("12,50"), 1250);
});

test("parseMoney: currency symbols and codes are stripped", () => {
  assert.equal(parseMoney("₹1,234.56"), 123456);
  assert.equal(parseMoney("Rs. 450.00"), 45000);
  assert.equal(parseMoney("$4.50"), 450);
  assert.equal(parseMoney("INR 99.99"), 9999);
});

test("parseMoney: negatives in every notation receipts use", () => {
  assert.equal(parseMoney("-50.00"), -5000);
  assert.equal(parseMoney("50.00-"), -5000);
  assert.equal(parseMoney("(50.00)"), -5000);
});

test("parseMoney: rejects non-numeric and over-long digit runs", () => {
  assert.equal(parseMoney("abc"), null);
  assert.equal(parseMoney(""), null);
  // Over 12 digits is never a price — reject rather than return a huge number.
  assert.equal(parseMoney("1234567890123456"), null);
});

test("parseMoney: zero-decimal currencies via minorDigits", () => {
  assert.equal(parseMoney("1,200", 0), 1200);
});

// ---------------------------------------------------------------------------
// findNumbers
// ---------------------------------------------------------------------------

test("findNumbers: returns every number left to right with positions", () => {
  const nums = findNumbers("Butter Naan 4 180.00");
  assert.equal(nums.length, 2);
  assert.equal(nums[0]!.value, 400);
  assert.equal(nums[1]!.value, 18000);
  assert.ok(nums[1]!.start > nums[0]!.start);
});

// ---------------------------------------------------------------------------
// findDate
// ---------------------------------------------------------------------------

test("findDate: day-first numeric dates", () => {
  assert.equal(findDate("Date: 25/07/2026", TODAY), "2026-07-25");
  assert.equal(findDate("25-07-26", TODAY), "2026-07-25");
});

test("findDate: flips when the second field can only be a day", () => {
  assert.equal(findDate("07/25/2026", TODAY), "2026-07-25");
});

test("findDate: textual months in both orders", () => {
  assert.equal(findDate("25 Jul 2026", TODAY), "2026-07-25");
  assert.equal(findDate("Jul 25, 2026", TODAY), "2026-07-25");
});

test("findDate: ISO passes through", () => {
  assert.equal(findDate("2026-07-25", TODAY), "2026-07-25");
});

test("findDate: future dates are rejected as misreads", () => {
  assert.equal(findDate("Date: 25/12/2026", TODAY), null);
});

test("findDate: picks the transaction date over an older printed date", () => {
  assert.equal(findDate("Member since 01/01/2020\nDate 25/07/2026", TODAY), "2026-07-25");
});

test("findDate: returns null when there is no date", () => {
  assert.equal(findDate("SPICE GARDEN", TODAY), null);
});

// ---------------------------------------------------------------------------
// groupIntoLines
// ---------------------------------------------------------------------------

function tok(text: string, x0: number, y0: number, h = 20): OcrToken {
  return { text, x0, x1: x0 + text.length * 8, y0, y1: y0 + h, confidence: 90 };
}

test("groupIntoLines: groups by vertical overlap and orders by x", () => {
  const lines = groupIntoLines([
    tok("120.00", 400, 100),
    tok("Dosa", 20, 102),
    tok("Coffee", 20, 140),
    tok("40.00", 400, 141),
  ]);
  assert.equal(lines.length, 2);
  assert.equal(lines[0]!.text, "Dosa 120.00");
  assert.equal(lines[1]!.text, "Coffee 40.00");
});

test("groupIntoLines: empty input yields no lines", () => {
  assert.deepEqual(groupIntoLines([]), []);
});

test("linesFromText: drops blank lines and collapses whitespace", () => {
  const lines = linesFromText("a  b\n\n  c \n");
  assert.deepEqual(lines.map((l) => l.text), ["a b", "c"]);
});

// ---------------------------------------------------------------------------
// Fixtures — the real regression net
// ---------------------------------------------------------------------------

for (const fx of FIXTURES) {
  test(`fixture: ${fx.name}`, () => {
    const draft = parseReceiptText(fx.text, { currency: fx.currency, today: TODAY });
    const r = reconcile(draft);
    const s = subtotals(draft.lines);

    assert.equal(draft.total, fx.expect.total, "total");
    assert.equal(r.ok, fx.expect.balances, `balances (computed ${r.computed} vs stated ${r.stated})`);

    if (fx.expect.merchant !== undefined) assert.equal(draft.merchant, fx.expect.merchant, "merchant");
    if (fx.expect.occurredAt !== undefined) assert.equal(draft.occurredAt, fx.expect.occurredAt, "date");
    if (fx.expect.currency !== undefined) assert.equal(draft.currency, fx.expect.currency, "currency");
    if (fx.expect.itemCount !== undefined) {
      assert.equal(draft.lines.filter((l) => l.kind === "item").length, fx.expect.itemCount, "item count");
    }
    if (fx.expect.tax !== undefined) assert.equal(s.tax, fx.expect.tax, "tax");
    if (fx.expect.serviceCharge !== undefined) assert.equal(s.serviceCharge, fx.expect.serviceCharge, "service charge");
    if (fx.expect.discount !== undefined) assert.equal(s.discount, fx.expect.discount, "discount");
    if (fx.expect.tip !== undefined) assert.equal(s.tip, fx.expect.tip, "tip");
  });
}

// ---------------------------------------------------------------------------
// Targeted parser behaviour
// ---------------------------------------------------------------------------

test("parser: payment footer lines never become items", () => {
  const d = parseReceiptText(
    "SHOP\nTea 20.00\nTotal 20.00\nCash 100.00\nChange 80.00\nCard ****1234",
    { currency: "INR", today: TODAY },
  );
  assert.equal(d.lines.length, 1);
  assert.equal(reconcile(d).ok, true);
});

test("parser: subtotal is recorded but never double-counted as a line", () => {
  const d = parseReceiptText(
    "SHOP\nTea 20.00\nCoffee 30.00\nSub Total 50.00\nTotal 50.00",
    { currency: "INR", today: TODAY },
  );
  assert.equal(d.lines.length, 2);
  assert.equal(reconcile(d).ok, true);
});

test("parser: 'Total Qty' is not mistaken for the bill total", () => {
  const d = parseReceiptText(
    "SHOP\nTea 20.00\nTotal Qty: 3\nGrand Total 20.00",
    { currency: "INR", today: TODAY },
  );
  assert.equal(d.total, 2000);
});

test("parser: service charge and service tax are classified differently", () => {
  const d = parseReceiptText(
    "SHOP\nTea 100.00\nService Charge 10.00\nService Tax 5.00\nTotal 115.00",
    { currency: "INR", today: TODAY },
  );
  const s = subtotals(d.lines);
  assert.equal(s.serviceCharge, 1000);
  assert.equal(s.tax, 500);
});

test("parser: discounts are stored negative even when printed positive", () => {
  const d = parseReceiptText(
    "SHOP\nShirt 1000.00\nDiscount 200.00\nTotal 800.00",
    { currency: "INR", today: TODAY },
  );
  assert.equal(subtotals(d.lines).discount, -20000);
  assert.equal(reconcile(d).ok, true);
});

test("parser: qty x rate = amount is detected by multiplying, not by position", () => {
  const d = parseReceiptText(
    "SHOP\nToor Dal 2 95.50 191.00\nTotal 191.00",
    { currency: "INR", today: TODAY },
  );
  const item = d.lines[0]!;
  assert.equal(qtyToMajor(item.quantity!), 2);
  assert.equal(item.unitPrice, 9550);
  assert.equal(item.amount, 19100);
  assert.match(item.description, /Toor Dal/);
});

test("parser: a three-number line that does NOT multiply keeps no bogus quantity", () => {
  const d = parseReceiptText(
    "SHOP\nItem 7 13 500.00\nTotal 500.00",
    { currency: "INR", today: TODAY },
  );
  assert.equal(d.lines[0]!.quantity, null);
  assert.equal(d.lines[0]!.amount, 50000);
});

test("parser: '2 x Item' notation yields quantity and derived unit price", () => {
  const d = parseReceiptText(
    "SHOP\n2 x Maggi Noodles 28.00\nTotal 28.00",
    { currency: "INR", today: TODAY },
  );
  const item = d.lines[0]!;
  assert.equal(qtyToMajor(item.quantity!), 2);
  assert.equal(item.unitPrice, 1400);
  assert.equal(item.description, "Maggi Noodles");
});

test("parser: weight-based lines keep the unit", () => {
  const d = parseReceiptText(
    "SHOP\n1.5 kg Onion 45.00\nTotal 45.00",
    { currency: "INR", today: TODAY },
  );
  const item = d.lines[0]!;
  assert.equal(qtyToMajor(item.quantity!), 1.5);
  assert.equal(item.unit, "kg");
  assert.equal(item.description, "Onion");
});

test("parser: percentage labels do not become the amount", () => {
  const d = parseReceiptText(
    "SHOP\nFood 100.00\nCGST 2.5% 2.50\nTotal 102.50",
    { currency: "INR", today: TODAY },
  );
  assert.equal(subtotals(d.lines).tax, 250);
  assert.equal(reconcile(d).ok, true);
});

test("parser: GSTIN and phone lines are ignored entirely", () => {
  const d = parseReceiptText(
    "SHOP\nGSTIN: 29AABCS1234F1Z5\nPh: 080-4455 6677\nTea 20.00\nTotal 20.00",
    { currency: "INR", today: TODAY },
  );
  assert.equal(d.lines.length, 1);
});

test("parser: a bare number with no label is dropped as noise", () => {
  const d = parseReceiptText("SHOP\n42\nTea 20.00\nTotal 20.00", { currency: "INR", today: TODAY });
  assert.equal(d.lines.length, 1);
});

test("parser: currency is detected from the receipt over the fallback", () => {
  const d = parseReceiptText("CAFE\nCoffee $4.50\nTotal $4.50", { currency: "INR", today: TODAY });
  assert.equal(d.currency, "USD");
});

test("parser: falls back to the supplied currency when none is printed", () => {
  const d = parseReceiptText("CAFE\nCoffee 4.50\nTotal 4.50", { currency: "INR", today: TODAY });
  assert.equal(d.currency, "INR");
});

test("parser: empty input yields an empty, unusable draft", () => {
  const d = parseReceiptText("", { currency: "INR", today: TODAY });
  assert.equal(d.lines.length, 0);
  assert.equal(d.confidence, 0);
  assert.equal(reconcile(d).ok, false);
});

test("parser: line ids are stable and unique", () => {
  const d = parseReceiptText(
    "SHOP\nA 10.00\nB 20.00\nC 30.00\nTotal 60.00",
    { currency: "INR", today: TODAY },
  );
  const ids = d.lines.map((l) => l.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.deepEqual(parseReceiptText("SHOP\nA 10.00\nB 20.00\nC 30.00\nTotal 60.00", { currency: "INR", today: TODAY }).lines.map((l) => l.id), ids);
});

test("parser: confidence rewards a bill that adds up", () => {
  const good = parseReceiptText("SHOP\nA 10.00\nB 20.00\nTotal 30.00", { currency: "INR", today: TODAY });
  const bad = parseReceiptText("SHOP\nA 10.00\nB 20.00\nTotal 99.00", { currency: "INR", today: TODAY });
  assert.ok(good.confidence > bad.confidence);
});

test("parser: works from positioned tokens, not just text", () => {
  const draft = parseReceipt(
    groupIntoLines([
      tok("SPICE", 20, 10), tok("GARDEN", 90, 10),
      tok("Dosa", 20, 60), tok("120.00", 400, 60),
      tok("Total", 20, 100), tok("120.00", 400, 100),
    ]),
    { currency: "INR", today: TODAY },
  );
  assert.equal(draft.merchant, "SPICE GARDEN");
  assert.equal(draft.total, 12000);
  assert.equal(reconcile(draft).ok, true);
});

// ---------------------------------------------------------------------------
// Integration: the invariant the itemized write path depends on
//
// createSplitExpenseItemized rolls per-item shares into expense_participants
// and relies on Σ shares === expenses.amount. If that ever drifts, every
// balance derived from the expense is wrong, so it is asserted here across
// every fixture that parses cleanly.
// ---------------------------------------------------------------------------

test("integration: every balanced fixture allocates to exactly its total", () => {
  const balanced = FIXTURES.filter((fx) => fx.expect.balances);
  assert.ok(balanced.length >= 8, "expected most fixtures to reconcile");

  for (const fx of balanced) {
    const draft = parseReceiptText(fx.text, { currency: fx.currency, today: TODAY });
    const people = ["a", "b", "c"];

    // Realistic mix: items split three ways, charges proportional.
    const assignments = draft.lines.map((line, i) => ({
      lineId: line.id,
      mode: (line.kind === "item"
        ? (i % 2 === 0 ? "equal" : "percent")
        : "proportional") as "equal" | "percent" | "proportional",
      shares:
        line.kind === "item" && i % 2 !== 0
          ? [
              { userId: "a", weight: 5000 },
              { userId: "b", weight: 3000 },
              { userId: "c", weight: 2000 },
            ]
          : people.map((userId) => ({ userId })),
    }));

    const r = allocateReceipt(draft.lines, assignments);
    const rolled = [...r.byUser.values()].reduce((s, v) => s + v, 0);

    assert.equal(rolled, draft.total, `${fx.name}: roll-up must equal the receipt total`);
    assert.equal(r.total, draft.total, `${fx.name}: allocation total must equal the receipt total`);

    // And each individual line must be fully allocated.
    for (const line of draft.lines) {
      const lineSum = (r.perLine.get(line.id) ?? []).reduce((s, x) => s + x.amount, 0);
      assert.equal(lineSum, line.amount, `${fx.name}: line "${line.description}" must be fully allocated`);
    }
  }
});
