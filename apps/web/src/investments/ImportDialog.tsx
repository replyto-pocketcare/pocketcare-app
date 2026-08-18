"use client";

import { useMemo, useRef, useState } from "react";
import { Modal } from "../ui/Modal";
import { useMoneyFmt } from "../ui/Money";
import { money } from "@sanvya/money";
import { getBaseCurrency } from "../prefs";
import {
  parseHoldingRows, splitRows, templateCsv, isExampleRow, TEMPLATE_HEADERS,
  type ColumnMap, type HoldingField, type ParseResult,
} from "./importFormats";
import { readXlsxSheets, canReadXlsx, type SheetData } from "./xlsx";
import { importHoldingsBulk, type HoldingImportResult } from "./importBulk";

/** Fields the user can re-point if the guess was wrong. Order = display order. */
const FIELDS: { key: HoldingField; label: string; required?: boolean }[] = [
  { key: "symbol", label: "Symbol" },
  { key: "name", label: "Name" },
  { key: "isin", label: "ISIN" },
  { key: "quantity", label: "Quantity", required: true },
  { key: "avgCost", label: "Avg. cost / unit" },
  { key: "buyValue", label: "Invested value" },
  { key: "currentPrice", label: "Current price" },
  { key: "currentValue", label: "Current value" },
  { key: "exchange", label: "Exchange" },
];

