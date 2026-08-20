"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { MaterialIcon, type MaterialIconName } from "../MaterialIcon";
import { ArrowUpIcon } from "../icons";
import { AssistantOrb } from "./AssistantOrb";
import { AssistantChat } from "../../assistant/AssistantChat";

/**
 * "Ask Sanvya" on the desktop dashboard: a card that morphs into a docked
 * side panel.
 *
 * The morph is a shared `layoutId` between the two elements rather than a
 * width/height transition on one. Only one is ever mounted, and framer-motion
 * interpolates the FLIP between them — which is what lets a card sitting in
 * normal document flow become a `position: fixed` panel without the jump you
 * get from animating `position` directly.
 *
 * Asking never leaves the dashboard. The expanded panel mounts the real
 * AssistantChat (threads, tools, quota, confirmations), so there is still
 * exactly ONE chat implementation -- it is embedded here rather than
 * navigated to. The collapsed card is only a launcher: whatever you type or
 * tap there becomes the panel's opening question.
 */
interface Quick {
  key: string;
  label: string;
  icon: MaterialIconName;
  tint: string;
  prompt: string;
}

const QUICK: Quick[] = [
  { key: "where", label: "Where did it go?", icon: "insights", tint: "var(--accent)", prompt: "Where did my money go this month?" },
  { key: "budget", label: "Am I on budget?", icon: "donut_small", tint: "var(--positive)", prompt: "Am I on track with my budgets this month?" },
  { key: "goal", label: "Plan a goal", icon: "savings", tint: "var(--teal)", prompt: "Help me plan a realistic savings goal." },
  { key: "find", label: "Find a payment", icon: "search", tint: "var(--warning)", prompt: "Help me find a payment I made recently." },
];

function ExpandIcon({ open }: { open: boolean }) {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      {open
        ? <path d="M9 4v5H4M15 20v-5h5" />
        : <path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7" />}
    </svg>
  );
}

function Body({ onAsk }: { onAsk: (text: string) => void }) {
  const [q, setQ] = useState("");
  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const text = q.trim();
    if (text) onAsk(text);
  };

  return (
    <>
      <div className="ai-stage">
        <AssistantOrb size={116} />
      </div>

      <div className="ai-quick">
        {QUICK.map((qa) => (
          <button key={qa.key} type="button" className="ai-chip press" onClick={() => onAsk(qa.prompt)}>
            <span className="ai-chip-ico" style={{ background: `color-mix(in srgb, ${qa.tint} 16%, transparent)`, color: qa.tint }}>
              <MaterialIcon name={qa.icon} size={14} />
            </span>
            <span className="ai-chip-label">{qa.label}</span>
          </button>
        ))}
      </div>

      <form className="ai-composer" onSubmit={submit}>
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Ask me anything…"
          aria-label="Ask Sanvya"
        />
        <button type="submit" className="ai-send press" disabled={!q.trim()} aria-label="Send">
          <ArrowUpIcon size={16} />
        </button>
      </form>
    </>
  );
}

export function AssistantWidget() {
  const [open, setOpen] = useState(false);
  // The question that opened the panel, handed to the chat as its first turn.
  const [opening, setOpening] = useState<string | undefined>(undefined);

  // Escape closes the panel — a docked overlay that can only be dismissed by
  // hitting a small target is a trap for keyboard users.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  const ask = (text: string) => { setOpening(text); setOpen(true); };

  // Remount the chat per question so a new one from the collapsed card starts
  // a fresh turn rather than being swallowed as a duplicate initial prompt.
  const chatKey = opening ?? "blank";

  const spring = { type: "spring" as const, stiffness: 240, damping: 30 };

  return (
    <>
      {!open && (
        <motion.section layoutId="ai-shell" transition={spring} className="ai-card card">
          <div className="ai-head">
            <h2>Ask Sanvya</h2>
            <button type="button" className="ai-expand press" onClick={() => { setOpening(undefined); setOpen(true); }} aria-label="Expand assistant">
              <ExpandIcon open={false} />
            </button>
          </div>
          <Body onAsk={ask} />
        </motion.section>
      )}

      <AnimatePresence>
        {open && (
          <>
            <motion.div
              key="ai-scrim"
              className="ai-scrim"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setOpen(false)}
            />
            <motion.aside
              key="ai-panel"
              layoutId="ai-shell"
              transition={spring}
              className="ai-panel"
              role="dialog"
              aria-label="Ask Sanvya"
            >
              <div className="ai-head">
                <h2>Ask Sanvya</h2>
                <button type="button" className="ai-expand press" onClick={() => setOpen(false)} aria-label="Collapse assistant">
                  <ExpandIcon open />
                </button>
              </div>
              <div className="ai-panel-chat">
                <AssistantChat key={chatKey} embedded initialPrompt={opening} />
              </div>
            </motion.aside>
          </>
        )}
      </AnimatePresence>
    </>
  );
}
