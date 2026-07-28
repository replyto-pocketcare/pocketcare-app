"use client";

/**
 * Admin → Errors.
 *
 * Auto-reported client failures, grouped by fingerprint. Nobody had to file a
 * bug report for these to be here — which is the point, because most users
 * never do. They just stop using the app.
 *
 * Triage on two numbers: how many users are hitting it, and when it last
 * happened. A high count from one user is a retry loop; a low count across many
 * users is a release regression.
 */
import { useEffect, useMemo, useState } from "react";

import {
  getAdminClientErrors,
  resolveAdminClientError,
  type AdminClientError,
} from "../../../src/admin-actions";

const cell: React.CSSProperties = { padding: "12px 14px", verticalAlign: "top", fontSize: 13 };

function ago(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const m = Math.round(ms / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.round(h / 24)}d ago`;
}

export default function AdminErrorsPage() {
  const [rows, setRows] = useState<AdminClientError[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [includeResolved, setIncludeResolved] = useState(false);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState("");
  const [busy, setBusy] = useState<string | null>(null);

  const load = (resolved: boolean) => {
    setRows(null);
    void getAdminClientErrors(resolved).then((res) => {
      if (res.ok) setRows(res.data);
      else setError(res.error);
    });
  };

  useEffect(() => { load(includeResolved); }, [includeResolved]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return rows ?? [];
    return (rows ?? []).filter((r) =>
      [r.message, r.scope, r.route, r.platform, JSON.stringify(r.detail)]
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
        .includes(q),
    );
  }, [rows, search]);

  async function resolve(fp: string) {
    setBusy(fp);
    const res = await resolveAdminClientError(fp);
    setBusy(null);
    if (res.ok) load(includeResolved);
    else setError(res.error);
  }

  const toggle = (id: string) =>
    setExpanded((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });

  if (error) return <div style={{ padding: 24, color: "var(--negative)" }}>{error}</div>;

  return (
    <div style={{ display: "grid", gap: 16 }}>
      <div>
        <h1 style={{ margin: 0 }}>Errors</h1>
        <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>
          Reported automatically from users&apos; devices, grouped by fingerprint.
          Amounts, names and contact details are stripped before sending.
        </p>
      </div>

      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
        <input
          className="input"
          placeholder="Search message, scope, route…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{ flex: "1 1 260px", minWidth: 0 }}
        />
        <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13 }}>
          <input type="checkbox" checked={includeResolved} onChange={(e) => setIncludeResolved(e.target.checked)} />
          Include resolved
        </label>
        <button className="btn ghost" type="button" onClick={() => load(includeResolved)}>Refresh</button>
      </div>

      {rows === null ? (
        <p className="muted">Loading…</p>
      ) : filtered.length === 0 ? (
        <div className="card" style={{ padding: 24, textAlign: "center" }}>
          <strong>Nothing reported.</strong>
          <p className="muted" style={{ margin: "6px 0 0", fontSize: 13 }}>
            {includeResolved ? "No errors on record." : "No unresolved errors — that's the good outcome."}
          </p>
        </div>
      ) : (
        <div className="card" style={{ padding: 0, overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", minWidth: 720 }}>
            <thead>
              <tr style={{ textAlign: "left", fontSize: 11.5, color: "var(--text-2)", textTransform: "uppercase", letterSpacing: "0.04em" }}>
                <th style={cell}>Error</th>
                <th style={{ ...cell, width: 90 }}>Users</th>
                <th style={{ ...cell, width: 80 }}>Times</th>
                <th style={{ ...cell, width: 110 }}>Last seen</th>
                <th style={{ ...cell, width: 100 }} />
              </tr>
            </thead>
            <tbody>
              {filtered.map((r) => {
                const open = expanded.has(r.fingerprint);
                return (
                  <tr key={r.fingerprint} style={{ borderTop: "1px solid var(--border)" }}>
                    <td style={cell}>
                      <button
                        type="button"
                        onClick={() => toggle(r.fingerprint)}
                        style={{ textAlign: "left", background: "none", border: "none", padding: 0, cursor: "pointer", color: "inherit", font: "inherit", width: "100%" }}
                      >
                        <div style={{ fontWeight: 600, wordBreak: "break-word" }}>{r.message}</div>
                        <div className="muted" style={{ fontSize: 11.5, marginTop: 3 }}>
                          {[r.scope, r.route, r.platform, r.app_version && `v${r.app_version}`]
                            .filter(Boolean)
                            .join(" · ")}
                          {r.resolved_at ? " · resolved" : ""}
                        </div>
                      </button>

                      {open && r.detail && (
                        <pre
                          style={{
                            margin: "8px 0 0", padding: 10, borderRadius: 8, background: "var(--surface-2)",
                            fontSize: 11, overflow: "auto", whiteSpace: "pre-wrap", wordBreak: "break-word",
                          }}
                        >
                          {JSON.stringify(r.detail, null, 2)}
                        </pre>
                      )}
                    </td>
                    {/* Many users = a real regression. One user, huge count = a retry loop. */}
                    <td style={{ ...cell, fontWeight: r.affected_users > 1 ? 700 : 400 }}>{r.affected_users}</td>
                    <td style={cell}>{r.count}</td>
                    <td style={cell}>{ago(r.last_seen)}</td>
                    <td style={cell}>
                      {!r.resolved_at && (
                        <button
                          className="btn ghost"
                          type="button"
                          disabled={busy === r.fingerprint}
                          onClick={() => void resolve(r.fingerprint)}
                          style={{ padding: "4px 10px", minHeight: 0, height: 30, fontSize: 12 }}
                        >
                          {busy === r.fingerprint ? "…" : "Resolve"}
                        </button>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <p className="muted" style={{ fontSize: 11.5, margin: 0 }}>
        Resolved errors re-open automatically if they happen again.
      </p>
    </div>
  );
}
