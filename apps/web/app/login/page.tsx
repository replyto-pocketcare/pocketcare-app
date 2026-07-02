"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabase } from "../../src/powersync";
import { Logo } from "../../src/ui/Logo";
import { PasswordInput } from "../../src/ui/PasswordInput";

type Mode = "register" | "signin";
type Step = "form" | "otp";

export default function LoginPage() {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("register");
  const [step, setStep] = useState<Step>("form");

  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [otp, setOtp] = useState("");

  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const emailTrim = email.trim();
  const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailTrim);

  function finishHome() {
    localStorage.setItem("onboardingSeen", "1");
    if (username.trim()) localStorage.setItem("username", username.trim());
    router.push("/");
  }

  // Step 1 (register): validate, save username, start email verification (sends OTP).
  async function startRegister() {
    setErr(null); setMsg(null);
    if (!username.trim()) return setErr("Please choose a display name.");
    if (!validEmail) return setErr("Enter a valid email address.");
    if (password.length < 8) return setErr("Password must be at least 8 characters.");
    if (password !== confirm) return setErr("Passwords don’t match.");
    setBusy(true);
    try {
      const supabase = getSupabase();
      // Attach the email to the current (guest) user and store the username.
      const { error } = await supabase.auth.updateUser({ email: emailTrim, data: { username: username.trim() } });
      if (error) throw error;
      setStep("otp");
      setMsg(`We sent a 6-digit code to ${emailTrim}. Enter it below to verify your email.`);
    } catch (e) {
      setErr(friendly((e as Error).message));
    } finally { setBusy(false); }
  }

  // Step 2 (register): verify OTP, then set the password on the now-verified account.
  async function verifyAndFinish() {
    setErr(null);
    if (otp.trim().length < 6) return setErr("Enter the 6-digit code from your email.");
    setBusy(true);
    try {
      const supabase = getSupabase();
      const { error: vErr } = await supabase.auth.verifyOtp({ email: emailTrim, token: otp.trim(), type: "email_change" });
      if (vErr) throw vErr;
      // Email is verified now — a password can be set.
      const { error: pErr } = await supabase.auth.updateUser({ password });
      if (pErr) throw pErr;
      setMsg("Account created — taking you home…");
      finishHome();
    } catch (e) {
      setErr(friendly((e as Error).message));
    } finally { setBusy(false); }
  }

  async function resend() {
    setErr(null); setBusy(true);
    try {
      await getSupabase().auth.updateUser({ email: emailTrim });
      setMsg("New code sent.");
    } catch (e) { setErr(friendly((e as Error).message)); } finally { setBusy(false); }
  }

  async function signIn() {
    setErr(null); setMsg(null);
    if (!validEmail || !password) return setErr("Enter your email and password.");
    setBusy(true);
    try {
      const { error } = await getSupabase().auth.signInWithPassword({ email: emailTrim, password });
      if (error) throw error;
      setMsg("Signed in — taking you home…");
      finishHome();
    } catch (e) {
      setErr(friendly((e as Error).message));
    } finally { setBusy(false); }
  }

  return (
    <div style={{ maxWidth: 420, margin: "6vh auto", display: "grid", gap: 14, padding: 24 }} className="fade-up">
      <Logo size={34} />

      {step === "otp" ? (
        <>
          <h1>Verify your email</h1>
          <p className="muted" style={{ marginTop: -6 }}>{msg}</p>
          <input className="input" inputMode="numeric" placeholder="6-digit code" value={otp}
            onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 6))} style={{ letterSpacing: "0.3em", textAlign: "center", fontSize: 20 }} />
          {err && <ErrorBox msg={err} />}
          <button className="btn" onClick={verifyAndFinish} disabled={busy} style={{ justifyContent: "center", padding: 13 }}>
            {busy ? "Verifying…" : "Verify & create account"}
          </button>
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }}>
            <button className="chip" onClick={resend} disabled={busy}>Resend code</button>
            <button className="chip" onClick={() => { setStep("form"); setErr(null); }}>← Back</button>
          </div>
        </>
      ) : (
        <>
          <h1>{mode === "register" ? "Create your account" : "Welcome back"}</h1>
          <p className="muted" style={{ marginTop: -6 }}>
            {mode === "register"
              ? "Keep the data you’ve been exploring as a guest — your account keeps the same data."
              : "Sign in to sync your data to this device. You’ll stay signed in."}
          </p>

          {mode === "register" && (
            <input className="input" placeholder="Display name" value={username} onChange={(e) => setUsername(e.target.value)} />
          )}
          <input className="input" type="email" placeholder="Email" value={email} onChange={(e) => setEmail(e.target.value)} />
          <PasswordInput value={password} onChange={setPassword} placeholder="Password" />
          {mode === "register" && (
            <PasswordInput value={confirm} onChange={setConfirm} placeholder="Confirm password" />
          )}

          {err && <ErrorBox msg={err} />}
          {msg && !err && <div className="card" style={{ padding: 12, fontSize: 14 }}>{msg}</div>}

          <button className="btn" onClick={mode === "register" ? startRegister : signIn} disabled={busy} style={{ justifyContent: "center", padding: 13 }}>
            {busy ? "…" : mode === "register" ? "Continue" : "Sign in"}
          </button>

          <button className="chip" style={{ justifySelf: "center" }} onClick={() => { setMode(mode === "register" ? "signin" : "register"); setErr(null); setMsg(null); }}>
            {mode === "register" ? "Already have an account? Sign in" : "New here? Create an account"}
          </button>
        </>
      )}
    </div>
  );
}

function ErrorBox({ msg }: { msg: string }) {
  return <div className="card" style={{ padding: 12, fontSize: 14, borderColor: "var(--negative)", color: "var(--negative)" }}>{msg}</div>;
}

/** Map common Supabase auth errors to friendlier copy. */
function friendly(m: string): string {
  const s = m.toLowerCase();
  if (s.includes("already been registered") || s.includes("already registered") || s.includes("already exists"))
    return "That email already has an account. Switch to Sign in instead.";
  if (s.includes("invalid login credentials")) return "Email or password is incorrect.";
  if (s.includes("token has expired") || s.includes("invalid")) return "That code is invalid or expired. Try resending.";
  if (s.includes("email not confirmed")) return "Please verify your email first (check for the code).";
  return m;
}
