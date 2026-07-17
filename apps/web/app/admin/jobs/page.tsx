"use client";

import { useState } from "react";
import { getSupabase } from "../../../src/powersync";

interface JobDef { fn: string; title: string; desc: string }
const JOBS: JobDef[] = [
  { fn: "fx-sync", title: "Currency rates (fx-sync)", desc: "Fetches daily FX rates into exchange_rates. Drives base-currency conversion app-wide." },
  { fn: "market-sync", title: "Stock/MF prices (market-sync)", desc: "Fetches Alpha Vantage quotes/dividends into the market_* tables for held symbols." },
];

interface Result { ok: boolean; body: unknown; ms: number }

export default function AdminJobs() {
  const [running, setRunning] = useState<string | null>(null);
  const [results, setResults] = useState<Record<string, Result>>({});

  async function run(fn: string) {
    setRunning(fn);
    const started = Date.now();
    try {
      const { data, error } = await getSupabase().functions.invoke(fn, { body: {} });
      const ms = Date.now() - started;
      if (error) {
        // Supabase wraps non-2xx as a FunctionsHttpError; try to surface the body.
        let body: unknown = error.message;
        try { body = await (error as { context?: Response }).context?.json(); } catch { /* keep message */ }
        setResults((r) => ({ ...r, [fn]: { ok: false, body: body ?? error.message, ms } }));
      } else {
        setResults((r) => ({ ...r, [fn]: { ok: true, body: data, ms } }));
      }
    } catch (e) {
      setResults((r) => ({ ...r, [fn]: { ok: false, body: e instanceof Error ? e.message : String(e), ms: Date.now() - started } }));
    } finally {
      setRunning(null);
    }
  }

  return (
    <div style={{ display: "grid", gap: 24 }}>
      <div>
        <h1 style={{ margin: 0 }}>Scheduled jobs</h1>
        <p style={{ color: "#888", margin: "6px 0 0" }}>Trigger the scheduled edge functions manually and inspect their output or errors.</p>
      </div>

      <div style={{ display: "grid", gap: 16 }}>
        {JOBS.map((j) => {
          const res = results[j.fn];
          const busy = running === j.fn;
          return (
            <div key={j.fn} style={{ background: "#1c1c1c", border: "1px solid #333", borderRadius: 12, padding: 20, display: "grid", gap: 12 }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12, flexWrap: "wrap" }}>
                <div>
                  <h3 style={{ margin: 0 }}>{j.title}</h3>
                  <p style={{ color: "#888", margin: "4px 0 0", fontSize: 13, maxWidth: 560 }}>{j.desc}</p>
                </div>
                <button
                  onClick={() => run(j.fn)}
                  disabled={busy}
                  style={{ background: busy ? "#444" : "#b06a4f", color: "#fff", border: "none", borderRadius: 8, padding: "10px 16px", cursor: busy ? "default" : "pointer", fontWeight: 600, whiteSpace: "nowrap" }}
                >
                  {busy ? "Running…" : "Run now"}
                </button>
              </div>

              {res && (
                <div style={{ borderTop: "1px solid #333", paddingTop: 12, display: "grid", gap: 6 }}>
                  <div style={{ display: "flex", gap: 10, alignItems: "center", fontSize: 13 }}>
                    <span style={{ display: "inline-flex", alignItems: "center", gap: 6, color: res.ok ? "#7bbf6a" : "#e0755f", fontWeight: 600 }}>
                      <span style={{ width: 8, height: 8, borderRadius: 999, background: res.ok ? "#7bbf6a" : "#e0755f" }} />
                      {res.ok ? "Success" : "Failed"}
                    </span>
                    <span style={{ color: "#888" }}>{res.ms} ms</span>
                  </div>
                  <pre style={{ margin: 0, background: "#111", border: "1px solid #333", borderRadius: 8, padding: 12, color: res.ok ? "#cfe8c6" : "#f0c6bd", fontSize: 12, overflowX: "auto", whiteSpace: "pre-wrap", wordBreak: "break-word" }}>
                    {typeof res.body === "string" ? res.body : JSON.stringify(res.body, null, 2)}
                  </pre>
                </div>
              )}
            </div>
          );
        })}
      </div>

      <p style={{ color: "#666", fontSize: 12, margin: 0 }}>
        These run with your admin session's JWT. Functions still enforce their own auth/secrets; a 401/403 here usually means the function requires a service role or a secret that isn't set.
      </p>
    </div>
  );
}
