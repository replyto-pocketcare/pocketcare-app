"use client";

import { useEffect, useMemo, useState } from "react";
import { getAdminFeedback } from "../../../src/admin-actions";
import { Spinner } from "../../../src/ui/Spinner";
import { AdminError } from "../AdminError";

type Row = Record<string, any>;

const SEVERITY_ORDER: Record<string, number> = { fatal: 0, high: 1, medium: 2, low: 3 };

const SORTS = {
  newest: { label: "Newest first", fn: (a: Row, b: Row) => +new Date(b.created_at) - +new Date(a.created_at) },
  oldest: { label: "Oldest first", fn: (a: Row, b: Row) => +new Date(a.created_at) - +new Date(b.created_at) },
  severity: {
    label: "Severity (fatal → low)",
    fn: (a: Row, b: Row) =>
      (SEVERITY_ORDER[a.severity] ?? 9) - (SEVERITY_ORDER[b.severity] ?? 9) ||
      +new Date(b.created_at) - +new Date(a.created_at),
  },
  area: {
    label: "Area (A → Z)",
    fn: (a: Row, b: Row) =>
      String(a.area ?? "￿").localeCompare(String(b.area ?? "￿")) ||
      +new Date(b.created_at) - +new Date(a.created_at),
  },
} as const;
type SortKey = keyof typeof SORTS;

const inputStyle: React.CSSProperties = {
  padding: "10px 14px",
  borderRadius: 8,
  border: "1px solid #333",
  background: "#222",
  color: "#fff",
};

/** Build an LLM-ready prompt from the currently visible records. */
function buildLlmPrompt(rows: Row[]): string {
  const bugs = rows.filter((r) => r.kind === "bug");
  const suggestions = rows.filter((r) => r.kind !== "bug");

  const fmt = (r: Row, i: number) => {
    const ctx = [
      r.route && `route: ${r.route}`,
      r.app_version && `version: ${r.app_version}`,
      r.platform && `platform: ${r.platform}`,
      r.viewport && `viewport: ${r.viewport}`,
      r.online === false && "reported while OFFLINE",
    ]
      .filter(Boolean)
      .join(" · ");
    return [
      `### ${r.kind === "bug" ? "BUG" : "SUGGESTION"} ${i + 1}${r.title ? `: ${r.title}` : ""}`,
      r.kind === "bug" ? `- severity: ${r.severity ?? "unspecified"}` : null,
      `- area: ${r.area ?? "unspecified"}`,
      `- status: ${r.status ?? "open"} · reported: ${new Date(r.created_at).toISOString().slice(0, 10)}`,
      ctx ? `- context: ${ctx}` : null,
      `- description: ${String(r.description ?? "").trim()}`,
    ]
      .filter(Boolean)
      .join("\n");
  };

  return [
    "You are working on PocketCare, an offline-first personal finance PWA (Next.js App Router + PowerSync WASM SQLite synced to Supabase Postgres, Turborepo/pnpm monorepo, TypeScript strict). Money is integer minor units via @pocketcare/money; balances derive from an append-only ledger; sync is server-authoritative.",
    "",
    "Below are beta-tester bug reports and suggestions exported from the admin console.",
    "",
    "## Your tasks",
    "1. Triage the BUGS: group duplicates/related reports, then order by (severity, number of affected reports).",
    "2. For each distinct bug: state the likely root cause (use the route/platform/version context as clues), which files/modules are probably involved, and a concrete fix plan. Ask for specific files if you need them — do not guess code you haven't seen.",
    "3. For the SUGGESTIONS: propose an implementation plan per suggestion (effort estimate S/M/L, dependencies, risks), and a recommended priority order.",
    "4. Flag anything that looks like a data-integrity or security risk first.",
    "",
    `## Bug reports (${bugs.length})`,
    bugs.length ? bugs.map(fmt).join("\n\n") : "_none in current view_",
    "",
    `## Suggestions (${suggestions.length})`,
    suggestions.length ? suggestions.map(fmt).join("\n\n") : "_none in current view_",
    "",
  ].join("\n");
}

