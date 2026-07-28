"use client";

/**
 * Settings → Diagnostics.
 *
 * Deliberately shows the log rather than hiding it behind a "send" button:
 * a user who can see "upload failed · expense_items · 23514" can tell you that
 * over WhatsApp in one message, which is usually faster than any round-trip
 * through a bug tracker.
 */
import { useEffect, useState, useSyncExternalStore } from "react";
import { useQuery } from "@powersync/react";

import { useSyncStatus } from "../sync";
import { getDb } from "../powersync";
import { clearEntries, exportLog, getEntries, getServerEntries, subscribe } from "./log";

const APP_VERSION = "0.1.0";

/** Rows still waiting to reach the server — the number that explains "not syncing". */
function useUploadQueueDepth(): number | null {
  const [depth, setDepth] = useState<number | null>(null);
  useEffect(() => {
    let alive = true;
    const read = async () => {
      try {
        const db = getDb();
        const stats = await (db as unknown as {
          getUploadQueueStats?: () => Promise<{ count: number }>;
        })?.getUploadQueueStats?.();
        if (alive) setDepth(stats?.count ?? null);
      } catch {
        if (alive) setDepth(null);
      }
    };
    void read();
    const t = setInterval(read, 4000);
    return () => { alive = false; clearInterval(t); };
  }, []);
  return depth;
}

export function DiagnosticsPanel() {
  const sync = useSyncStatus();
  const queued = useUploadQueueDepth();
  const [copied, setCopied] = useState(false);
  const [expanded, setExpanded] = useState(false);

  // useSyncExternalStore keeps this in step with the ring buffer without
  // polling. Both snapshot functions MUST return a stable reference — an
  // inline `() => []` allocates a new array per call and loops React forever.
  const entries = useSyncExternalStore(subscribe, getEntries, getServerEntries);

  const { data: pendingBug = [] } = useQuery<{ n: number }>(
    "SELECT COUNT(*) AS n FROM bug_reports WHERE deleted_at IS NULL",
  );

  const errors = entries.filter((e) => e.level === "error");
  const context = {
    version: APP_VERSION,
    connected: sync.connected,
    hasSynced: sync.hasSynced,
    lastSyncedAt: sync.lastSyncedAt?.toISOString() ?? "never",
    queuedWrites: queued ?? "unknown",
    syncError: sync.error ?? "none",
    reportsFiled: pendingBug[0]?.n ?? 0,
  };

  async function share() {
    const text = exportLog(context);
    try {
      // navigator.share is the good path on a phone — it opens WhatsApp,
      // Mail, wherever — and is exactly where this needs to end up.
      if (typeof navigator !== "undefined" && navigator.share) {
        await navigator.share({ title: "PocketCare diagnostics", text });
        return;
      }
      await navigator.clipboard?.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      /* user dismissed the share sheet */
    }
  }

  const statusLine = !sync.online
    ? "Offline — changes are saved on this device and will sync later."
    : sync.error
      ? "Sync is failing. The details below will tell us why."
      : sync.connected
        ? "Connected."
        : "Not connected.";

  return (
    <section className="card" style={{ padding: 18, display: "grid", gap: 12 }}>
      <div>
        <strong>Diagnostics</strong>
        <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>
          If something isn&apos;t working, share this with support. Amounts, names and
          contact details are removed automatically.
        </p>
      </div>

      {/* At-a-glance status — answers "is it syncing?" without reading a log. */}
      <div
        style={{
          display: "grid",
          gap: 8,
          gridTemplateColumns: "repeat(auto-fit, minmax(min(140px, 100%), 1fr))",
        }}
      >
        <Stat label="Status" value={sync.online ? (sync.connected ? "Connected" : "Connecting") : "Offline"} />
        <Stat label="Last synced" value={sync.lastSyncedAt ? sync.lastSyncedAt.toLocaleTimeString() : "Never"} />
        <Stat label="Waiting to upload" value={queued === null ? "—" : String(queued)} warn={!!queued && queued > 0} />
        <Stat label="Errors logged" value={String(errors.length)} warn={errors.length > 0} />
      </div>

      <p className="muted" style={{ fontSize: 12.5, margin: 0 }}>{statusLine}</p>

      {sync.error && (
        <div
          style={{
            fontSize: 12.5,
            padding: "8px 10px",
            borderRadius: 8,
            background: "color-mix(in srgb, var(--negative) 12%, transparent)",
            wordBreak: "break-word",
          }}
        >
          {sync.error}
        </div>
      )}

      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <button className="btn" type="button" onClick={() => void share()}>
          {copied ? "Copied" : "Share diagnostics"}
        </button>
        <button className="btn ghost" type="button" onClick={() => setExpanded((v) => !v)} aria-expanded={expanded}>
          {expanded ? "Hide log" : `Show log (${entries.length})`}
        </button>
        {entries.length > 0 && (
          <button className="btn ghost" type="button" onClick={clearEntries}>
            Clear
          </button>
        )}
      </div>

      {expanded && (
        <pre
          style={{
            margin: 0,
            padding: 10,
            borderRadius: 8,
            background: "var(--surface-2)",
            fontSize: 11,
            lineHeight: 1.5,
            maxHeight: 320,
            overflow: "auto",
            whiteSpace: "pre-wrap",
            wordBreak: "break-word",
          }}
        >
          {entries.length === 0
            ? "Nothing logged yet — that's a good sign."
            : entries
                .slice()
                .reverse()
                .map((e) => `${new Date(e.at).toLocaleTimeString()} ${e.level.toUpperCase()} [${e.scope}] ${e.message}`)
                .join("\n")}
        </pre>
      )}
    </section>
  );
}

function Stat({ label, value, warn = false }: { label: string; value: string; warn?: boolean }) {
  return (
    <div
      style={{
        display: "grid",
        gap: 2,
        padding: "8px 10px",
        borderRadius: 10,
        background: warn ? "color-mix(in srgb, var(--negative) 10%, transparent)" : "var(--surface-2)",
        minWidth: 0,
      }}
    >
      <span className="muted" style={{ fontSize: 11.5 }}>{label}</span>
      <strong style={{ fontSize: 14, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
        {value}
      </strong>
    </div>
  );
}
