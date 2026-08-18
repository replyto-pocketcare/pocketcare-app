import { test } from "node:test";
import assert from "node:assert/strict";
import { parseHoldingsFile, templateCsv, isExampleRow, num } from "./importFormats.ts";

/* Fixtures mirror the SHAPE each broker's export is reported to have. They are
   not verified against a real download (those only exist behind a login), which
   is exactly why the parser matches on column names and exposes a correctable
   mapping rather than trusting fixed positions. */


/** Index access is checked (`noUncheckedIndexedAccess`), so assert-then-return
 *  keeps each expectation a one-liner without a non-null assertion per field. */
function h0(r: ReturnType<typeof parseHoldingsFile>) {
  const h = r.holdings[0];
  assert.ok(h, "expected at least one holding");
  return h;
}
function rj0(r: ReturnType<typeof parseHoldingsFile>) {
  const x = r.rejected[0];
  assert.ok(x, "expected a rejection reason");
  return x;
}

test("Zerodha Console holdings: skips preamble, reads columns, drops the total row", () => {
  const csv = [
    "Zerodha Broking Ltd",
    "Holdings statement",
    "Client ID,AB1234",
    "",
    "Instrument,Qty.,Avg. cost,LTP,Cur. val,P&L",
    "INFY,25,1450.50,1600.00,40000.00,3737.50",
    "TCS,10,3200.00,3400.00,34000.00,2000.00",
    "Total,,,,74000.00,5737.50",
  ].join("\n");
  const r = parseHoldingsFile(csv);
  assert.equal(r.broker?.id, "zerodha");
  assert.equal(r.holdings.length, 2, "the Total row must not become a holding");
  assert.equal(h0(r).symbol, "INFY");
  assert.equal(h0(r).quantity, 25);
  assert.equal(h0(r).avgCost, 1450.5);
  assert.equal(h0(r).currentValue, 40000);
});

test("Groww: maps 'Average buy price' to cost, not 'Closing price'", () => {
  const csv = [
    "Stock Name,ISIN,Quantity,Average buy price,Buy value,Closing price,Closing value",
    "Infosys Ltd,INE009A01021,25,1450.50,36262.50,1600,40000",
  ].join("\n");
  const r = parseHoldingsFile(csv);
  assert.equal(r.broker?.id, "groww");
  assert.equal(h0(r).avgCost, 1450.5);
  assert.equal(h0(r).currentValue, 40000);
  assert.equal(h0(r).isin, "INE009A01021");
});

test("Paytm Money: 'Avg Price' + LTP with no current-value column", () => {
  const csv = [
    "Scrip Name,ISIN,Quantity,Avg Price,LTP",
    "Reliance Industries,INE002A01018,12,2400.25,2600",
  ].join("\n");
  const r = parseHoldingsFile(csv);
  assert.equal(h0(r).avgCost, 2400.25);
  // No current value column, so it derives one from price x quantity.
  assert.equal(h0(r).currentValue, 31200);
});

test("tradewise P&L: derives per-unit cost from buy value / quantity", () => {
  const csv = [
    "Symbol,ISIN,Entry Date,Quantity,Buy Value,Sell Value",
    "INFY,INE009A01021,2025-01-05,10,14000,15000",
  ].join("\n");
  const r = parseHoldingsFile(csv);
  assert.equal(h0(r).avgCost, 1400);
});

test("mutual fund exports are classified as mf, not stock", () => {
  const csv = [
    "Scheme Name,Folio,Units,NAV",
    "Parag Parikh Flexi Cap,12345/67,310.482,62.15",
  ].join("\n");
  const r = parseHoldingsFile(csv);
  assert.equal(h0(r).assetClass, "mf");
  assert.equal(h0(r).quantity, 310.482);
});

test("Indian-format numbers, currency symbols and bracket negatives", () => {
  assert.equal(num("₹1,45,000.50"), 145000.5);
  assert.equal(num("(1,234.50)"), -1234.5);
  assert.equal(num("-"), null);
  assert.equal(num(""), null);
  assert.equal(num("N/A"), null);
});

test("a corrected mapping overrides the guess", () => {
  const csv = ["Name,Col A,Col B", "Widget,7,99"].join("\n");
  // Nothing matches "quantity" here, so it cannot parse unaided...
  assert.equal(parseHoldingsFile(csv).holdings.length, 0);
  // ...but pointing quantity at column 1 rescues the file.
  const fixed = parseHoldingsFile(csv, { name: 0, quantity: 1, avgCost: 2 });
  assert.equal(fixed.holdings.length, 1);
  assert.equal(h0(fixed).quantity, 7);
  assert.equal(h0(fixed).avgCost, 99);
});

test("the blank template round-trips, and its example rows are flagged", () => {
  const r = parseHoldingsFile(templateCsv());
  assert.equal(r.holdings.length, 2);
  assert.ok(r.holdings.every(isExampleRow), "template samples must be detectable so they are never imported");
});

test("unreadable files report why instead of importing nothing silently", () => {
  const r = parseHoldingsFile("just some text\nand another line");
  assert.equal(r.holdings.length, 0);
  assert.ok(rj0(r).reason.length > 0);
});
