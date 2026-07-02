import { test } from "node:test";
import assert from "node:assert/strict";
import {
  money,
  fromMajor,
  toMajor,
  minorUnits,
  add,
  subtract,
  negate,
  scale,
  sum,
  convert,
  split,
  itemsReconcile,
  format,
  CurrencyMismatchError,
} from "./index.ts";

test("minorUnits: knows currency decimal places", () => {
  assert.equal(minorUnits("USD"), 2);
  assert.equal(minorUnits("INR"), 2);
  assert.equal(minorUnits("JPY"), 0);
  assert.equal(minorUnits("BHD"), 3);
});

test("fromMajor/toMajor round-trip", () => {
  assert.deepEqual(fromMajor(12.34, "USD"), money(1234, "USD"));
  assert.equal(toMajor(money(1234, "USD")), 12.34);
  assert.deepEqual(fromMajor(1000, "JPY"), money(1000, "JPY"));
});

test("fromMajor rounds half away from zero", () => {
  assert.equal(fromMajor(0.005, "USD").amount, 1);
  assert.equal(fromMajor(-0.005, "USD").amount, -1);
});

test("money() rejects non-integer minor units", () => {
  assert.throws(() => money(12.5, "USD"));
});

test("add/subtract/negate stay in minor units", () => {
  assert.deepEqual(add(money(100, "USD"), money(250, "USD")), money(350, "USD"));
  assert.deepEqual(subtract(money(100, "USD"), money(250, "USD")), money(-150, "USD"));
  assert.deepEqual(negate(money(100, "USD")), money(-100, "USD"));
});

test("mixing currencies throws", () => {
  assert.throws(() => add(money(100, "USD"), money(100, "EUR")), CurrencyMismatchError);
});

test("scale rounds to whole minor units", () => {
  assert.deepEqual(scale(money(1000, "USD"), 0.155), money(155, "USD"));
});

test("sum of empty list needs a currency", () => {
  assert.deepEqual(sum([], "USD"), money(0, "USD"));
  assert.throws(() => sum([]));
});

test("convert: same currency is identity", () => {
  const m = money(500, "USD");
  assert.equal(convert(m, "USD", 1.23), m);
});

test("convert: applies rate + target minor units", () => {
  // 100.00 USD at 83.5 INR/USD -> 8350.00 INR = 835000 paise
  assert.deepEqual(convert(money(10000, "USD"), "INR", 83.5), money(835000, "INR"));
  // 10.00 USD -> JPY (0 decimals) at 156.7 -> 1567 yen
  assert.deepEqual(convert(money(1000, "USD"), "JPY", 156.7), money(1567, "JPY"));
});

test("convert rejects non-positive rate", () => {
  assert.throws(() => convert(money(100, "USD"), "INR", 0));
});

test("split distributes with no lost minor units", () => {
  const parts = split(money(1000, "USD"), 3);
  assert.equal(parts.length, 3);
  assert.deepEqual(
    parts.map((p) => p.amount),
    [334, 333, 333],
  );
  assert.equal(sum(parts).amount, 1000);
});

test("split works for negative totals", () => {
  const parts = split(money(-1000, "USD"), 3);
  assert.equal(sum(parts).amount, -1000);
});

test("itemsReconcile enforces breakdown == total", () => {
  const total = money(1000, "USD");
  assert.ok(itemsReconcile(total, [money(600, "USD"), money(400, "USD")]));
  assert.ok(!itemsReconcile(total, [money(600, "USD"), money(399, "USD")]));
  assert.ok(!itemsReconcile(total, [money(600, "USD"), money(400, "EUR")]));
});

test("format is locale-aware", () => {
  // Non-breaking spaces/symbols vary by ICU; assert the digits are present.
  assert.match(format(money(123456, "USD"), "en-US"), /1,234\.56/);
  assert.match(format(money(100000, "JPY"), "ja-JP"), /100,000/);
});