export default function AdminFeedback() {
  const [feedback, setFeedback] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  // filters
  const [filterKind, setFilterKind] = useState("all");
  const [filterSeverity, setFilterSeverity] = useState("all");
  const [filterArea, setFilterArea] = useState("all");
  const [filterStatus, setFilterStatus] = useState("all");
  const [search, setSearch] = useState("");
  const [sortKey, setSortKey] = useState<SortKey>("newest");

  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    getAdminFeedback().then((res) => {
      if (res.ok) setFeedback(res.data);
      else setError(res.error);
    });
  }, []);

  const areas = useMemo(
    () => [...new Set((feedback ?? []).map((f) => f.area).filter(Boolean))].sort() as string[],
    [feedback],
  );
  const statuses = useMemo(
    () => [...new Set((feedback ?? []).map((f) => f.status).filter(Boolean))].sort() as string[],
    [feedback],
  );

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return (feedback ?? [])
      .filter(
        (f) =>
          (filterKind === "all" || f.kind === filterKind) &&
          (filterSeverity === "all" || f.severity === filterSeverity) &&
          (filterArea === "all" || f.area === filterArea) &&
          (filterStatus === "all" || f.status === filterStatus) &&
          (!q ||
            [f.title, f.description, f.area, f.reporter_name, f.reporter_email, f.route]
              .filter(Boolean)
              .some((v) => String(v).toLowerCase().includes(q))),
      )
      .sort(SORTS[sortKey].fn);
  }, [feedback, filterKind, filterSeverity, filterArea, filterStatus, search, sortKey]);

  if (error) return <AdminError title="Couldn’t load feedback" message={error} />;
  if (!feedback) return <Spinner />;

  const toggleRow = (id: string) =>
    setExpanded((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });

  const exportPrompt = async () => {
    const prompt = buildLlmPrompt(filtered);
    try {
      await navigator.clipboard.writeText(prompt);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      /* clipboard blocked — fall through to download */
    }
    const blob = new Blob([prompt], { type: "text/markdown" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `pocketcare-feedback-prompt-${new Date().toISOString().slice(0, 10)}.md`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div style={{ display: "grid", gap: 30 }}>
      <h1>Beta Tester Feedback</h1>

      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
        <select value={filterKind} onChange={(e) => setFilterKind(e.target.value)} style={inputStyle}>
          <option value="all">All Feedback</option>
          <option value="bug">Bugs</option>
          <option value="suggestion">Suggestions</option>
        </select>

        <select value={filterSeverity} onChange={(e) => setFilterSeverity(e.target.value)} style={inputStyle}>
          <option value="all">Any severity</option>
          {["fatal", "high", "medium", "low"].map((s) => (
            <option key={s} value={s}>{s[0]!.toUpperCase() + s.slice(1)}</option>
          ))}
        </select>

        <select value={filterArea} onChange={(e) => setFilterArea(e.target.value)} style={inputStyle}>
          <option value="all">Any area</option>
          {areas.map((a) => (
            <option key={a} value={a}>{a}</option>
          ))}
        </select>

        {statuses.length > 1 && (
          <select value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} style={inputStyle}>
            <option value="all">Any status</option>
            {statuses.map((s) => (
              <option key={s} value={s}>{s}</option>
            ))}
          </select>
        )}

        <select value={sortKey} onChange={(e) => setSortKey(e.target.value as SortKey)} style={inputStyle}>
          {Object.entries(SORTS).map(([k, v]) => (
            <option key={k} value={k}>Sort: {v.label}</option>
          ))}
        </select>

        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search title, description, reporter…"
          style={{ ...inputStyle, flex: "1 1 220px", minWidth: 180 }}
        />

        <button
          onClick={exportPrompt}
          disabled={filtered.length === 0}
          style={{
            ...inputStyle,
            cursor: filtered.length ? "pointer" : "not-allowed",
            background: "var(--accent, #4a7c59)",
            border: "none",
            fontWeight: 600,
            opacity: filtered.length ? 1 : 0.5,
            whiteSpace: "nowrap",
          }}
          title="Copies an LLM-ready prompt of the records in the current view to the clipboard and downloads it as .md"
        >
          {copied ? "✓ Copied + downloaded" : `⤓ Export for LLM (${filtered.length})`}
        </button>
      </div>

      <div style={{ background: "#222", borderRadius: 12, border: "1px solid #333", overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left" }}>
          <thead>
            <tr style={{ borderBottom: "1px solid #333", background: "#1a1a1a" }}>
              <th style={{ padding: 16 }}>Date</th>
              <th style={{ padding: 16 }}>Reported by</th>
              <th style={{ padding: 16 }}>Kind</th>
              <th style={{ padding: 16 }}>Severity</th>
              <th style={{ padding: 16 }}>Area</th>
              <th style={{ padding: 16 }}>Title</th>
              <th style={{ padding: 16 }}>Description</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((f) => {
              const isOpen = expanded.has(f.id);
              return (
                <tr
                  key={f.id}
                  onClick={() => toggleRow(f.id)}
                  style={{ borderBottom: "1px solid #333", cursor: "pointer", verticalAlign: "top" }}
                  title={isOpen ? "Click to collapse" : "Click to expand"}
                >
                  <td style={{ padding: 16, fontSize: 13, color: "#888", whiteSpace: "nowrap" }}>
                    {new Date(f.created_at).toLocaleDateString()}
                  </td>
                  <td style={{ padding: 16, fontSize: 13, whiteSpace: "nowrap" }}>
                    {f.reporter_name || f.reporter_email
                      ? <>
                          {f.reporter_name && <div>{f.reporter_name}</div>}
                          {f.reporter_email && <div style={{ color: "#888", fontSize: 12 }}>{f.reporter_email}</div>}
                        </>
                      : <span style={{ color: "#666" }}>{f.user_id ? `${String(f.user_id).slice(0, 8)}…` : "—"}</span>}
                  </td>
                  <td style={{ padding: 16 }}>
                    <span style={{
                      padding: "4px 8px", borderRadius: 4, fontSize: 12, fontWeight: 600,
                      background: f.kind === "bug" ? "var(--warning-soft, #ff444433)" : "var(--accent-ghost)",
                      color: f.kind === "bug" ? "var(--warning, #ff4444)" : "var(--accent)"
                    }}>
                      {f.kind === "bug" ? "Bug" : "Suggestion"}
                    </span>
                  </td>
                  <td style={{ padding: 16 }}>{f.severity || "—"}</td>
                  <td style={{ padding: 16 }}>{f.area || "—"}</td>
                  <td style={{ padding: 16, fontWeight: 600, maxWidth: 220, overflowWrap: "break-word" }}>
                    {f.title || "—"}
                  </td>
                  <td style={{ padding: 16, maxWidth: 420 }}>
                    <div
                      style={
                        isOpen
                          ? { whiteSpace: "pre-wrap", overflowWrap: "break-word" }
                          : {
                              display: "-webkit-box",
                              WebkitLineClamp: 2,
                              WebkitBoxOrient: "vertical",
                              overflow: "hidden",
                              overflowWrap: "break-word",
                            }
                      }
                    >
                      {f.description}
                    </div>
                    {isOpen && (
                      <div style={{ marginTop: 10, fontSize: 12, color: "#888", display: "flex", gap: 12, flexWrap: "wrap" }}>
                        {f.route && <span>route: {f.route}</span>}
                        {f.app_version && <span>v{f.app_version}</span>}
                        {f.platform && <span>{f.platform}</span>}
                        {f.viewport && <span>{f.viewport}</span>}
                        {f.online === false && <span style={{ color: "var(--warning, #ff4444)" }}>offline</span>}
                        {f.status && <span>status: {f.status}</span>}
                      </div>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {filtered.length === 0 && (
          <div style={{ padding: 20, textAlign: "center", color: "#888" }}>No feedback matches the current filters.</div>
        )}
      </div>
    </div>
  );
}
