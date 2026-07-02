"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import { Logo } from "../../src/ui/Logo";

const SLIDES = [
  { title: "Every account, one calm view", body: "Savings, cash, cards, stocks and funds — see your true net worth in your own currency, with or without money you’ve set aside." },
  { title: "Understand where it goes", body: "Log income, expenses and transfers with itemised breakdowns, budgets that alert you early, and beautiful insights." },
  { title: "Build toward what matters", body: "Fund an emergency buffer first, then block savings toward goals and see exactly when you’ll get there." },
];

export default function OnboardingPage() {
  const router = useRouter();
  const [i, setI] = useState(0);
  const last = i === SLIDES.length - 1;

  const done = (dest: string) => {
    localStorage.setItem("onboardingSeen", "1");
    router.replace(dest);
  };

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

        <div style={{ display: "flex", gap: 10, justifyContent: "center" }}>
          {!last ? (
            <>
              <button className="btn" onClick={() => setI(i + 1)}>Next</button>
              <button className="btn ghost" onClick={() => done("/")}>Skip</button>
            </>
          ) : (
            <>
              <button className="btn" onClick={() => done("/")}>Explore as guest</button>
              <button className="btn ghost" onClick={() => done("/login")}>Create account</button>
            </>
          )}
        </div>
        <p className="muted" style={{ fontSize: 12 }}>Guest data is kept for 3 days. Create an account any time to keep it forever.</p>
      </div>
    </div>
  );
}
