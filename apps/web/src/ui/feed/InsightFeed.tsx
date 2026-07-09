"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import { useInsightStack } from "../../insights/useInsightStack";
import { InsightCard } from "./InsightCard";
import { ProgressRail } from "./ProgressRail";
import type { InsightCard as Card } from "../../insights/types";

// ---- responsive helpers ----
function useIsDesktop(): boolean {
  const [d, setD] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(min-width: 860px)");
    const on = () => setD(mq.matches);
    on(); mq.addEventListener("change", on);
    return () => mq.removeEventListener("change", on);
  }, []);
  return d;
}

/** Height that fills the viewport from the element's top down. */
function useFillHeight() {
  const ref = useRef<HTMLDivElement>(null);
  const [h, setH] = useState("70vh");
  useLayoutEffect(() => {
    const measure = () => {
      const top = ref.current?.getBoundingClientRect().top ?? 0;
      setH(`calc(100dvh - ${Math.max(0, Math.round(top))}px - 12px)`);
    };
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);
  return { ref, height: h };
}

// ---- mobile: native vertical scroll-snap ----
function SnapFeed({ cards, activeIndex, setActiveIndex }: { cards: Card[]; activeIndex: number; setActiveIndex: (i: number) => void }) {
  const scroller = useRef<HTMLDivElement>(null);
  const items = useRef<(HTMLElement | null)[]>([]);

  useEffect(() => {
    const root = scroller.current;
    if (!root) return;
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting && e.intersectionRatio >= 0.55) {
            const idx = Number((e.target as HTMLElement).dataset.idx);
            if (!Number.isNaN(idx)) setActiveIndex(idx);
          }
        }
      },
      { root, threshold: [0.55, 0.75] },
    );
    items.current.forEach((el) => el && io.observe(el));
    return () => io.disconnect();
  }, [cards.length, setActiveIndex]);

  return (
    <div
      ref={scroller}
      className="hide-scrollbar"
      style={{ height: "100%", overflowY: "auto", scrollSnapType: "y mandatory", overscrollBehavior: "contain", touchAction: "pan-y", borderRadius: 16 }}
    >
      {cards.map((c, i) => (
        <section
          key={c.id}
          data-idx={i}
          ref={(el) => { items.current[i] = el; }}
          style={{ height: "100%", scrollSnapAlign: "start", scrollSnapStop: "always" }}
        >
          <InsightCard card={c} layout="mobile" />
        </section>
      ))}
    </div>
  );
}

// ---- desktop: coverflow deck ----
function Coverflow({ cards, activeIndex, setActiveIndex }: { cards: Card[]; activeIndex: number; setActiveIndex: (i: number) => void }) {
  const box = useRef<HTMLDivElement>(null);
  const cooldown = useRef(0);
  const clamp = useCallback((i: number) => Math.max(0, Math.min(cards.length - 1, i)), [cards.length]);
  const go = useCallback((dir: number) => {
    const now = performance.now();
    if (now < cooldown.current) return;
    cooldown.current = now + 420;
    setActiveIndex(clamp(activeIndex + dir));
  }, [activeIndex, clamp, setActiveIndex]);

  // Wheel paging (non-passive so we can preventDefault the page scroll).
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      const d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
      if (Math.abs(d) < 12) return;
      e.preventDefault();
      go(d > 0 ? 1 : -1);
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => el.removeEventListener("wheel", onWheel);
  }, [go]);

  // Keyboard paging.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (["ArrowRight", "ArrowDown"].includes(e.key)) { e.preventDefault(); go(1); }
      else if (["ArrowLeft", "ArrowUp"].includes(e.key)) { e.preventDefault(); go(-1); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [go]);

  // Pointer swipe.
  const startX = useRef<number | null>(null);
  const onPointerDown = (e: React.PointerEvent) => { startX.current = e.clientX; };
  const onPointerUp = (e: React.PointerEvent) => {
    if (startX.current === null) return;
    const dx = e.clientX - startX.current;
    startX.current = null;
    if (Math.abs(dx) > 60) go(dx < 0 ? 1 : -1);
  };

  return (
    <div
      ref={box}
      tabIndex={0}
      onPointerDown={onPointerDown}
      onPointerUp={onPointerUp}
      style={{ position: "relative", height: "100%", outline: "none", touchAction: "pan-y" }}
    >
      {cards.map((c, i) => {
        const offset = i - activeIndex;
        if (Math.abs(offset) > 2) return null;
        const isActive = offset === 0;
        return (
          <motion.div
            key={c.id}
            initial={false}
            animate={{
              x: `calc(-50% + ${offset * 56}%)`,
              scale: isActive ? 1 : 0.82,
              opacity: Math.abs(offset) > 1 ? 0 : isActive ? 1 : 0.55,
              filter: isActive ? "none" : "saturate(0.8)",
            }}
            transition={{ type: "spring", stiffness: 260, damping: 30 }}
            onClick={() => { if (!isActive) setActiveIndex(i); }}
            style={{
              position: "absolute", left: "50%", top: 0, height: "100%",
              width: "min(760px, 62vw)", zIndex: 10 - Math.abs(offset),
              cursor: isActive ? "default" : "pointer",
              pointerEvents: Math.abs(offset) > 1 ? "none" : "auto",
            }}
          >
            <InsightCard card={c} layout="desktop" />
          </motion.div>
        );
      })}

      {/* prev / next */}
      {activeIndex > 0 && <DeckButton side="left" onClick={() => go(-1)} />}
      {activeIndex < cards.length - 1 && <DeckButton side="right" onClick={() => go(1)} />}
    </div>
  );
}

