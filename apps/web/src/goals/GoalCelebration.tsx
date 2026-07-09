"use client";

import { useEffect, useRef, useState } from "react";
import dynamic from "next/dynamic";

// Load three.js only when a celebration actually fires — keeps the goals route light.
const Cake3D = dynamic(() => import("./Cake3D"), { ssr: false });

const CONFETTI_COLORS = ["#e8a33d", "#9cae8e", "#c98a72", "#6d5acf", "#d23a5e", "#3f7a6a", "#f0c419"];

/**
 * Full-screen "goal achieved" moment: a spinning 3D cake with lit candles and a
 * confetti burst. Auto-dismisses; tap anywhere to close. Respects
 * prefers-reduced-motion with a calm static card instead of the animation.
 */
export function GoalCelebration({ name, onClose }: { name: string; onClose: () => void }) {
  const [reduced, setReduced] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const mq = typeof window !== "undefined" ? window.matchMedia("(prefers-reduced-motion: reduce)") : null;
    setReduced(!!mq?.matches);
  }, []);

  // Auto-close after a few seconds.
  useEffect(() => {
    const t = setTimeout(onClose, reduced ? 4200 : 6500);
    return () => clearTimeout(t);
  }, [onClose, reduced]);

  // Confetti burst on a 2D canvas (skipped when reduced-motion).
  useEffect(() => {
    if (reduced) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const resize = () => {
      canvas.width = window.innerWidth * dpr;
      canvas.height = window.innerHeight * dpr;
    };
    resize();
    window.addEventListener("resize", resize);

    type P = { x: number; y: number; vx: number; vy: number; rot: number; vr: number; size: number; color: string; shape: number };
    const W = () => canvas.width, H = () => canvas.height;
    const parts: P[] = [];
    const make = (n: number) => {
      for (let i = 0; i < n; i++) {
        parts.push({
          x: W() * (0.15 + Math.random() * 0.7),
          y: -20 * dpr,
          vx: (Math.random() - 0.5) * 6 * dpr,
          vy: (2 + Math.random() * 4) * dpr,
          rot: Math.random() * Math.PI,
          vr: (Math.random() - 0.5) * 0.3,
          size: (5 + Math.random() * 7) * dpr,
          color: CONFETTI_COLORS[(Math.random() * CONFETTI_COLORS.length) | 0] ?? "#e8a33d",
          shape: (Math.random() * 2) | 0,
        });
      }
    };
    make(160);
    setTimeout(() => make(90), 500);

    let raf = 0;
    const start = performance.now();
    const tick = () => {
      const elapsed = performance.now() - start;
      ctx.clearRect(0, 0, W(), H());
      for (const p of parts) {
        p.x += p.vx; p.y += p.vy; p.vy += 0.06 * dpr; p.rot += p.vr;
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.rot);
        ctx.fillStyle = p.color;
        ctx.globalAlpha = Math.max(0, 1 - elapsed / 6500);
        if (p.shape === 0) ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.5);
        else { ctx.beginPath(); ctx.arc(0, 0, p.size / 2, 0, Math.PI * 2); ctx.fill(); }
        ctx.restore();
      }
      if (elapsed < 6500) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => { cancelAnimationFrame(raf); window.removeEventListener("resize", resize); };
  }, [reduced]);

  return (
    <div
      onClick={onClose}
      role="dialog"
      aria-label={`Goal achieved: ${name}`}
      style={{
        position: "fixed", inset: 0, zIndex: 1000, display: "grid", placeItems: "center",
        background: "rgba(20,18,16,0.55)", backdropFilter: "blur(4px)", cursor: "pointer",
        animation: "pc-fade-in 240ms ease",
      }}
    >
      {!reduced && <canvas ref={canvasRef} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", pointerEvents: "none" }} />}

      <div style={{ position: "relative", textAlign: "center", display: "grid", gap: 6, justifyItems: "center", padding: 24 }}>
        <div style={{ width: "min(320px, 74vw)", height: "min(320px, 74vw)" }}>
          {reduced ? (
            <div style={{ fontSize: 120, lineHeight: "min(320px,74vw)" }}>🎂</div>
          ) : (
            <Cake3D />
          )}
        </div>
        <div style={{ fontSize: 13, fontWeight: 700, letterSpacing: "0.14em", textTransform: "uppercase", color: "#f0c419" }}>
          Goal achieved
        </div>
        <h2 style={{ margin: 0, color: "#fff", fontSize: "clamp(24px, 5vw, 36px)", letterSpacing: "-0.02em" }}>{name} 🎉</h2>
        <p style={{ margin: 0, color: "rgba(255,255,255,0.72)", fontSize: 14 }}>You fully funded it. Nicely done.</p>
        <span style={{ marginTop: 6, color: "rgba(255,255,255,0.5)", fontSize: 12 }}>Tap anywhere to continue</span>
      </div>

      <style>{`@keyframes pc-fade-in { from { opacity: 0 } to { opacity: 1 } }`}</style>
    </div>
  );
}
