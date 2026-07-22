"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslation } from "react-i18next";
import { AnimatePresence, motion } from "framer-motion";
import { Logo } from "../../src/ui/Logo";
import { getSupabase } from "../../src/powersync";
import { Modal } from "../../src/ui/Modal";
import { InstallGuide } from "../../src/ui/InstallGuide";
import { DownloadIcon } from "../../src/ui/icons";

/** Inshorts-style walkthrough: a graphic glyph + a plain-language summary. The
 *  first cards say what to DO first; the rest say what you can achieve. */
// Visual identity per slide; the title/body copy is localised via the `onboarding` namespace.
const SLIDES: { glyph: string; grad: [string, string] }[] = [
  { glyph: "❤", grad: ["#b06a4f", "#8f533c"] },
  { glyph: "⌂", grad: ["#3e4a38", "#2f6f6a"] },
  { glyph: "⇅", grad: ["#7a4a6b", "#4f3a54"] },
  { glyph: "◔", grad: ["#c08a3e", "#a8503a"] },
  { glyph: "⇌", grad: ["#b06a4f", "#5f6647"] },
  { glyph: "◎", grad: ["#2f6f6a", "#3e4a38"] },
  { glyph: "✦", grad: ["#7c4a3a", "#b06a4f"] },
];

function Graphic({ glyph, grad }: { glyph: string; grad: [string, string] }) {
  return (
    <div style={{ width: "100%", maxWidth: 300, aspectRatio: "16 / 10", borderRadius: 24, display: "grid", placeItems: "center",
      background: `linear-gradient(150deg, ${grad[0]}, ${grad[1]})`, boxShadow: `0 20px 44px -22px ${grad[0]}bb`, color: "#f6f0e7" }}>
      <span style={{ fontSize: 68, lineHeight: 1, filter: "drop-shadow(0 4px 10px rgba(0,0,0,0.25))" }}>{glyph}</span>
    </div>
  );
}

export default function OnboardingPage() {
  const { t } = useTranslation("onboarding");
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
      setErr((e as Error).message || t("guestErr"));
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
            initial={{ opacity: 0, x: 40 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -40 }}
            transition={{ duration: 0.32, ease: [0.2, 0, 0, 1] }}
            drag="x" dragConstraints={{ left: 0, right: 0 }} dragElastic={0.18}
            onDragEnd={(_, info) => {
              if (info.offset.x < -60 && i < SLIDES.length - 1) setI(i + 1);
              else if (info.offset.x > 60 && i > 0) setI(i - 1);
            }}
            style={{ display: "grid", gap: 18, justifyItems: "center", cursor: "grab", touchAction: "pan-y" }}
          >
            <Graphic glyph={SLIDES[i]!.glyph} grad={SLIDES[i]!.grad} />
            <h1 style={{ fontSize: 27, margin: 0 }}>{t(`slides.${i}.title`)}</h1>
            <p className="muted" style={{ fontSize: 16, lineHeight: 1.6, maxWidth: 440, margin: 0 }}>{t(`slides.${i}.body`)}</p>
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
              <button className="btn" onClick={() => setI(i + 1)}>{t("next")}</button>
              <button className="btn ghost" onClick={() => setI(SLIDES.length - 1)}>{t("skip")}</button>
            </>
          ) : (
            <>
              <button className="btn" onClick={() => done("/login")} disabled={busy}>{t("createAccount")}</button>
              <button className="btn ghost" onClick={() => done("/login?mode=signin")} disabled={busy}>{t("signIn")}</button>
              <button className="btn ghost" onClick={tryGuest} disabled={busy}>{busy ? t("starting") : t("tryGuest")}</button>
            </>
          )}
        </div>
        {err && <div className="card" style={{ padding: 12, fontSize: 13, borderColor: "var(--negative)", color: "var(--negative)" }}>{err}</div>}
        <p className="muted" style={{ fontSize: 12 }}>{t("footer")}</p>

        <button className="chip" style={{ justifySelf: "center", display: "inline-flex", alignItems: "center", gap: 6 }} onClick={() => setShowInstall(true)}>
          <DownloadIcon size={15} /> {t("installApp")}
        </button>
      </div>

      <Modal open={showInstall} onClose={() => setShowInstall(false)}>
        <h2 style={{ margin: "0 0 12px" }}>{t("installTitle")}</h2>
        <InstallGuide />
      </Modal>
    </div>
  );
}
