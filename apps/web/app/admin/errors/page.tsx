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
 * users is a release regression. Expanding a row shows exactly who.
 *
 * STYLING: the admin console is a DARK surface with hardcoded hex (see
 * AdminShell: #111 background, #eee text). It does NOT use the app's CSS
 * custom properties, which are light — using `.card` or `var(--surface-2)`
 * here renders white-on-white.
 */
import { useEffect, useMemo, useState } from "react";

import {
  getAdminClientErrorUsers,
  getAdminClientErrors,
  resolveAdminClientError,
  type AdminClientError,
  type AdminErrorUser,
} from "../../../src/admin-actions";

const PANEL = "#222";
const PANEL_DARK = "#1a1a1a";
const BORDER = "#333";
const TEXT = "#eee";
const MUTED = "#888";

const cell: React.CSSProperties = { padding: "12px 14px", verticalAlign: "top", fontSize: 13, color: TEXT };
const headCell: React.CSSProperties = {
  ...cell,
  fontSize: 11,
  color: MUTED,
  textTransform: "uppercase",
  letterSpacing: "0.05em",
  fontWeight: 600,
};

const inputStyle: React.CSSProperties = {
  padding: "8px 12px",
  borderRadius: 8,
  border: `1px solid ${BORDER}`,
  background: PANEL,
  color: "#fff",
  fontSize: 13,
};

const btn = (primary = false): React.CSSProperties => ({
  padding: "8px 14px",
  borderRadius: 8,
  border: `1px solid ${primary ? "transparent" : BORDER}`,
  background: primary ? "#2b6" : "#2a2a2a",
  color: primary ? "#000" : TEXT,
  fontSize: 12.5,
  fontWeight: 600,
  cursor: "pointer",
});

function ago(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const m = Math.round(ms / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.round(h / 24)}d ago`;
}

/** Who is hitting one error. Loaded on demand — most rows are never expanded. */
function AffectedUsers({ fingerprint }: { fingerprint: string }) {
  const [users, setUsers] = useState<AdminErrorUser[] | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    void getAdminClientErrorUsers(fingerprint).then((res) => {
      if (res.ok) setUsers(res.data);
      else setErr(res.error);
    });
  }, [fingerprint]);

  if (err) return <div style={{ color: "#f88", fontSize: 12 }}>{err}</div>;
  if (users === null) return <div style={{ color: MUTED, fontSize: 12 }}>Loading affected users…</div>;
  if (users.length === 0) return <div style={{ color: MUTED, fontSize: 12 }}>No user rows.</div>;

  return (
    <div style={{ marginTop: 10, border: `1px solid ${BORDER}`, borderRadius: 8, overflow: "hidden" }}>
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ background: PANEL_DARK }}>
            <th style={{ ...headCell, padding: "8px 12px" }}>User</th>
            <th style={{ ...headCell, padding: "8px 12px", width: 70 }}>Times</th>
            <th style={{ ...headCell, padding: "8px 12px", width: 130 }}>Platform</th>
            <th style={{ ...headCell, padding: "8px 12px", width: 150 }}>Last route</th>
            <th style={{ ...headCell, padding: "8px 12px", width: 110 }}>Last seen</th>
          </tr>
        </thead>
        <tbody>
          {users.map((u, i) => (
            <tr key={`${u.user_id ?? "deleted"}-${i}`} style={{ borderTop: `1px solid ${BORDER}` }}>
              <td style={{ ...cell, padding: "8px 12px" }}>
                <div style={{ fontWeight: 600 }}>{u.name}</div>
                {u.email && <div style={{ color: MUTED, fontSize: 11.5 }}>{u.email}</div>}
                {u.user_id && (
                  <div style={{ color: "#666", fontSize: 11, fontFamily: "monospace" }}>
                    {u.user_id.slice(0, 8)}…
                  </div>
                )}
              </td>
              <td style={{ ...cell, padding: "8px 12px" }}>{u.count}</td>
              <td style={{ ...cell, padding: "8px 12px", color: MUTED }}>
                {[u.platform, u.app_version && `v${u.app_version}`].filter(Boolean).join(" · ") || "—"}
              </td>
              <td style={{ ...cell, padding: "8px 12px", color: MUTED, wordBreak: "break-all" }}>{u.route || "—"}</td>
              <td style={{ ...cell, padding: "8px 12px", color: MUTED, whiteSpace: "nowrap" }}>{ago(u.last_seen)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
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

  if (error) return <div style={{ padding: 24, color: "#f88" }}>{error}</div>;

  return (
    <div style={{ display: "grid", gap: 16, color: TEXT }}>
      <div>
        <h1 style={{ margin: 0, color: TEXT }}>Errors</h1>
        <p style={{ margin: "4px 0 0", fontSize: 13, color: MUTED }}>
          Reported automatically from users&apos; devices, grouped by fingerprint.
          Amounts, names and contact details are stripped before sending.
        </p>
      </div>

      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
        <input
          placeholder="Search message, scope, route…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{ ...inputStyle, flex: "1 1 260px", minWidth: 0 }}
        />
        <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13, color: MUTED }}>
          <input type="checkbox" checked={includeResolved} onChange={(e) => setIncludeResolved(e.target.checked)} />
          Include resolved
        </label>
        <button type="button" onClick={() => load(includeResolved)} style={btn()}>Refresh</button>
      </div>

      {rows === null ? (
        <p style={{ color: MUTED }}>Loading…</p>
      ) : filtered.length === 0 ? (
        <div style={{ background: PANEL, border: `1px solid ${BORDER}`, borderRadius: 12, padding: 24, textAlign: "center" }}>
          <strong>Nothing reported.</strong>
          <p style={{ margin: "6px 0 0", fontSize: 13, color: MUTED }}>
            {includeResolved ? "No errors on record." : "No unresolved errors — that's the good outcome."}
          </p>
        </div>
      ) : (
        <div style={{ background: PANEL, borderRadius: 12, border: `1px solid ${BORDER}`, overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", minWidth: 720 }}>
            <thead>
              <tr style={{ background: PANEL_DARK, borderBottom: `1px solid ${BORDER}`, textAlign: "left" }}>
                <th style={headCell}>Error</th>
                <th style={{ ...headCell, width: 90 }}>Users</th>
                <th style={{ ...headCell, width: 80 }}>Times</th>
                <th style={{ ...headCell, width: 110 }}>Last seen</th>
                <th style={{ ...headCell, width: 100 }} />
              </tr>
            </thead>
            <tbody>
              {filtered.map((r) => {
                const open = expanded.has(r.fingerprint);
                return (
                  <tr key={r.fingerprint} style={{ borderTop: `1px solid ${BORDER}` }}>
                    <td style={cell}>
                      <button
                        type="button"
                        onClick={() => toggle(r.fingerprint)}
                        style={{
                          textAlign: "left", background: "none", border: "none", padding: 0,
                          cursor: "pointer", color: TEXT, font: "inherit", width: "100%",
                        }}
                        aria-expanded={open}
                      >
                        <div style={{ fontWeight: 600, wordBreak: "break-word" }}>
                          <span style={{ color: MUTED, marginRight: 6 }}>{open ? "▾" : "▸"}</span>
                          {r.message}
                        </div>
                        <div style={{ color: MUTED, fontSize: 11.5, marginTop: 3, paddingLeft: 18 }}>
                          {[r.scope, r.route, r.platform, r.app_version && `v${r.app_version}`]
                            .filter(Boolean)
                            .join(" · ")}
                          {r.resolved_at ? " · resolved" : ""}
                        </div>
                      </button>

                      {open && (
                        <div style={{ paddingLeft: 18 }}>
                          {r.detail && (
                            <pre
                              style={{
                                margin: "8px 0 0", padding: 10, borderRadius: 8,
                                background: "#000", color: "#8fd", border: `1px solid ${BORDER}`,
                                fontSize: 11, overflow: "auto", whiteSpace: "pre-wrap", wordBreak: "break-word",
                              }}
                            >
                              {JSON.stringify(r.detail, null, 2)}
                            </pre>
                          )}
                          <AffectedUsers fingerprint={r.fingerprint} />
                        </div>
                      )}
                    </td>
                    {/* Many users = a real regression. One user, huge count = a retry loop. */}
                    <td style={{ ...cell, fontWeight: r.affected_users > 1 ? 700 : 400, color: r.affected_users > 1 ? "#fc8" : TEXT }}>
                      {r.affected_users}
                    </td>
                    <td style={cell}>{r.count}</td>
                    <td style={{ ...cell, color: MUTED, whiteSpace: "nowrap" }}>{ago(r.last_seen)}</td>
                    <td style={cell}>
                      {!r.resolved_at && (
                        <button
                          type="button"
                          disabled={busy === r.fingerprint}
                          onClick={() => void resolve(r.fingerprint)}
                          style={{ ...btn(), padding: "5px 10px", fontSize: 12 }}
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

      <p style={{ fontSize: 11.5, margin: 0, color: MUTED }}>
        Resolved errors re-open automatically if they happen again.
      </p>
    </div>
  );
}
