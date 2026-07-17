"use client";

import { useState } from "react";
import { usePathname } from "next/navigation";
import { Modal } from "./Modal";
import { insertRow } from "../write";

const SEVERITIES: { id: "fatal" | "high" | "medium" | "low"; label: string; color: string }[] = [
  { id: "fatal", label: "Fatal", color: "var(--negative)" },
  { id: "high", label: "High", color: "#d98324" },
  { id: "medium", label: "Medium", color: "var(--accent)" },
  { id: "low", label: "Low", color: "var(--text-2)" },
];

const AREAS = [
  "Dashboard", "Transactions", "Accounts & Cards", "Budgets", "Goals",
  "Investments", "Friends & Splits", "Subscriptions", "Loans",
  "Ask PocketCare", "Insights", "Settings & Billing", "Sync / Offline", "Other",
];

const APP_VERSION = "0.1.0";

function captureContext(route: string) {
  if (typeof navigator === "undefined") return { route } as Record<string, string | number | boolean>;
  const platform = /iPhone|iPad|iPod/.test(navigator.userAgent) ? "iOS"
    : /Android/.test(navigator.userAgent) ? "Android"
    : navigator.platform || "desktop";
  return {
    app_version: APP_VERSION,
    route,
    platform,
    user_agent: navigator.userAgent.slice(0, 300),
    viewport: `${window.innerWidth}x${window.innerHeight}`,
    online: navigator.onLine ? 1 : 0,
  };
}

/** Low-effort bug/suggestion report: pick severity + area, write the issue.
 *  Everything else (version, page, device) is captured automatically. */
export function BugReportModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const pathname = usePathname();
  const [kind, setKind] = useState<"bug" | "suggestion">("bug");
  const [severity, setSeverity] = useState<"fatal" | "high" | "medium" | "low">("medium");
  const [area, setArea] = useState<string>("");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const isBug = kind === "bug";

  function reset() {
    setKind("bug"); setSeverity("medium"); setArea(""); setTitle(""); setDescription(""); setDone(false); setErr(null);
  }

  async function submit() {
    setErr(null);
    if (!description.trim()) { setErr(isBug ? "Please describe the issue." : "Please describe your suggestion."); return; }
    setBusy(true);
    try {
      await insertRow("bug_reports", {
        kind, severity: isBug ? severity : null, area: area || null, title: title.trim() || null,
        description: description.trim(), status: "open",
        ...captureContext(pathname),
      });
      setDone(true);
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Couldn't submit. Try again.");
    } finally { setBusy(false); }
  }

  return (
    <Modal open={open} onClose={() => { onClose(); setTimeout(reset, 200); }}>
      {done ? (
        <div style={{ display: "grid", gap: 10, textAlign: "center" }}>
          <div style={{ fontSize: 34 }}>🙏</div>
          <h2 style={{ margin: 0 }}>Thanks for the {isBug ? "report" : "suggestion"}!</h2>
          <p className="muted" style={{ margin: 0, fontSize: 14 }}>
            {isBug
              ? <>Beta testers who report <strong>5 bugs get a free month of Lite</strong>, and <strong>25 unlock Pro</strong> — your reward coupon shows up in Settings → Billing.</>
              : <>We read every suggestion — thanks for helping shape PocketCare.</>}
          </p>
          <div style={{ display: "flex", gap: 8, justifyContent: "center", marginTop: 6 }}>
            <button className="btn ghost" onClick={reset}>Send another</button>
            <button className="btn" onClick={() => { onClose(); setTimeout(reset, 200); }}>Done</button>
          </div>
        </div>
      ) : (
        <div style={{ display: "grid", gap: 12 }}>
          <div>
            <h2 style={{ margin: 0 }}>Send feedback</h2>
            <p className="muted" style={{ fontSize: 12, margin: "4px 0 0" }}>Pick a couple of options and tell us — we capture the rest automatically.</p>
          </div>

          {/* Bug vs Suggestion segmenting */}
          <div style={{ display: "flex", gap: 6 }}>
            {(["bug", "suggestion"] as const).map((k) => (
              <button key={k} type="button" className="chip" data-active={kind === k} style={{ flex: 1, textTransform: "capitalize" }} onClick={() => setKind(k)}>
                {k === "bug" ? "🐞 Bug" : "💡 Suggestion"}
              </button>
            ))}
          </div>

          {isBug && (
            <div style={{ display: "grid", gap: 6 }}>
              <span className="muted" style={{ fontSize: 12 }}>Severity</span>
              <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                {SEVERITIES.map((s) => (
                  <button key={s.id} type="button" className="chip" data-active={severity === s.id} onClick={() => setSeverity(s.id)}
                    style={severity === s.id ? { borderColor: s.color, color: s.color } : undefined}>{s.label}</button>
                ))}
              </div>
            </div>
          )}

          <label style={{ display: "grid", gap: 6 }}>
            <span className="muted" style={{ fontSize: 12 }}>Which area?</span>
            <select className="input" value={area} onChange={(e) => setArea(e.target.value)}>
              <option value="">Select a page / feature…</option>
              {AREAS.map((a) => <option key={a} value={a}>{a}</option>)}
            </select>
          </label>

          <input className="input" placeholder="Short title (optional)" value={title} onChange={(e) => setTitle(e.target.value)} />
          <textarea className="input" rows={4}
            placeholder={isBug ? "What went wrong? What did you expect to happen?" : "What would make PocketCare better?"}
            value={description} onChange={(e) => setDescription(e.target.value)} style={{ resize: "vertical" }} />

          <p className="muted" style={{ fontSize: 11, margin: 0 }}>Automatically included: app version, current page, device, and connection status.</p>
          {err && <div style={{ color: "var(--negative)", fontSize: 13 }}>{err}</div>}

          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
            <button className="btn ghost" onClick={() => { onClose(); setTimeout(reset, 200); }}>Cancel</button>
            <button className="btn" onClick={submit} disabled={busy || !description.trim()}>{busy ? "Sending…" : isBug ? "Send report" : "Send suggestion"}</button>
          </div>
        </div>
      )}
    </Modal>
  );
}
