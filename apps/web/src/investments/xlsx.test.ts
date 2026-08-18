import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { readXlsxSheets } from "./xlsx.ts";
import { parseHoldingRows } from "./importFormats.ts";

/* Fixture is a REAL .xlsx written by openpyxl — same zip/XML shape Excel and
   broker exports produce — not a hand-assembled archive, which would only
   prove the parser agrees with itself. */
const fixture = fileURLToPath(new URL("./__fixtures__/paytm-holdings.xlsx", import.meta.url));
const load = async () => readXlsxSheets((await readFile(fixture)).buffer as ArrayBuffer);

test("reads every sheet, with the tab names from the workbook", async () => {
  const sheets = await load();
  assert.deepEqual(sheets.map((s) => s.name), ["Holdings", "Mutual Funds"]);
});

test("shared strings, numbers and the preamble survive the round trip", async () => {
  const [holdings] = await load();
  assert.ok(holdings);
  assert.equal(holdings.rows[0]?.[0], "Paytm Money Ltd");
  assert.equal(holdings.rows[4]?.[0], "Scrip Name");
  assert.equal(holdings.rows[5]?.[2], "12");
  assert.equal(holdings.rows[5]?.[3], "2400.25");
});

test("XML-escaped text and embedded commas come back intact", async () => {
  const [holdings] = await load();
  // Proves cells are never round-tripped through CSV (the comma would split
  // the column) and that &amp; is decoded.
  assert.equal(holdings?.rows[6]?.[0], "Bajaj Finance, Ltd & Co");
});

test("a Paytm Money .xlsx parses straight into holdings", async () => {
  const [holdings] = await load();
  assert.ok(holdings);
  const r = parseHoldingRows(holdings.rows);
  assert.equal(r.broker?.id, "paytm");
  assert.equal(r.holdings.length, 3, "the Total row must not become a holding");

  const rel = r.holdings[0];
  assert.ok(rel);
  assert.equal(rel.name, "Reliance Industries Ltd");
  assert.equal(rel.isin, "INE002A01018");
  assert.equal(rel.quantity, 12);
  assert.equal(rel.avgCost, 2400.25);
  assert.equal(rel.currentValue, 31200);
  assert.equal(rel.assetClass, "stock");
});

test("the mutual-fund sheet is classified as mf, not stock", async () => {
  const sheets = await load();
  const mf = sheets[1];
  assert.ok(mf);
  const r = parseHoldingRows(mf.rows);
  assert.equal(r.holdings.length, 1);
  assert.equal(r.holdings[0]?.assetClass, "mf");
  assert.equal(r.holdings[0]?.quantity, 310.482);
  assert.equal(r.holdings[0]?.currentValue, 19296.45);
  // A bare "NAV" column on a HOLDINGS statement is today's NAV, not what you
  // paid, so it must not be mistaken for cost — the statement simply doesn't
  // say what this was bought at.
  assert.equal(r.holdings[0]?.avgCost, null);
});

test("a non-xlsx file fails with a clear message rather than garbage", async () => {
  await assert.rejects(
    () => readXlsxSheets(new TextEncoder().encode("just,a,csv\n1,2,3").buffer as ArrayBuffer),
    /not a valid \.xlsx/i,
  );
});
