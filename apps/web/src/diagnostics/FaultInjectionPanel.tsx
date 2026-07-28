"use client";

/**
 * Dev-only: force sync failures on demand.
 *
 * Every bug in this area has been one that reasoning missed and only running
 * the code would have caught — a deferred constraint that could never hold, a
 * getSnapshot that looped React, a stuck-op detector that could never fire.
 * The common factor is that these paths are *unreachable in normal use*: you
 * cannot casually produce an RLS denial or a foreign-key violation, so nobody
 * ever exercises the code that handles them until a user hits it in the wild.
 *
 * This makes them reachable in one tap.
 *
 * GATING: hidden unless `NEXT_PUBLIC_ENABLE_FAULT_INJECTION` is set, or on
 * localhost. A shipped build with this visible would be a way to break a real
 * user's sync, so the gate is deliberately not a runtime toggle.
 */
import { useEffect, useState } from "react";
import { getFaultInjection, setFaultInjection, type FaultInjection } from "@pocketcare/db";
import { classifyFailure, explainForUser, MAX_PERMANENT_ATTEMPTS } from "@pocketcare/sync-policy";

/** The failures that have actually bitten us, plus the common transient ones. */
const PRESETS: { label: string; code: string; status: number; note: string }[] = [
  { label: "RLS denial", code: "42501", status: 403, note: "the split_group_members incident" },
  { label: "Foreign key", code: "23503", status: 409, note: "orphaned child row" },
  { label: "Check constraint", code: "23514", status: 400, note: "the 0040 sum trigger" },
  { label: "Unique violation", code: "23505", status: 409, note: "duplicate insert" },
  { label: "Server error", code: "", status: 503, note: "transient — must NOT quarantine" },
  { label: "Deadlock", code: "40001", status: 500, note: "transient despite looking fatal" },
];

const TABLES = [
  "*",
  "transactions",
  "expenses",
  "expense_items",
  "split_groups",
  "split_group_members",
  "settlements",
  "accounts",
];

function enabled(): boolean {
  if (process.env.NEXT_PUBLIC_ENABLE_FAULT_INJECTION === "true") return true;
  if (typeof window === "undefined") return false;
  return window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1";
}

export function FaultInjectionPanel() {
  const [active, setActive] = useState<FaultInjection | null>(null);
  const [table, setTable] = useState("*");

  useEffect(() => { setActive(getFaultInjection()); }, []);

  if (!enabled()) return null;

  function apply(preset: (typeof PRESETS)[number]) {
    const fault: FaultInjection = {
      table,
      code: preset.code,
      status: preset.status,
      message: `injected: ${preset.label}`,
    };
    setFaultInjection(fault);
    setActive(fault);
  }

  function clear() {
    setFaultInjection(null);
    setActive(null);
  }

  const classification = active
    ? classifyFailure({ code: active.code, status: active.status, message: active.message })
    : null;

  return (
    <section
      className="card"
      style={{ padding: 18, display: "grid", gap: 12, borderStyle: "dashed" }}
    >
      <div>
        <strong>Fault injection</strong>{" "}
        <span className="chip" style={{ fontSize: 10.5 }}>DEV</span>
        <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>
          Force uploads to fail so the retry, quarantine and recovery paths can
          actually be exercised. Never shown in production.
        </p>
      </div>

      <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, maxWidth: 260 }}>
        Fail uploads to
        <select className="input" value={table} onChange={(e) => setTable(e.target.value)}>
          {TABLES.map((t) => (
            <option key={t} value={t}>{t === "*" ? "every table" : t}</option>
          ))}
        </select>
      </label>

      <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
        {PRESETS.map((p) => (
          <button
            key={p.label}
            className="chip"
            type="button"
            data-active={active?.code === p.code && active?.status === p.status}
            onClick={() => apply(p)}
            title={p.note}
          >
            {p.label}
          </button>
        ))}
      </div>

      {active ? (
        <div
          style={{
            display: "grid",
            gap: 6,
            padding: 10,
            borderRadius: 8,
            background: "color-mix(in srgb, var(--negative) 12%, transparent)",
            fontSize: 12.5,
          }}
        >
          <strong>
            Injecting {active.message} on {active.table === "*" ? "every table" : active.table}
          </strong>
          {/* Shows what the policy will DO with it — the thing worth verifying. */}
          <span className="muted">
            Classified <strong>{classification?.cls}</strong> — {classification?.reason}
          </span>
          <span className="muted">
            User would see: “{explainForUser({ code: active.code, status: active.status })}”
          </span>
          <span className="muted">
            {classification?.cls === "permanent"
              ? `After ${MAX_PERMANENT_ATTEMPTS} attempts it moves to “Problems syncing” and the queue unblocks.`
              : "Retries forever — it must never be quarantined."}
          </span>
          <button className="btn" type="button" onClick={clear} style={{ justifySelf: "start" }}>
            Stop injecting
          </button>
        </div>
      ) : (
        <span className="muted" style={{ fontSize: 12 }}>
          No fault active. Pick one, then make a change in the app and watch Diagnostics.
        </span>
      )}
    </section>
  );
}
