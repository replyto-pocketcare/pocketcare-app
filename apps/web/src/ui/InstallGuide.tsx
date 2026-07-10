"use client";

import { useState } from "react";
import { useInstallPrompt, type Platform } from "../pwa";
import { DownloadIcon } from "./icons";

// --- small inline glyphs used as the "graphics" in the steps ---
const IosShareIcon = ({ size = 18 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <path d="M12 15V3m0 0 4 4m-4-4L8 7" />
    <path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7" />
  </svg>
);
const AddBoxIcon = ({ size = 18 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <rect x="4" y="4" width="16" height="16" rx="3" />
    <path d="M12 8v8M8 12h8" />
  </svg>
);
const KebabIcon = ({ size = 18 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
    <circle cx="12" cy="5" r="1.6" /><circle cx="12" cy="12" r="1.6" /><circle cx="12" cy="19" r="1.6" />
  </svg>
);

function Step({ n, icon, children }: { n: number; icon?: React.ReactNode; children: React.ReactNode }) {
  return (
    <li style={{ display: "flex", gap: 10, alignItems: "flex-start", fontSize: 14, lineHeight: 1.5 }}>
      <span style={{ flexShrink: 0, width: 22, height: 22, borderRadius: 999, background: "var(--accent-ghost)", color: "var(--accent)", fontSize: 12, fontWeight: 700, display: "grid", placeItems: "center" }}>{n}</span>
      <span style={{ display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap" }}>{children}{icon && <span style={{ color: "var(--text-2)", display: "inline-flex" }}>{icon}</span>}</span>
    </li>
  );
}

function IosSteps() {
  return (
    <ol style={{ display: "grid", gap: 10, margin: 0, padding: 0, listStyle: "none" }}>
      <Step n={1}>Open PocketCare in <strong>Safari</strong> (Chrome on iPhone can’t add to the Home Screen).</Step>
      <Step n={2} icon={<IosShareIcon />}>Tap the <strong>Share</strong> button in the toolbar</Step>
      <Step n={3} icon={<AddBoxIcon />}>Scroll down and tap <strong>Add to Home Screen</strong></Step>
      <Step n={4}>Tap <strong>Add</strong> — PocketCare appears on your Home Screen like a native app.</Step>
    </ol>
  );
}
function AndroidSteps() {
  return (
    <ol style={{ display: "grid", gap: 10, margin: 0, padding: 0, listStyle: "none" }}>
      <Step n={1} icon={<KebabIcon />}>In Chrome, tap the <strong>⋮ menu</strong> (top-right)</Step>
      <Step n={2} icon={<AddBoxIcon />}>Tap <strong>Install app</strong> (or <strong>Add to Home screen</strong>)</Step>
      <Step n={3}>Confirm <strong>Install</strong> — it’s added to your app drawer and home screen.</Step>
    </ol>
  );
}
function DesktopSteps() {
  return (
    <ol style={{ display: "grid", gap: 10, margin: 0, padding: 0, listStyle: "none" }}>
      <Step n={1} icon={<DownloadIcon size={16} />}>Click the <strong>install icon</strong> at the right of the address bar…</Step>
      <Step n={2} icon={<KebabIcon />}>…or open the <strong>⋮ menu</strong> → <strong>Install PocketCare</strong></Step>
      <Step n={3}>Confirm <strong>Install</strong> — it opens in its own window.</Step>
    </ol>
  );
}

const STEPS: Record<Platform, () => React.JSX.Element> = {
  ios: IosSteps, android: AndroidSteps, desktop: DesktopSteps, unknown: DesktopSteps,
};

/** Install button (where supported) + concise, platform-specific manual steps. */
export function InstallGuide() {
  const { canInstall, promptInstall, platform, standalone } = useInstallPrompt();
  const [msg, setMsg] = useState<string | null>(null);
  const Steps = STEPS[platform];

  if (standalone) {
    return <p className="muted" style={{ fontSize: 14, margin: 0 }}>✓ PocketCare is installed — you’re using the app.</p>;
  }

  return (
    <div style={{ display: "grid", gap: 14 }}>
      <p className="muted" style={{ fontSize: 13, margin: 0 }}>
        Install PocketCare for a full-screen, offline-first app on your phone or desktop — no app store needed.
      </p>

      {canInstall && (
        <button className="btn" style={{ justifyContent: "center", gap: 8 }}
          onClick={async () => { const r = await promptInstall(); setMsg(r === "accepted" ? "Installing…" : r === "dismissed" ? "No problem — you can install anytime." : null); }}>
          <DownloadIcon size={16} /> Install app
        </button>
      )}
      {msg && <span className="muted" style={{ fontSize: 12 }}>{msg}</span>}

      <div style={{ display: "grid", gap: 8 }}>
        {canInstall && <div className="muted" style={{ fontSize: 12, fontWeight: 600 }}>Or do it manually:</div>}
        <div className="card" style={{ padding: 16, background: "var(--surface-2)" }}>
          <div style={{ fontSize: 12, fontWeight: 700, textTransform: "uppercase", letterSpacing: "0.06em", color: "var(--text-2)", marginBottom: 10 }}>
            {platform === "ios" ? "On iPhone / iPad (Safari)" : platform === "android" ? "On Android (Chrome)" : "On desktop (Chrome / Edge)"}
          </div>
          <Steps />
        </div>
      </div>
    </div>
  );
}