function download(name: string, text: string) {
  const url = URL.createObjectURL(new Blob([text], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url; a.download = name;
  a.click();
  // Revoke on the next tick — revoking synchronously can cancel the download
  // in Safari before it has read the blob.
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function ImportDialog({ open, onClose, accountId, onDone }: {
  open: boolean; onClose: () => void; accountId: string | null; onDone?: () => void;
}) {
  const fmt = useMoneyFmt();
  const base = getBaseCurrency();
  const fileRef = useRef<HTMLInputElement>(null);
  const [sheets, setSheets] = useState<SheetData[] | null>(null);
  const [sheetIdx, setSheetIdx] = useState(0);
  const [fileName, setFileName] = useState("");
  const [override, setOverride] = useState<ColumnMap>({});
  const [onConflict, setOnConflict] = useState<"update" | "skip">("update");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<HoldingImportResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const sheet = sheets?.[sheetIdx] ?? null;
  const parsed: ParseResult | null = useMemo(
    () => (sheet === null ? null : parseHoldingRows(sheet.rows, Object.keys(override).length ? override : undefined)),
    [sheet, override],
  );

  const rows = parsed?.holdings.filter((h) => !isExampleRow(h)) ?? [];
  const droppedExamples = (parsed?.holdings.length ?? 0) - rows.length;

  const reset = () => {
    setSheets(null); setSheetIdx(0); setFileName(""); setOverride({}); setResult(null); setError(null);
    if (fileRef.current) fileRef.current.value = "";
  };

  const pick = async (f: File | undefined) => {
    if (!f) return;
    setError(null); setResult(null); setOverride({}); setSheetIdx(0);
    try {
      if (/\.xlsx$/i.test(f.name)) {
        if (!canReadXlsx()) throw new Error("This browser can't read .xlsx — please save the file as CSV and try again.");
        const all = await readXlsxSheets(await f.arrayBuffer());
        // Brokers split equity / MF / F&O across tabs, so open on the first
        // sheet that actually yields holdings rather than always sheet 1.
        const firstUsable = all.findIndex((sh) => parseHoldingRows(sh.rows).holdings.length > 0);
        setSheets(all);
        setSheetIdx(firstUsable >= 0 ? firstUsable : 0);
      } else if (/\.xls$/i.test(f.name)) {
        // .xls is a completely different (pre-2007, OLE2) format, not a ZIP.
        throw new Error("This is an old .xls file. Open it and re-save as .xlsx or CSV, then upload that.");
      } else {
        setSheets([{ name: f.name, rows: splitRows(await f.text()) }]);
      }
      setFileName(f.name);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not read that file");
    }
  };

  const run = async () => {
    if (!accountId || rows.length === 0) return;
    setBusy(true); setError(null);
    try {
      const r = await importHoldingsBulk(rows, { accountId, onConflict });
      setResult(r);
      if (r.created + r.updated > 0) onDone?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Import failed");
    } finally {
      setBusy(false);
    }
  };

  const totalCost = rows.reduce((s, h) => s + (h.avgCost ?? 0) * h.quantity, 0);

  return (
    <Modal open={open} onClose={() => { reset(); onClose(); }} label="Import investments">
      <h2 style={{ margin: "0 0 4px" }}>Import investments</h2>
      <p className="muted" style={{ fontSize: 13, margin: "0 0 16px", lineHeight: 1.55 }}>
        Upload a holdings or P&amp;L export from Zerodha, Groww, Paytm Money or any other broker.
        Excel (.xlsx) and CSV both work. Columns are matched by name, so most exports import as-is —
        and you can correct the match below if something lands in the wrong place.
      </p>

      {!parsed && (
        <div style={{ display: "grid", gap: 12 }}>
          <label className="btn" style={{ justifyContent: "center", cursor: "pointer" }}>
            Choose a file (.xlsx or .csv)
            <input
              ref={fileRef}
              type="file"
              accept=".csv,.tsv,.txt,.xlsx,text/csv"
              style={{ display: "none" }}
              onChange={(e) => void pick(e.target.files?.[0])}
            />
          </label>
          <button type="button" className="btn ghost" style={{ justifyContent: "center" }}
            onClick={() => download("sanvya-investments-template.csv", templateCsv())}>
            Download a blank template
          </button>
          <p className="muted" style={{ fontSize: 12, margin: 0, lineHeight: 1.5 }}>
            PDF-only export, or a broker we can\u2019t read? Download the template, fill in your holdings
            ({TEMPLATE_HEADERS.join(", ")}) and upload it here.
          </p>
        </div>
      )}

      {error && (
        <div style={{ padding: "10px 12px", borderRadius: 10, fontSize: 13, marginBottom: 12,
          background: "var(--accent-ghost)", border: "1px solid var(--warning)" }}>{error}</div>
      )}

      {parsed && !result && (
        <div style={{ display: "grid", gap: 14 }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, flexWrap: "wrap" }}>
            <div style={{ fontSize: 13 }}>
              <strong>{fileName}</strong>
              <div className="muted" style={{ fontSize: 12 }}>
                {parsed.broker ? `Recognised as ${parsed.broker.label}` : "Unrecognised layout — matched by column name"}
              </div>
            </div>
            <button type="button" className="chip" onClick={reset}>Choose another file</button>
          </div>

          {sheets && sheets.length > 1 && (
            <label style={{ display: "grid", gap: 5, fontSize: 12.5 }}>
              <span className="muted">Sheet</span>
              <select
                value={sheetIdx}
                onChange={(e) => { setSheetIdx(Number(e.target.value)); setOverride({}); }}
                style={{ padding: "7px 9px", borderRadius: 8, border: "1px solid var(--border)", background: "var(--surface)", color: "var(--text)", fontSize: 12.5 }}
              >
                {sheets.map((sh, i) => (
                  <option key={i} value={i}>{sh.name} ({parseHoldingRows(sh.rows).holdings.length} holdings)</option>
                ))}
              </select>
            </label>
          )}

          {rows.length === 0 ? (
            <div style={{ padding: "12px 14px", borderRadius: 10, fontSize: 13, background: "var(--surface-2)" }}>
              No holdings could be read from this file.
              {parsed.rejected[0] ? ` ${parsed.rejected[0].reason}.` : ""} Check the column match below,
              or use the blank template instead.
            </div>
          ) : (
            <div style={{ fontSize: 13 }}>
              <strong>{rows.length}</strong> holding{rows.length === 1 ? "" : "s"} ready
              {totalCost > 0 && <> · {fmt(money(Math.round(totalCost * 100), base))} invested</>}
              {droppedExamples > 0 && <div className="muted" style={{ fontSize: 12 }}>{droppedExamples} example row(s) from the template ignored.</div>}
            </div>
          )}

          {/* Column match — the escape hatch when a broker changes its export. */}
          <details>
            <summary style={{ cursor: "pointer", fontSize: 13, fontWeight: 600 }}>Column match</summary>
            <div style={{ display: "grid", gap: 6, marginTop: 10 }}>
              {FIELDS.map((f) => (
                <label key={f.key} style={{ display: "grid", gridTemplateColumns: "1fr 1.2fr", gap: 8, alignItems: "center", fontSize: 12.5 }}>
                  <span>{f.label}{f.required && <span style={{ color: "var(--negative)" }}> *</span>}</span>
                  <select
                    value={parsed.mapping[f.key] ?? -1}
                    onChange={(e) => setOverride({ ...parsed.mapping, ...override, [f.key]: Number(e.target.value) })}
                    style={{ padding: "6px 8px", borderRadius: 8, border: "1px solid var(--border)", background: "var(--surface)", color: "var(--text)", fontSize: 12.5 }}
                  >
                    <option value={-1}>— not in file —</option>
                    {parsed.headers.map((h, i) => <option key={i} value={i}>{h || `Column ${i + 1}`}</option>)}
                  </select>
                </label>
              ))}
            </div>
          </details>

          {rows.length > 0 && (
            <div style={{ maxHeight: 190, overflowY: "auto", border: "1px solid var(--border)", borderRadius: 10 }}>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12.5 }}>
                <thead>
                  <tr style={{ textAlign: "left", color: "var(--text-2)" }}>
                    <th style={{ padding: "7px 10px" }}>Holding</th>
                    <th style={{ padding: "7px 10px", textAlign: "right" }}>Qty</th>
                    <th style={{ padding: "7px 10px", textAlign: "right" }}>Avg. cost</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.slice(0, 60).map((h) => (
                    <tr key={`${h.sourceRow}-${h.symbol}`} style={{ borderTop: "1px solid var(--border)" }}>
                      <td style={{ padding: "7px 10px" }}>{h.name || h.symbol}</td>
                      <td style={{ padding: "7px 10px", textAlign: "right" }}>{h.quantity}</td>
                      <td style={{ padding: "7px 10px", textAlign: "right" }}>
                        {h.avgCost === null ? "—" : fmt(money(Math.round(h.avgCost * 100), base))}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {rows.length > 60 && <div className="muted" style={{ padding: "7px 10px", fontSize: 12 }}>+{rows.length - 60} more will be imported.</div>}
            </div>
          )}

          {parsed.rejected.length > 0 && rows.length > 0 && (
            <div className="muted" style={{ fontSize: 12 }}>
              {parsed.rejected.length} row(s) skipped — e.g. row {parsed.rejected[0]!.row}: {parsed.rejected[0]!.reason}.
            </div>
          )}

          <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 12.5 }}>
            <input type="checkbox" checked={onConflict === "update"} onChange={(e) => setOnConflict(e.target.checked ? "update" : "skip")} />
            Update holdings I already track (otherwise leave them unchanged)
          </label>

          <button type="button" className="btn" disabled={!accountId || rows.length === 0 || busy}
            style={{ justifyContent: "center" }} onClick={() => void run()}>
            {busy ? "Importing…" : `Import ${rows.length} holding${rows.length === 1 ? "" : "s"}`}
          </button>
          {!accountId && <p className="muted" style={{ fontSize: 12, margin: 0 }}>Add an investment account first — imported holdings need somewhere to live.</p>}
        </div>
      )}

      {result && (
        <div style={{ display: "grid", gap: 12 }}>
          <div style={{ fontSize: 14 }}>
            Imported <strong>{result.created}</strong> new
            {result.updated > 0 && <> · updated <strong>{result.updated}</strong></>}
            {result.skipped > 0 && <> · left <strong>{result.skipped}</strong> unchanged</>}.
          </div>
          {result.errors.map((e, i) => <div key={i} className="muted" style={{ fontSize: 12 }}>{e}</div>)}
          <button type="button" className="btn" style={{ justifyContent: "center" }} onClick={() => { reset(); onClose(); }}>Done</button>
        </div>
      )}
    </Modal>
  );
}
