"use client";

import { useEffect, useMemo, useRef, useState } from "react";

const CONFETTI_COLORS = ["#e8a33d", "#9cae8e", "#c98a72", "#6d5acf", "#d23a5e", "#3f7a6a", "#f0c419"];

// Cake dimensions (px, before responsive scaling). The top face has the tile's
// proportions; TH is the cake's thickness (its "height" in the front view).
const W = 300; // tile width  (X)
const D = 190; // tile depth  (Z) — becomes the top face's vertical extent in top-view
const TH = 88; // cake thickness (Y)
const HW = W / 2, HD = D / 2, HH = TH / 2;

/**
 * "Goal achieved" moment. The goal tile morphs into a cake: it starts as a flat
 * top-down view (the tile is the cake's top), then rises and rotates to a front
 * view revealing the frosted body, with candles standing up and a confetti
 * burst during the turn. Tap anywhere / auto-dismiss. Respects reduced-motion.
 */
export function GoalCelebration({ name, onClose }: { name: string; onClose: () => void }) {
  const [reduced, setReduced] = useState(false);
  const [scale, setScale] = useState(1);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  // After the rise/rotate settles, the cake becomes a draggable 3D model.
  const [interactive, setInteractive] = useState(false);
  const [rot, setRot] = useState({ x: -22, y: 0 }); // matches the settled pose
  const dragging = useRef(false);
  const last = useRef({ x: 0, y: 0 });
  const closeTimer = useRef<number | undefined>(undefined);

  useEffect(() => {
    const mq = typeof window !== "undefined" ? window.matchMedia("(prefers-reduced-motion: reduce)") : null;
    setReduced(!!mq?.matches);
    const fit = () => setScale(Math.min(1, (window.innerWidth * 0.86) / (W + 40)));
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, []);

  // Auto-dismiss — but cancelled once the user starts orbiting the cake.
  useEffect(() => {
    closeTimer.current = window.setTimeout(onClose, reduced ? 4200 : 9000);
    return () => { if (closeTimer.current) clearTimeout(closeTimer.current); };
  }, [onClose, reduced]);

  // Hand control to the user after the entrance animation.
  useEffect(() => {
    if (reduced) return;
    const t = setTimeout(() => setInteractive(true), 2600);
    return () => clearTimeout(t);
  }, [reduced]);

  const orbit = interactive ? {
    onPointerDown: (e: React.PointerEvent) => {
      e.stopPropagation();
      dragging.current = true;
      last.current = { x: e.clientX, y: e.clientY };
      (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
      if (closeTimer.current) { clearTimeout(closeTimer.current); closeTimer.current = undefined; } // stop auto-close
    },
    onPointerMove: (e: React.PointerEvent) => {
      if (!dragging.current) return;
      const dx = e.clientX - last.current.x, dy = e.clientY - last.current.y;
      last.current = { x: e.clientX, y: e.clientY };
      setRot((r) => ({ x: Math.max(-85, Math.min(85, r.x - dy * 0.4)), y: r.y + dx * 0.4 }));
    },
    onPointerUp: () => { dragging.current = false; },
    onClick: (e: React.MouseEvent) => e.stopPropagation(),
  } : {};

  // Confetti burst — timed to fire as the cake begins to rise & rotate.
  useEffect(() => {
    if (reduced) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const resize = () => { canvas.width = window.innerWidth * dpr; canvas.height = window.innerHeight * dpr; };
    resize();
    window.addEventListener("resize", resize);

    type P = { x: number; y: number; vx: number; vy: number; rot: number; vr: number; size: number; color: string; shape: number };
    const parts: P[] = [];
    const burst = (n: number) => {
      const cx = canvas.width / 2, cy = canvas.height * 0.5;
      for (let i = 0; i < n; i++) {
        const a = Math.random() * Math.PI * 2;
        const sp = (2 + Math.random() * 9) * dpr;
        parts.push({
          x: cx + (Math.random() - 0.5) * 60 * dpr, y: cy + (Math.random() - 0.5) * 40 * dpr,
          vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 4 * dpr,
          rot: Math.random() * Math.PI, vr: (Math.random() - 0.5) * 0.3,
          size: (5 + Math.random() * 7) * dpr,
          color: CONFETTI_COLORS[(Math.random() * CONFETTI_COLORS.length) | 0] ?? "#e8a33d",
          shape: (Math.random() * 2) | 0,
        });
      }
    };
    const t1 = setTimeout(() => burst(170), 520);
    const t2 = setTimeout(() => burst(110), 950);

    let raf = 0;
    const start = performance.now();
    const tick = () => {
      const elapsed = performance.now() - start;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      for (const p of parts) {
        p.x += p.vx; p.y += p.vy; p.vy += 0.12 * dpr; p.vx *= 0.99; p.rot += p.vr;
        ctx.save();
        ctx.translate(p.x, p.y); ctx.rotate(p.rot);
        ctx.fillStyle = p.color; ctx.globalAlpha = Math.max(0, 1 - elapsed / 7000);
        if (p.shape === 0) ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.5);
        else { ctx.beginPath(); ctx.arc(0, 0, p.size / 2, 0, Math.PI * 2); ctx.fill(); }
        ctx.restore();
      }
      if (elapsed < 7000) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => { cancelAnimationFrame(raf); clearTimeout(t1); clearTimeout(t2); window.removeEventListener("resize", resize); };
  }, [reduced]);

  // Candle positions around the top-face perimeter (in top-face local px).
  const candles = useMemo(() => {
    const pad = 34;
    return [
      { x: pad, y: pad }, { x: W - pad, y: pad },
      { x: W / 2, y: 20 },
      { x: pad, y: D - pad }, { x: W - pad, y: D - pad },
      { x: W / 2, y: D - 18 },
    ];
  }, []);

  if (reduced) {
    return (
      <div onClick={onClose} role="dialog" aria-label={`Goal achieved: ${name}`}
        style={{ position: "fixed", inset: 0, zIndex: 1000, display: "grid", placeItems: "center", background: "rgba(20,18,16,0.6)", backdropFilter: "blur(4px)", cursor: "pointer" }}>
        <div className="card" style={{ padding: 28, textAlign: "center", display: "grid", gap: 8, maxWidth: 360 }}>
          <div style={{ fontSize: 72 }}>🎂</div>
          <div style={{ fontSize: 12, fontWeight: 700, letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--accent)" }}>Goal achieved</div>
          <h2 style={{ margin: 0 }}>{name} 🎉</h2>
          <p className="muted" style={{ margin: 0 }}>You fully funded it. Nicely done.</p>
        </div>
      </div>
    );
  }

  const face: React.CSSProperties = { position: "absolute", left: "50%", top: "50%", backfaceVisibility: "hidden" };
  const frostingBand = "linear-gradient(#fff4f7 0 26%, #f3c9d6 26% 34%, #cf9079 34% 100%)";

  return (
    <div onClick={onClose} role="dialog" aria-label={`Goal achieved: ${name}`}
      style={{ position: "fixed", inset: 0, zIndex: 1000, display: "grid", placeItems: "center", background: "rgba(20,18,16,0.6)", backdropFilter: "blur(5px)", cursor: "pointer", animation: "pc-fade-in 240ms ease" }}>
      <canvas ref={canvasRef} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", pointerEvents: "none" }} />

      <div style={{ display: "grid", justifyItems: "center", gap: 18 }}>
        {/* 3D stage — draggable to orbit once it settles */}
        <div {...orbit} style={{ perspective: 1200, transform: `scale(${scale})`, cursor: interactive ? (dragging.current ? "grabbing" : "grab") : "default", touchAction: "none" }}>
          <div style={{
            position: "relative", width: W, height: D, transformStyle: "preserve-3d",
            ...(interactive
              ? { transform: `rotateX(${rot.x}deg) rotateY(${rot.y}deg)` }
              : { animation: "pc-cake-rise 2.5s cubic-bezier(0.22,0.9,0.24,1) forwards" }),
          }}>
            {/* bottom / plate */}
            <div style={{ ...face, width: W, height: D, transform: `translate(-50%,-50%) rotateX(-90deg) translateZ(${HH}px)`, background: "#e9e4dc", borderRadius: 18 }} />
            {/* sides */}
            <div style={{ ...face, width: W, height: TH, transform: `translate(-50%,-50%) translateZ(${HD}px)`, background: frostingBand, borderRadius: "0 0 12px 12px" }} />
            <div style={{ ...face, width: W, height: TH, transform: `translate(-50%,-50%) rotateY(180deg) translateZ(${HD}px)`, background: frostingBand, borderRadius: "0 0 12px 12px" }} />
            <div style={{ ...face, width: D, height: TH, transform: `translate(-50%,-50%) rotateY(-90deg) translateZ(${HW}px)`, background: frostingBand, borderRadius: "0 0 12px 12px" }} />
            <div style={{ ...face, width: D, height: TH, transform: `translate(-50%,-50%) rotateY(90deg) translateZ(${HW}px)`, background: frostingBand, borderRadius: "0 0 12px 12px" }} />

            {/* TOP FACE = the goal tile */}
            <div style={{ ...face, width: W, height: D, transform: `translate(-50%,-50%) rotateX(90deg) translateZ(${HH}px)`, transformStyle: "preserve-3d" }}>
              <div style={{ position: "absolute", inset: 0, background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 18, boxShadow: "var(--shadow)", padding: 22, display: "grid", alignContent: "space-between", gap: 12 }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8 }}>
                  <strong style={{ fontSize: 18, letterSpacing: "-0.01em" }}>{name}</strong>
                  <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent)", letterSpacing: "0.08em" }}>GOAL</span>
                </div>
                <div style={{ display: "grid", gap: 8 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13, color: "var(--text-2)" }}>
                    <span>Funded</span><strong style={{ color: "var(--text)" }}>100%</strong>
                  </div>
                  <div style={{ height: 10, borderRadius: 999, background: "var(--surface-2)", overflow: "hidden" }}>
                    <div style={{ height: "100%", width: "100%", borderRadius: 999, background: "linear-gradient(90deg, var(--sage), var(--accent))" }} />
                  </div>
                </div>
              </div>

              {/* candles stand up out of the top face (+Z of this face) */}
              {candles.map((c, i) => (
                <div key={i} style={{ position: "absolute", left: c.x, top: c.y, width: 8, height: 46, transformOrigin: "50% 100%", transform: "translate(-50%,-100%) rotateX(-90deg)", transformStyle: "preserve-3d" }}>
                  <div style={{ position: "absolute", inset: 0, borderRadius: 4, background: i % 2 ? "linear-gradient(#fff, #f4c9db)" : "linear-gradient(#fff, #cfe0f5)" }} />
                  {/* flame at the tip, billboarded to face up */}
                  <div style={{ position: "absolute", left: "50%", top: -12, width: 12, height: 18, transform: "translate(-50%,0) rotateX(90deg)", transformOrigin: "50% 100%", borderRadius: "50% 50% 50% 50% / 60% 60% 40% 40%", background: "radial-gradient(circle at 50% 65%, #fff2a8, #ff9d2e 60%, #ff6a2e)", boxShadow: "0 0 16px 4px rgba(255,170,60,0.7)", animation: `pc-flicker 0.9s ${i * 0.13}s ease-in-out infinite` }} />
                </div>
              ))}
            </div>
          </div>
        </div>

        <div style={{ textAlign: "center", display: "grid", gap: 4, justifyItems: "center", opacity: 0, animation: "pc-caption 500ms 1.5s ease forwards" }}>
          <div style={{ fontSize: 13, fontWeight: 700, letterSpacing: "0.14em", textTransform: "uppercase", color: "#f0c419" }}>Goal achieved</div>
          <h2 style={{ margin: 0, color: "#fff", fontSize: "clamp(22px, 5vw, 34px)", letterSpacing: "-0.02em" }}>{name} 🎉</h2>
          <span style={{ marginTop: 4, color: "rgba(255,255,255,0.5)", fontSize: 12 }}>{interactive ? "Drag the cake to spin it · tap outside to close" : "Tap anywhere to continue"}</span>
        </div>
      </div>

      <style>{`
        @keyframes pc-fade-in { from { opacity: 0 } to { opacity: 1 } }
        @keyframes pc-caption { from { opacity: 0; transform: translateY(8px) } to { opacity: 1; transform: none } }
        @keyframes pc-flicker { 0%,100% { transform: translate(-50%,0) rotateX(90deg) scale(1); opacity: 1 } 50% { transform: translate(-50%,0) rotateX(90deg) scale(0.86,1.12); opacity: 0.85 } }
        @keyframes pc-cake-rise {
          0%   { transform: translate3d(0, 44px, 0) rotateX(-90deg) rotateY(0deg); }
          22%  { transform: translate3d(0, -18px, 0) rotateX(-90deg) rotateY(0deg); }
          100% { transform: translate3d(0, 0, 0) rotateX(-22deg) rotateY(360deg); }
        }
      `}</style>
    </div>
  );
}
