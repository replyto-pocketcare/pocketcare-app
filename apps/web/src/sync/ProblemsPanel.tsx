"use client";

/**
 * Settings → "Problems syncing".
 *
 * The visible half of the dead-letter queue. Quarantining a rejected write
 * unblocks the upload queue, but on its own it just moves the data somewhere
 * nobody can see — which is the same loss with a better excuse. This is where
 * the user meets it.
 *
 * WRITTEN FOR A PERSON, NOT A MAINTAINER. The heading names the thing
 * ("Fresh Mart · ₹1,122.50 · 12 Jun"), the explanation says what happened in
 * plain words ("You don't have permission to save this — you may have been
 * removed from the group"), and the SQLSTATE is tucked behind a disclosure for
 * a support conversation. Nobody should have to know what 42501 means to
 * recover their own expenses.
 *
 * The panel renders nothing at all when there's nothing wrong. A permanently
 * visible "problems" box teaches people to ignore it.
 */
import { useCallback, useEffect, useState } from "react";

import { Spinner } from "../ui/Spinner";
import { downloadExport } from "./repair";
import {
  discardFailedWrite,
  exportFailedWrites,
  listFailedWrites,
  retryFailedWrite,
  type FailedWrite,
} from "./deadletter";

export function ProblemsPanel() {
  const [items, setItems] = useState<FailedWrite[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [confirming, setConfirming] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setItems(await listFailedWrites());
    setLoading(false);
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function retry(item: FailedWrite) {
    setBusy(item.id);
    const res = await retryFailedWrite(item);
    setBusy(null);
    if (res.ok) {
      await refresh();
    } else {
      setErrors((e) => ({ ...e, [item.id]: res.error ?? "Still not accepted." }));
    }
  }

  async function retryAll() {
    setBusy("all");
    // Sequential, not parallel: these often depend on each other, and a parent
    // succeeding is frequently what makes the child's retry work.
    for (const item of items) await retryFailedWrite(item);
    setBusy(null);
    await refresh();
  }

  async function discard(item: FailedWrite) {
    setBusy(item.id);
    await discardFailedWrite(item);
    setBusy(null);
    setConfirming(null);
    await refresh();
  }

  // Nothing wrong → say nothing. Silence is the correct empty state here.
  if (loading || items.length === 0) return null;

  return (
    <section
      id="problems"
      className="card"
      style={{
        padding: 18,
        display: "grid",
        gap: 12,
        borderColor: "var(--negative)",
      }}
    >
      <div>
        <strong>Problems syncing</strong>
        <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>
          {items.length} change{items.length === 1 ? "" : "s"} couldn&apos;t be saved to the
          server. {items.length === 1 ? "It's" : "They're"} still on this device — nothing has
          been lost. Everything else is syncing normally.
        </p>
      </div>

      <div style={{ display: "grid", gap: 10 }}>
        {items.map((item) => (
          <div
            key={item.id}
            style={{
              display: "grid",
              gap: 6,
              padding: 12,
              borderRadius: 10,
              background: "color-mix(in srgb, var(--negative) 10%, transparent)",
            }}
          >
            <strong style={{ fontSize: 13.5 }}>{item.label}</strong>
            <span className="muted" style={{ fontSize: 12.5 }}>
              {item.explanation}
            </span>

            {errors[item.id] && (
              <span style={{ fontSize: 12, color: "var(--negative)" }}>
                Tried again — still not accepted.
              </span>
            )}

            <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginTop: 2 }}>
              <button
                className="btn"
                type="button"
                disabled={busy !== null}
                onClick={() => void retry(item)}
              >
                {busy === item.id ? "Trying…" : "Try again"}
              </button>
              <button
                className="btn ghost"
                type="button"
                onClick={() => downloadExport(exportFailedWrites([item]))}
              >
                Save a copy
              </button>
              {confirming === item.id ? (
                <button
                  className="btn ghost"
                  type="button"
                  disabled={busy !== null}
                  style={{ color: "var(--negative)" }}
                  onClick={() => void discard(item)}
                >
                  Download a copy and discard
                </button>
              ) : (
                <button
                  className="btn ghost"
                  type="button"
                  onClick={() => setConfirming(item.id)}
                >
                  Discard
                </button>
              )}
            </div>

            {/* Technical detail exists for support, and stays out of the way. */}
            <details style={{ fontSize: 11.5 }}>
              <summary className="muted" style={{ cursor: "pointer" }}>
                Technical details
              </summary>
              <div className="muted" style={{ paddingTop: 4, wordBreak: "break-word" }}>
                {item.table} · {item.op} · {item.code ?? "no code"} · attempt {item.attempts}
                <br />
                {item.message}
              </div>
            </details>
          </div>
        ))}
      </div>

      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <button
          className="btn"
          type="button"
          disabled={busy !== null}
          onClick={() => void retryAll()}
        >
          {busy === "all" ? (
            <span style={{ display: "inline-flex", gap: 6, alignItems: "center" }}>
              <Spinner /> Trying…
            </span>
          ) : (
            `Try all ${items.length} again`
          )}
        </button>
        <button
          className="btn ghost"
          type="button"
          onClick={() => downloadExport(exportFailedWrites(items))}
        >
          Save a copy of everything
        </button>
      </div>
    </section>
  );
}
