"use client";

/**
 * Settings → Notifications. Enables browser Web Push (so alerts arrive with the
 * app closed but the browser running in the background) and toggles which
 * triggers fire. Prefs live in `notification_prefs` (synced); the push
 * subscription lives in `push_subscriptions` (server-side).
 */
import { useState } from "react";
import { useNotifPrefs, updatePrefs } from "./hooks";
import { enablePush, disablePush, pushSupported, pushPermission } from "./push";

function Toggle({ on, onChange, label, hint }: { on: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
  return (
    <label style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, cursor: "pointer" }}>
      <span style={{ display: "grid", gap: 1 }}>
        <span style={{ fontSize: 14 }}>{label}</span>
        {hint && <span className="muted" style={{ fontSize: 12 }}>{hint}</span>}
      </span>
      <span
        role="switch" aria-checked={on} onClick={() => onChange(!on)}
        style={{
          width: 42, height: 24, borderRadius: 999, flexShrink: 0, position: "relative", cursor: "pointer",
          background: on ? "var(--accent)" : "var(--border-strong)", transition: "background .15s",
        }}>
        <span style={{
          position: "absolute", top: 2, left: on ? 20 : 2, width: 20, height: 20, borderRadius: 999,
          background: "#fff", transition: "left .15s", boxShadow: "0 1px 2px rgba(0,0,0,.3)",
        }} />
      </span>
    </label>
  );
}

export function NotificationPanel() {
  const prefs = useNotifPrefs();
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const supported = pushSupported();
  const perm = pushPermission();
  const pushOn = !!prefs?.push_enabled;

  async function togglePush(next: boolean) {
    setErr(null); setBusy(true);
    try {
      if (next) {
        const r = await enablePush();
        if (!r.ok) {
          setErr(
            r.reason === "denied" ? "Notifications are blocked in your browser settings — allow them for this site and try again."
            : r.reason === "unsupported" ? "This browser can't deliver background notifications."
            : r.reason === "missing-vapid-key" ? "Push isn't configured on the server yet."
            : r.reason);
          return;
        }
        await updatePrefs({ push_enabled: 1 });
      } else {
        await disablePush();
        await updatePrefs({ push_enabled: 0 });
      }
    } finally { setBusy(false); }
  }

  const set = (patch: Record<string, number>) => void updatePrefs(patch);

  return (
    <section className="card" style={{ padding: 20, display: "grid", gap: 14 }}>
      <div style={{ display: "grid", gap: 2 }}>
        <h2 style={{ margin: 0, fontSize: 16 }}>Notifications</h2>
        <span className="muted" style={{ fontSize: 12.5 }}>
          Get alerted about bills, budgets, low balances and unusual spend. For alerts while the app is closed,
          keep the browser running in the background.
        </span>
      </div>

      {!supported ? (
        <div className="muted" style={{ fontSize: 13 }}>Background push isn't supported in this browser. In-app notifications still work.</div>
      ) : (
        <Toggle on={pushOn} onChange={(v) => !busy && void togglePush(v)}
          label={busy ? "Working…" : "Push notifications"}
          hint={perm === "denied" ? "Blocked in browser settings" : "Deliver alerts to this device"} />
      )}
      {err && <div style={{ color: "var(--negative)", fontSize: 12.5 }}>{err}</div>}

      <div style={{ height: 1, background: "var(--border)" }} />

      <Toggle on={!!prefs?.emi_due} onChange={(v) => set({ emi_due: v ? 1 : 0 })}
        label="Upcoming EMIs & bills" hint={`Alert ${prefs?.emi_lead_days ?? 3} days before due`} />
      <Toggle on={!!prefs?.budget} onChange={(v) => set({ budget: v ? 1 : 0 })}
        label="Budget limits" hint="When you cross 80% and 100% of a budget" />
      <Toggle on={!!prefs?.low_balance} onChange={(v) => set({ low_balance: v ? 1 : 0 })}
        label="Low balance" hint="When an account drops below your floor" />
      <Toggle on={!!prefs?.outlier} onChange={(v) => set({ outlier: v ? 1 : 0 })}
        label="Unusual transactions" hint="Large or out-of-pattern spends" />

      <div style={{ height: 1, background: "var(--border)" }} />
      <div className="muted" style={{ fontSize: 11, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.06em" }}>Groups & trips</div>

      <Toggle on={prefs ? !!prefs.group_invite : true} onChange={(v) => set({ group_invite: v ? 1 : 0 })}
        label="Group activity" hint="When someone joins a group or trip you're in" />
      <Toggle on={prefs ? !!prefs.group_expense : true} onChange={(v) => set({ group_expense: v ? 1 : 0 })}
        label="Shared expenses" hint="When someone adds an expense to split" />
    </section>
  );
}