function DeckButton({ side, onClick }: { side: "left" | "right"; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      aria-label={side === "left" ? "Previous insight" : "Next insight"}
      style={{
        position: "absolute", top: "50%", transform: "translateY(-50%)", [side]: 8, zIndex: 30,
        width: 42, height: 42, borderRadius: 999, border: "1px solid var(--border)",
        background: "var(--surface)", boxShadow: "var(--shadow)", cursor: "pointer", fontSize: 18, color: "var(--text)",
      } as React.CSSProperties}
    >
      {side === "left" ? "‹" : "›"}
    </button>
  );
}

export function InsightFeed() {
  const { cards, total, activeIndex, setActiveIndex, remaining } = useInsightStack();
  const isDesktop = useIsDesktop();
  const { ref, height } = useFillHeight();

  if (total === 0) {
    return (
      <div className="card fade-up" style={{ padding: 32, textAlign: "center", display: "grid", gap: 8, maxWidth: 460 }}>
        <div style={{ fontSize: 28 }}>✦</div>
        <h2>Your stack is empty for now</h2>
        <p className="muted">Add a few transactions and PocketCare will start surfacing weekly recaps, budget alerts and savings wins here.</p>
      </div>
    );
  }

  return (
    // Negative bottom margin cancels the shell's bottom padding (FAB space) so
    // the page itself doesn't add a second scrollbar next to the feed's swipe.
    <div ref={ref} className="fade-up" style={{ position: "relative", marginBottom: -88 }}>
      <div style={{ height }}>
        <div style={{ position: "relative", height: "100%" }}>
          <ProgressRail total={total} activeIndex={activeIndex} layout={isDesktop ? "desktop" : "mobile"} onJump={setActiveIndex} />
          {isDesktop
            ? <Coverflow cards={cards} activeIndex={activeIndex} setActiveIndex={setActiveIndex} />
            : <SnapFeed cards={cards} activeIndex={activeIndex} setActiveIndex={setActiveIndex} />}
          <div style={{ position: "absolute", bottom: 10, left: "50%", transform: "translateX(-50%)", zIndex: 20,
            fontSize: 12, color: "var(--text-2)", background: "var(--surface)", border: "1px solid var(--border)",
            borderRadius: 999, padding: "4px 12px", boxShadow: "var(--shadow)" }}>
            {activeIndex + 1} of {total}{remaining > 0 ? ` · ${remaining} left` : " · all caught up"}
          </div>
        </div>
      </div>
    </div>
  );
}
