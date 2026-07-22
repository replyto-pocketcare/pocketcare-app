"use client";

import { useEffect, useState } from "react";
import { useCryptoStatus, setupEncryption, unlock, unlockWithRecovery, lock, refreshKeyState } from "./session";
import { issueSupportGrant, revokeGrant, activeGrants, type ActiveGrant } from "./support";

export function SecurityPanel() {
  const status = useCryptoStatus();
  useEffect(() => { void refreshKeyState(); }, []);

  return (
    <section className="card" style={{ padding: 20, display: "grid", gap: 12 }}>
      <div>
        <h2 style={{ margin: 0 }}>Security &amp; encryption</h2>
        <p className="muted" style={{ fontSize: 12, margin: "4px 0 0" }}>
          End-to-end encrypt sensitive fields (notes, names) with a passphrase only you know. We store only the encrypted form — support can never read it without your explicit, time-limited consent.
        </p>
      </div>
      {status === "loading" ? <span className="muted" style={{ fontSize: 13 }}>Checking…</span>
        : status === "unset" ? <SetupBox />
        : status === "locked" ? <UnlockBox />
        : <UnlockedBox />}
    </section>
  );
}

function SetupBox() {
  const [pass, setPass] = useState("");
  const [pass2, setPass2] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [recovery, setRecovery] = useState<string | null>(null);

  async function go() {
    setErr(null);
    if (pass.length < 8) { setErr("Use at least 8 characters."); return; }
    if (pass !== pass2) { setErr("Passphrases don't match."); return; }
    setBusy(true);
    try { setRecovery(await setupEncryption(pass)); }
    catch (e) { setErr(e instanceof Error ? e.message : "Setup failed."); }
    finally { setBusy(false); }
  }

  if (recovery) {
    return (
      <div style={{ display: "grid", gap: 10 }}>
        <div className="card" style={{ padding: 14, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)" }}>
          <strong>Save your recovery code</strong>
          <p className="muted" style={{ fontSize: 12, margin: "4px 0 8px" }}>Store it somewhere safe — a password manager or written down offline. We can’t show it again.</p>
          <div style={{ fontFamily: "var(--font-mono, monospace)", fontSize: 16, letterSpacing: "0.06em", userSelect: "all", padding: "8px 10px", background: "var(--surface)", borderRadius: 8, border: "1px solid var(--border)" }}>{recovery}</div>
        </div>
        <div className="card" style={{ padding: 14, background: "var(--negative-ghost, rgba(200,60,60,0.08))", border: "1px solid var(--negative)" }}>
          <strong style={{ color: "var(--negative)" }}>⚠︎ There is no other way back in</strong>
          <p style={{ fontSize: 12.5, lineHeight: 1.5, margin: "4px 0 0" }}>
            Your passphrase and this recovery code are the <strong>only two keys</strong> to your
            encrypted fields. If you <strong>forget the passphrase AND lose this code</strong>, that
            data is <strong>permanently unrecoverable</strong> — not by you, and <strong>not by our
            support team</strong>. We never see your passphrase or your keys, so there is nothing we
            can reset or restore. Please save the code before continuing.
          </p>
        </div>
        <button className="btn" onClick={() => setRecovery(null)}>I understand — I’ve saved it</button>
      </div>
    );
  }
  return (
    <div style={{ display: "grid", gap: 8, maxWidth: 380 }}>
      <div className="card" style={{ padding: 12, background: "var(--surface-2)", fontSize: 12.5, lineHeight: 1.5 }}>
        <strong>Choose a passphrase you won’t forget.</strong> It never leaves your device, so we
        can’t reset or recover it. You’ll get a one-time recovery code as backup — if you lose
        <strong> both</strong>, your encrypted data can’t be recovered by anyone, including support.
      </div>
      <input className="input" type="password" placeholder="Create a passphrase (8+ chars)" value={pass} onChange={(e) => setPass(e.target.value)} />
      <input className="input" type="password" placeholder="Confirm passphrase" value={pass2} onChange={(e) => setPass2(e.target.value)} />
      {err && <span style={{ color: "var(--negative)", fontSize: 13 }}>{err}</span>}
      <button className="btn" onClick={() => void go()} disabled={busy || !pass}>{busy ? "Setting up…" : "Turn on encryption"}</button>
    </div>
  );
}

function UnlockBox() {
  const [val, setVal] = useState("");
  const [mode, setMode] = useState<"passphrase" | "recovery">("passphrase");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function go() {
    setErr(null); setBusy(true);
    try { mode === "passphrase" ? await unlock(val) : await unlockWithRecovery(val); }
    catch { setErr(mode === "passphrase" ? "Wrong passphrase." : "Invalid recovery code."); }
    finally { setBusy(false); }
  }
  return (
    <div style={{ display: "grid", gap: 8, maxWidth: 380 }}>
      <span className="muted" style={{ fontSize: 13 }}>Encryption is on. Unlock to read and write protected fields on this device.</span>
      <input className="input" type="password" placeholder={mode === "passphrase" ? "Passphrase" : "Recovery code"} value={val} onChange={(e) => setVal(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void go(); }} />
      {err && <span style={{ color: "var(--negative)", fontSize: 13 }}>{err}</span>}
      <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
        <button className="btn" onClick={() => void go()} disabled={busy || !val}>{busy ? "Unlocking…" : "Unlock"}</button>
        <button className="chip" onClick={() => { setMode(mode === "passphrase" ? "recovery" : "passphrase"); setErr(null); setVal(""); }}>
          {mode === "passphrase" ? "Use recovery code" : "Use passphrase"}
        </button>
      </div>
    </div>
  );
}

function UnlockedBox() {
  return (
    <div style={{ display: "grid", gap: 12 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
        <span style={{ fontSize: 14, color: "var(--positive)" }}>● Unlocked — protected fields are readable on this device.</span>
        <button className="chip" onClick={() => lock()}>Lock</button>
      </div>
      <SupportAccess />
    </div>
  );
}

function SupportAccess() {
  const [grants, setGrants] = useState<ActiveGrant[]>([]);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const refresh = () => { void activeGrants().then(setGrants); };
  useEffect(() => { refresh(); const t = setInterval(refresh, 30_000); return () => clearInterval(t); }, []);

  async function grant(scope: "content" | "structural") {
    setBusy(true); setMsg(null);
    try { const r = await issueSupportGrant(scope, 2); setMsg(`Granted ${scope} access until ${new Date(r.expiresAt).toLocaleTimeString()}.`); refresh(); }
    catch (e) { setMsg(e instanceof Error ? e.message : "Couldn't create grant."); }
    finally { setBusy(false); }
  }

  return (
    <div className="card" style={{ padding: 14, background: "var(--surface-2)", display: "grid", gap: 8 }}>
      <strong style={{ fontSize: 14 }}>Grant temporary support access</strong>
      <p className="muted" style={{ fontSize: 12, margin: 0 }}>
        Lets our support team help you for <strong>2 hours</strong>, then it expires automatically. Structural access only checks for sync problems (no data is read). Content access lets support decrypt your fields to debug — every access is logged.
      </p>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <button className="chip" disabled={busy} onClick={() => void grant("structural")}>Allow sync check (2h)</button>
        <button className="chip" disabled={busy} onClick={() => void grant("content")}>Allow data access (2h)</button>
      </div>
      {msg && <span className="muted" style={{ fontSize: 12 }}>{msg}</span>}
      {grants.length > 0 && (
        <div style={{ display: "grid", gap: 6, marginTop: 4 }}>
          {grants.map((g) => (
            <div key={g.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, fontSize: 12 }}>
              <span>{g.scope === "content" ? "Data access" : "Sync check"} · expires {new Date(g.expires_at).toLocaleTimeString()}</span>
              <button className="chip" onClick={async () => { await revokeGrant(g.id); refresh(); }}>Revoke</button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
