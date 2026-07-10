"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import { Logo } from "../../src/ui/Logo";
import { getSupabase } from "../../src/powersync";
import { Modal } from "../../src/ui/Modal";
import { InstallGuide } from "../../src/ui/InstallGuide";
import { DownloadIcon } from "../../src/ui/icons";

const SLIDES = [
  { title: "Every account, one calm view", body: "Savings, cash, cards, stocks and funds — see your true net worth in your own currency, with or without money you’ve set aside." },
  { title: "Understand where it goes", body: "Log income, expenses and transfers with itemised breakdowns, budgets that alert you early, and beautiful insights." },
  { title: "Build toward what matters", body: "Fund an emergency buffer first, then block savings toward goals and see exactly when you’ll get there." },
];

export default function OnboardingPage() {
  const router = useRouter();
  const [i, setI] = useState(0);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [showInstall, setShowInstall] = useState(false);
  const last = i === SLIDES.length - 1;

  const done = (dest: string) => {
    localStorage.setItem("onboardingSeen", "1");
    router.replace(dest);
  };

  // Explicit guest route: create an anonymous session, then enter the app.
  async function tryGuest() {
    setErr(null); setBusy(true);
    try {
      const { error } = await getSupabase().auth.signInAnonymously();
      if (error) throw error;
      done("/");
    } catch (e) {
      setErr((e as Error).message || "Couldn’t start a guest session.");
      setBusy(false);
    }
  }

  return (
    <div style={{ minHeight: "100vh", display: "grid", placeItems: "center", padding: 24, background: "radial-gradient(120% 90% at 50% 0%, var(--accent-ghost), var(--bg) 60%)" }}>
      <div style={{ maxWidth: 520, width: "100%", textAlign: "center", display: "grid", gap: 22 }}>
        <div style={{ display: "flex", justifyContent: "center", marginBottom: 4 }}><Logo size={34} /></div>
        <AnimatePresence mode="wait">
          <motion.div
            key={i}
            initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -16 }}
            transition={{ duration: 0.35, ease: [0.2, 0, 0, 1] }}
            style={{ display: "grid", gap: 16, justifyItems: "center" }}
          >
            <h1 style={{ fontSize: 30 }}>{SLIDES[i].title}</h1>
            <p className="muted" style={{ fontSize: 17, lineHeight: 1.6, maxWidth: 440 }}>{SLIDES[i].body}</p>
          </motion.div>
        </AnimatePresence>

        <div style={{ display: "flex", justifyContent: "center", gap: 8 }}>
          {SLIDES.map((_, k) => (
            <motion.span key={k} animate={{ width: k === i ? 22 : 8, background: k === i ? "var(--accent)" : "var(--border)" }}
              style={{ height: 8, borderRadius: 999, display: "inline-block" }} />
          ))}
        </div>

        <div style={{ display: "flex", gap: 10, justifyContent: "center", flexWrap: "wrap" }}>
          {!last ? (
            <>
              <button className="btn" onClick={() => setI(i + 1)}>Next</button>
              <button className="btn ghost" onClick={() => setI(SLIDES.length - 1)}>Skip</button>
            </>
          ) : (
            <>
              <button className="btn" onClick={() => done("/login")} disabled={busy}>Create account</button>
              <button className="btn ghost" onClick={() => done("/login?mode=signin")} disabled={busy}>Sign in</button>
              <button className="btn ghost" onClick={tryGuest} disabled={busy}>{busy ? "Starting…" : "Try as guest"}</button>
            </>
          )}
        </div>
        {err && <div className="card" style={{ padding: 12, fontSize: 13, borderColor: "var(--negative)", color: "var(--negative)" }}>{err}</div>}
        <p className="muted" style={{ fontSize: 12 }}>Create an account to sync across devices. Guest data stays on this device and is kept for 3 days.</p>

        <button className="chip" style={{ justifySelf: "center", display: "inline-flex", alignItems: "center", gap: 6 }} onClick={() => setShowInstall(true)}>
          <DownloadIcon size={15} /> Install app on your device
        </button>
      </div>

      <Modal open={showInstall} onClose={() => setShowInstall(false)}>
        <h2 style={{ margin: "0 0 12px" }}>Install PocketCare</h2>
        <InstallGuide />
      </Modal>
    </div>
  );
}
