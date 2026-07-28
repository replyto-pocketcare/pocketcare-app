"use client";

/**
 * Settings → "Check for unsynced data".
 *
 * The recovery half of the fault-tolerance work. A user who hit a stuck queue
 * — or who was told to discard one — may have rows sitting on their device
 * that never reached the server. To them the data simply vanished.
 *
 * Deliberate choices:
 * - **Export before repair, always.** Offered up front, not buried behind a
 *   confirm. Nothing here should ever be the last copy of someone's data.
 * - **Rows are described, not counted.** "Fresh Mart · ₹1,122.50 · 12 Jun"
 *   lets someone confirm it's theirs; "3 rows in expenses" does not.
 * - **Nothing is deleted here.** Repair only ever adds. Discarding is a
 *   separate, later decision on the Problems screen.
 */
import { useState } from "react";

import { Spinner } from "../ui/Spinner";
import {
  downloadExport,
  exportStranded,
  repairStranded,
  scanForStranded,
  type RepairResult,
  type StrandedRow,
} from "./repair";

type Stage = "idle" | "scanning" | "found" | "clean" | "repairing" | "done" | "error";

export function RepairPanel() {
  const [stage, setStage] = useState<Stage>("idle");
  const [rows, setRows] = useState<StrandedRow[]>([]);
  const [unchecked, setUnchecked] = useState<string[]>([]);
  const [result, setResult] = useState<RepairResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function scan() {
    setStage("scanning");
    setError(null);
    try {
      const res = await scanForStranded();
      setRows(res.stranded);
      setUnchecked(res.unchecked);
      setStage(res.stranded.length > 0 ? "found" : "clean");
    } catch (e) {
      setError((e as Error).message);
      setStage("error");
    }
  }

  async function repair() {
    setStage("repairing");
    try {
      const res = await repairStranded(rows);
      setResult(res);
      setStage("done");
    } catch (e) {
      setError((e as Error).message);
      setStage("error");
    }
  }

  const byTable = rows.reduce<Record<string, StrandedRow[]>>((acc, r) => {
    (acc[r.table] ??= []).push(r);
    return acc;
  }, {});

  return (
    <section className="card" style={{ padding: 18, display: "grid", gap: 12 }}>
      <div>
        <strong>Check for unsynced data</strong>
        <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>
          Compares what&apos;s on this device against the server and re-uploads anything
          that never made it. Safe to run any time — it only ever adds.
        </p>
      </div>

      {stage === "idle" && (
        <button className="btn" type="button" onClick={() => void scan()} style={{ justifySelf: "start" }}>
          Check now
        </button>
      )}

      {stage === "scanning" && (
        <div style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13 }}>
          <Spinner /> Comparing this device with the server…
        </div>
      )}

      {stage === "clean" && (
        <>
          <div style={{ fontSize: 13.5 }}>
            <strong>Everything is synced.</strong>{" "}
            <span className="muted">Nothing on this device is missing from the server.</span>
          </div>
          {unchecked.length > 0 && (
            <span className="muted" style={{ fontSize: 11.5 }}>
              Couldn&apos;t check: {unchecked.join(", ")}. Try again when you have a stable connection.
            </span>
          )}
          <button className="btn ghost" type="button" onClick={() => setStage("idle")} style={{ justifySelf: "start" }}>
            Check again
          </button>
        </>
      )}

      {stage === "found" && (
        <>
          <div
            style={{
              display: "grid",
              gap: 8,
              padding: 12,
              borderRadius: 10,
              background: "color-mix(in srgb, var(--warning, #c08a3e) 14%, transparent)",
            }}
          >
            <strong style={{ fontSize: 13.5 }}>
              {rows.length} item{rows.length === 1 ? "" : "s"} on this device never reached the server
            </strong>
            <span className="muted" style={{ fontSize: 12 }}>
              They&apos;re safe here, but they aren&apos;t backed up and won&apos;t appear on your
              other devices. Save a copy first, then upload them.
            </span>
          </div>

          {/* Described, not counted — recognition is what reassures someone. */}
          <div style={{ display: "grid", gap: 10, maxHeight: 300, overflow: "auto" }}>
            {Object.entries(byTable).map(([table, items]) => (
              <div key={table} style={{ display: "grid", gap: 4 }}>
                <span className="muted" style={{ fontSize: 11, textTransform: "uppercase", letterSpacing: "0.05em" }}>
                  {table.replace(/_/g, " ")} ({items.length})
                </span>
                <ul style={{ margin: 0, paddingLeft: 18, fontSize: 12.5 }}>
                  {items.slice(0, 12).map((r) => (
                    <li key={r.id}>{r.label}</li>
                  ))}
                  {items.length > 12 && (
                    <li className="muted">…and {items.length - 12} more</li>
                  )}
                </ul>
              </div>
            ))}
          </div>

          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button
              className="btn ghost"
              type="button"
              onClick={() => downloadExport(exportStranded(rows))}
            >
              Save a copy
            </button>
            <button className="btn" type="button" onClick={() => void repair()}>
              Upload {rows.length} item{rows.length === 1 ? "" : "s"}
            </button>
          </div>
        </>
      )}

      {stage === "repairing" && (
        <div style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13 }}>
          <Spinner /> Uploading…
        </div>
      )}

      {stage === "done" && result && (
        <>
          <div style={{ fontSize: 13.5 }}>
            <strong>Uploaded {result.uploaded} item{result.uploaded === 1 ? "" : "s"}.</strong>
          </div>
          {result.failed.length > 0 && (
            <div style={{ display: "grid", gap: 6 }}>
              <span style={{ fontSize: 13, color: "var(--negative)" }}>
                {result.failed.length} still couldn&apos;t be uploaded:
              </span>
              <ul style={{ margin: 0, paddingLeft: 18, fontSize: 12 }} className="muted">
                {result.failed.slice(0, 8).map((f) => (
                  <li key={`${f.table}-${f.id}`}>{f.label} — {f.error}</li>
                ))}
              </ul>
              <span className="muted" style={{ fontSize: 11.5 }}>
                Save a copy so nothing is lost, then send it to support.
              </span>
              <button
                className="btn ghost"
                type="button"
                style={{ justifySelf: "start" }}
                onClick={() => downloadExport(exportStranded(rows))}
              >
                Save a copy
              </button>
            </div>
          )}
          <button className="btn ghost" type="button" onClick={() => setStage("idle")} style={{ justifySelf: "start" }}>
            Check again
          </button>
        </>
      )}

      {stage === "error" && (
        <>
          <div style={{ color: "var(--negative)", fontSize: 13 }}>{error}</div>
          <button className="btn ghost" type="button" onClick={() => setStage("idle")} style={{ justifySelf: "start" }}>
            Try again
          </button>
        </>
      )}
    </section>
  );
}
