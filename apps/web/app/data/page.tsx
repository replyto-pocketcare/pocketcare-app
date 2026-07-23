"use client";

import { useState } from "react";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { downloadText } from "../../src/data/csv";
import { exportTransactionsCsv } from "../../src/data/exportCsv";
import { IMPORT_ADAPTERS, parseWithAdapter, type CanonRow } from "../../src/data/adapters";
import { importTransactions, type ImportResult } from "../../src/data/importCsv";
import { usePremiumStatus } from "../../src/premium";

export default function DataPage() {
  const { t } = useTranslation("data");
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
      if (count === 0) { setExportMsg(t("noExport")); return; }
      downloadText(`pocketcare-transactions-${new Date().toISOString().slice(0, 10)}.csv`, csv);
      setExportMsg(t("exported", { count }));
    } catch (e) {
      setExportMsg(t("exportFailed", { msg: (e as Error).message }));
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
      if (parsed.length === 0) { setParseErr(t("noRows")); return; }
      setRows(parsed);
    } catch (err) {
      setParseErr(t("readFail", { msg: (err as Error).message }));
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
        <h1>{t("title")}</h1>
        <p className="muted" style={{ fontSize: 14, marginTop: 4 }}>
          {t("introPre")}<Link href="/settings">{t("backToSettings")}</Link>
        </p>
      </div>

      {/* Export */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>{t("export")}</h2>
        <p className="muted" style={{ fontSize: 13, marginTop: -4 }}>
          {t("exportNote")}
        </p>
        <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
          <button className="btn" onClick={doExport} disabled={exporting}>{exporting ? t("preparing") : t("exportBtn")}</button>
          {exportMsg && <span className="muted" style={{ fontSize: 13 }}>{exportMsg}</span>}
        </div>
      </section>

        {/* Import */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 12 }}>
        <h2>{t("import")}</h2>
        {hasActiveTrial && !isPremiumUser ? (
          <div className="card" style={{ padding: 12, fontSize: 14, background: "var(--accent-ghost)", borderColor: "var(--accent-soft)" }}>
            {t("trialNote")}
          </div>
        ) : (
          <>
            <label style={{ display: "grid", gap: 4 }}>
              <span className="muted" style={{ fontSize: 13 }}>{t("fileFormat")}</span>
              <select className="input" value={adapterId} onChange={(e) => { setAdapterId(e.target.value); setRows(null); setResult(null); }}>
                {IMPORT_ADAPTERS.map((a) => <option key={a.id} value={a.id}>{a.label}</option>)}
              </select>
            </label>

            <label style={{ display: "grid", gap: 4 }}>
              <span className="muted" style={{ fontSize: 13 }}>{t("csvFile")}</span>
              <input className="input" type="file" accept=".csv,text/csv,text/plain" onChange={onFile} />
            </label>

            <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 14 }}>
              <input type="checkbox" checked={skipDup} onChange={(e) => setSkipDup(e.target.checked)} />
              {t("skipDup")}
            </label>

            {parseErr && <div className="card" style={{ padding: 12, fontSize: 13, borderColor: "var(--negative)", color: "var(--negative)" }}>{parseErr}</div>}

            {rows && (
              <div style={{ display: "grid", gap: 10 }}>
                <div style={{ fontSize: 14 }}>{t("foundPreview", { count: rows.length, file: fileName })}</div>
                <div style={{ overflowX: "auto" }}>
                  <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13, minWidth: 420 }}>
                    <thead><tr style={{ textAlign: "left", borderBottom: "2px solid var(--border)" }}>
                      <th style={{ padding: "6px 8px" }}>{t("thDate")}</th><th>{t("thType")}</th><th>{t("thAmount")}</th><th>{t("thAccount")}</th><th>{t("thCategory")}</th>
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
                <button className="btn" onClick={runImport} disabled={importing}>{importing ? t("importing") : t("importBtn", { count: rows.length })}</button>
              </div>
            )}

            {result && (
              <div className="card" style={{ padding: 12, fontSize: 14, display: "grid", gap: 4, background: "var(--surface-2)" }}>
                <div>{t("resultLine", { created: result.created, skipped: result.skipped, failed: result.failed })}</div>
                {result.errors.length > 0 && <div className="muted" style={{ fontSize: 12 }}>{t("firstIssues", { issues: result.errors.slice(0, 3).join("; ") })}</div>}
              </div>
            )}

            <p className="muted" style={{ fontSize: 12 }}>
              {t("footerNote")}
            </p>
          </>
        )}
      </section>
    </div>
  );
}
