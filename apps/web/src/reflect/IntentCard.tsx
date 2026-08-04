"use client";

import { motion, useAnimation, useMotionValue, useTransform } from "framer-motion";
import { useEffect, useState } from "react";
import { money } from "@sanvya/money";
import { useMoneyFmt } from "../ui/Money";
import { merchantTitle, avatarColor } from "../ui/TransactionTile";
import { MaterialIcon } from "../ui/MaterialIcon";

export interface IntentCardProps {
  id: string;
  raw: string;
  amountMinor: number;
  currency: string;
  occurredAt: string;
  categoryName?: string | null;
  accountName?: string;
  accountColor?: string;
  onJudged: (intent: 'need' | 'greed') => void;
  onSkip: () => void;
  isTop?: boolean;
}

export function IntentCard({
  id, raw, amountMinor, currency, occurredAt, categoryName,
  accountName, accountColor, onJudged, onSkip, isTop = true
}: IntentCardProps) {
  const fmt = useMoneyFmt();
  const title = merchantTitle(raw);
  const color = accountColor || avatarColor(title);
  
  const x = useMotionValue(0);
  const controls = useAnimation();
  
  const rotate = useTransform(x, [-200, 200], [-10, 10]);
  const opacity = useTransform(x, [-200, -100, 0, 100, 200], [0, 1, 1, 1, 0]);
  
  const bgNeed = useTransform(x, [-100, 0], ["rgba(76, 175, 80, 0.2)", "rgba(255, 255, 255, 0)"]);
  const bgGreed = useTransform(x, [0, 100], ["rgba(255, 255, 255, 0)", "rgba(244, 67, 54, 0.2)"]);

  const [exitX, setExitX] = useState<number>(0);

  const handleJudgement = async (intent: 'need' | 'greed') => {
    const targetX = intent === 'need' ? -300 : 300;
    setExitX(targetX);
    await controls.start({ x: targetX, opacity: 0, transition: { duration: 0.2 } });
    onJudged(intent);
  };

  const handleDragEnd = async (e: any, info: any) => {
    const offset = info.offset.x;
    const velocity = info.velocity.x;

    if (offset < -100 || velocity < -500) {
      await handleJudgement('need');
    } else if (offset > 100 || velocity > 500) {
      await handleJudgement('greed');
    } else {
      controls.start({ x: 0, transition: { type: "spring", stiffness: 300, damping: 20 } });
    }
  };

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (!isTop) return;
      if (e.key === "ArrowLeft") handleJudgement('need');
      if (e.key === "ArrowRight") handleJudgement('greed');
      if (e.key === "Escape") onSkip();
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isTop]);

  return (
    <motion.div
      drag={isTop ? "x" : false}
      dragConstraints={{ left: 0, right: 0 }}
      onDragEnd={handleDragEnd}
      animate={controls}
      style={{
        x, rotate, opacity,
        position: 'absolute',
        top: 0, left: 0, right: 0, bottom: 0,
        borderRadius: 24,
        background: "var(--surface)",
        boxShadow: "0 8px 32px rgba(0,0,0,0.1)",
        display: "flex", flexDirection: "column",
        overflow: "hidden",
        border: `2px solid ${color}`,
        zIndex: isTop ? 10 : 1,
        pointerEvents: isTop ? "auto" : "none"
      }}
    >
      <motion.div style={{ position: "absolute", inset: 0, background: bgNeed, pointerEvents: "none" }} />
      <motion.div style={{ position: "absolute", inset: 0, background: bgGreed, pointerEvents: "none" }} />

      <div style={{ padding: "40px 24px", flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
        <div style={{ fontSize: 42, fontWeight: 800, marginBottom: 8, color: "var(--text)" }}>
          {fmt(money(amountMinor, currency))}
        </div>
        <div style={{ fontSize: 24, fontWeight: 600, color: "var(--text-2)", textAlign: "center", marginBottom: 24 }}>
          {title}
        </div>
        
        {accountName && (
          <div style={{ 
            display: "inline-flex", alignItems: "center", gap: 6,
            background: color, color: "#fff", 
            padding: "6px 12px", borderRadius: 999,
            fontSize: 14, fontWeight: 600, marginBottom: 12
          }}>
            <MaterialIcon name="account_balance" size={16} />
            {accountName}
          </div>
        )}
        
        <div className="muted" style={{ display: "flex", gap: 16, fontSize: 13 }}>
          <span>{new Date(occurredAt).toLocaleDateString()}</span>
          {categoryName && <span>• {categoryName}</span>}
        </div>
      </div>

      <div style={{ padding: 24, display: "flex", gap: 12 }}>
        <button
          onClick={() => handleJudgement('need')}
          className="btn"
          style={{ flex: 1, background: "rgba(76, 175, 80, 0.1)", color: "#4CAF50", padding: "16px", borderRadius: 16, fontWeight: 700, fontSize: 16, border: "none" }}
        >
          Need (←)
        </button>
        <button
          onClick={() => handleJudgement('greed')}
          className="btn"
          style={{ flex: 1, background: "rgba(244, 67, 54, 0.1)", color: "#F44336", padding: "16px", borderRadius: 16, fontWeight: 700, fontSize: 16, border: "none" }}
        >
          Greed (→)
        </button>
      </div>
    </motion.div>
  );
}
