"use client";

import { useState } from "react";
import Link from "next/link";
import { downloadText } from "../../src/data/csv";
import { exportTransactionsCsv } from "../../src/data/exportCsv";
import { IMPORT_ADAPTERS, parseWithAdapter, type CanonRow } from "../../src/data/adapters";
import { importTransactions, type ImportResult } from "../../src/data/importCsv";
import { usePremiumStatus } from "../../src/premium";

export default function DataPage() {
  const { isPremiumUser, hasActiveTrial } = usePremiumStatus();
  const [exporting, setExporting] = useState(false);
  const [exportMsg, setExportMsg] = useState<string | null>(null);

  const [adapterId, setAdapterId] = useState(IMPORT_ADAPTERS[0]!.id);
  const [fileName, setFileName] = useState<string | null>(null);
  const [rows, setRows] = useState<CanonRow[] | null>(null);
  const [parseErr, setParseErr] = useState<string | null>(null);
  const [skipDup, setSkipDup] = useState(true);
  const [importing, setImporting] = useState(false);
  const [result, setResult] = useState<ImportResult | null>(null);

  async function doExport() {
    setExporting(true); setExportMsg(null);
    try {
      const { csv, count } = await exportTransactionsCsv();
      if (count === 0) { setExportMsg("No transactions to export yet."); return; }
      downloadText(`pocketcare-transactions-${new Date().toISOString().slice(0, 10)}.csv`, csv);
      setExportMsg(`Exported ${count} transaction${count === 1 ? "" : "s"}.`);
    } catch (e) {
      setExportMsg(`Export failed: ${(e as Error).message}`);
    } finally { setExporting(false); }
  }

  async function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    setResult(null); setParseErr(null); setRows(null);
    if (!file) return;
    setFileName(file.name);
    try {
      const text = await file.text();
      const parsed = parseWithAdapter(adapterId, text);
      if (parsed.length === 0) { setParseErr("No rows found — check the file and the selected format."); return; }
      setRows(parsed);
    } catch (err) {
      setParseErr(`Couldn't read the file: ${(err as Error).message}`);
    }
  }

  async function runImport() {
    if (!rows) return;
    setImporting(true); setResult(null);
    try {
      const r = await importTransactions(rows, { skipDuplicates: skipDup });
      setResult(r);
      setRows(null); setFileName(null);
    } catch (e) {
      setResult({ created: 0, skipped: 0, failed: rows.length, errors: [(e as Error).message] });
    } finally { setImporting(false); }
  }

  return (
    <div style={{ display: "grid", gap: 20, maxWidth: 760 }} className="fade-up">
      <div>
        <h1>Import &amp; export</h1>
        <p className="muted" style={{ fontSize: 14, marginTop: 4 }}>
          Back up your transactions to a CSV file, or bring data in from a CSV. <Link href="/settings">Back to settings</Link>
        </p>
      </div>

      {/* Export */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>Export</h2>
        <p className="muted" style={{ fontSize: 13, marginTop: -4 }}>
          Downloads all your transactions as a CSV in PocketCare’s own format — which you can re-import here anytime.
        </p>
        <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
          <button className="btn" onClick={doExport} disabled={exporting}>{exporting ? "Preparing…" : "Export transactions (CSV)"}</button>
          {exportMsg && <span className="muted" style={{ fontSize: 13 }}>{exportMsg}</span>}
        </div>
      </section>

        {/* Import */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 12 }}>
        <h2>Import</h2>
        {hasActiveTrial && !isPremiumUser ? (
          <div className="card" style={{ padding: 12, fontSize: 14, background: "var(--accent-ghost)", borderColor: "var(--accent-soft)" }}>
            Importing data is not available during the free trial. Please upgrade to Premium to import your historical data.
          </div>
        ) : (
          <>
            <label style={{ display: "grid", gap: 4 }}>
              <span className="muted" style={{ fontSize: 13 }}>File format</span>
              <select className="input" value={adapterId} onChange={(e) => { setAdapterId(e.target.value); setRows(null); setResult(null); }}>
                {IMPORT_ADAPTERS.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}
              </select>
            </label>

            <label style={{ display: "grid", gap: 4 }}>
              <span className="muted" style={{ fontSize: 13 }}>CSV file</span>
              <input className="input" type="file" accept=".csv,text/csv,text/plain" onChange={onFile} />
            </label>

            <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 14 }}>
              <input type="checkbox" checked={skipDup} onChange={(e) => setSkipDup(e.target.checked)} />
              Skip rows that already exist (same account, amount, type &amp; date)
            </label>

            {parseErr && <div className="card" style={{ padding: 12, fontSize: 13, borderColor: "var(--negative)", color: "var(--negative)" }}>{parseErr}</div>}

            {rows && (
              <div style={{ display: "grid", gap: 10 }}>
                <div style={{ fontSize: 14 }}><strong>{rows.length}</strong> transaction{rows.length === 1 ? "" : "s"} found in {fileName}. Preview:</div>
                <div style={{ overflowX: "auto" }}>
                  <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13, minWidth: 420 }}>
                    <thead><tr style={{ textAlign: "left", borderBottom: "2px solid var(--border)" }}>
                      <th style={{ padding: "6px 8px" }}>Date</th><th>Type</th><th>Amount</th><th>Account</th><th>Category</th>
                    </tr></thead>
                    <tbody>
                      {rows.slice(0, 6).map((r, i) => (
                        <tr key={i} style={{ borderBottom: "1px solid var(--border)" }}>
                          <td style={{ padding: "6px 8px" }}>{new Date(r.date).toLocaleDateString()}</td>
                          <td>{r.type}</td>
                          <td>{r.currency} {r.amount}</td>
                          <td>{r.account}</td>
                          <td className="muted">{r.category ?? "—"}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <button className="btn" onClick={runImport} disabled={importing}>{importing ? "Importing…" : `Import ${rows.length} transaction${rows.length === 1 ? "" : "s"}`}</button>
              </div>
            )}

            {result && (
              <div className="card" style={{ padding: 12, fontSize: 14, display: "grid", gap: 4, background: "var(--surface-2)" }}>
                <div><strong>{result.created}</strong> imported · {result.skipped} skipped · {result.failed} failed</div>
                {result.errors.length > 0 && <div className="muted" style={{ fontSize: 12 }}>First issues: {result.errors.slice(0, 3).join("; ")}</div>}
              </div>
            )}

            <p className="muted" style={{ fontSize: 12 }}>
              New accounts and categories are created automatically (accounts default to “savings” — you can change the type afterward). Importing recomputes balances from your ledger. The Wallet by BudgetBakers importer is in beta — transfers may need a quick review.
            </p>
          </>
        )}
      </section>
    </div>
  );
}
