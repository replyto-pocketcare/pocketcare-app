"use client";

/**
 * The dashboard's floating action button, expanded into a two-action speed dial.
 *
 * Closed it is the same pill it always was, so the primary action ("Add
 * transaction") is still one tap away — the receipt scanner is added WITHOUT
 * demoting the thing people do twenty times a day.
 *
 * Accessibility notes (a FAB is easy to ship as a mouse-only control):
 *  - `role="menu"` + `menuitem`, arrow-key navigation, Home/End.
 *  - Focus moves into the menu on open and returns to the trigger on close.
 *  - Escape and an outside click both close it.
 *  - Respects `prefers-reduced-motion`: no rotation, no stagger, just show/hide.
 */
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";

import { CloseIcon, PlusIcon, ReceiptIcon } from "./icons";

export interface SpeedDialAction {
  readonly key: string;
  readonly label: string;
  readonly href: string;
  readonly icon: React.ReactNode;
}

export interface AddSpeedDialProps {
  /** Label for the closed pill. */
  readonly label: string;
  readonly closeLabel: string;
  readonly actions: readonly SpeedDialAction[];
}

export function AddSpeedDial({ label, closeLabel, actions }: AddSpeedDialProps) {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const reduceMotion = useReducedMotion();
  const triggerRef = useRef<HTMLButtonElement>(null);
  const itemRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const containerRef = useRef<HTMLDivElement>(null);

  const close = useCallback((returnFocus = true) => {
    setOpen(false);
    if (returnFocus) triggerRef.current?.focus();
  }, []);

  // Escape from anywhere, and an outside pointer press.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        close();
      }
    };
    const onPointer = (e: PointerEvent) => {
      if (!containerRef.current?.contains(e.target as Node)) close(false);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPointer);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onPointer);
    };
  }, [open, close]);

  // Move focus to the first action so keyboard users land inside the menu.
  useEffect(() => {
    if (open) itemRefs.current[0]?.focus();
  }, [open]);

  const onItemKeyDown = (e: React.KeyboardEvent, index: number) => {
    const last = actions.length - 1;
    let next: number | null = null;
    if (e.key === "ArrowUp") next = index === 0 ? last : index - 1;
    else if (e.key === "ArrowDown") next = index === last ? 0 : index + 1;
    else if (e.key === "Home") next = 0;
    else if (e.key === "End") next = last;
    else if (e.key === "Tab") { close(false); return; }
    if (next !== null) {
      e.preventDefault();
      itemRefs.current[next]?.focus();
    }
  };

  const go = (href: string) => {
    setOpen(false);
    router.push(href);
  };

  // Rendered bottom-up: the LAST action sits closest to the button, so the
  // first one in the array ends up highest — matching how the list reads.
  const stacked = [...actions].reverse();

  return (
    <div
      ref={containerRef}
      className="add-fab-wrap"
      style={{ position: "fixed", right: 20, bottom: 20, zIndex: 40 }}
    >
      {/* Scrim: dims the page and gives a big tap target to dismiss. */}
      <AnimatePresence>
        {open && (
          <motion.div
            aria-hidden
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: reduceMotion ? 0 : 0.16 }}
            onClick={() => close(false)}
            style={{
              position: "fixed",
              inset: 0,
              background: "rgba(0,0,0,0.32)",
              backdropFilter: "blur(1.5px)",
              zIndex: -1,
            }}
          />
        )}
      </AnimatePresence>

      <div
        role="menu"
        aria-label={label}
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "flex-end",
          gap: 10,
          marginBottom: open ? 12 : 0,
        }}
      >
        <AnimatePresence>
          {open &&
            stacked.map((action, stackIndex) => {
              // Index in the original (visual top-down) order, for key nav.
              const index = actions.length - 1 - stackIndex;
              return (
                <motion.button
                  key={action.key}
                  ref={(el) => { itemRefs.current[index] = el; }}
                  role="menuitem"
                  type="button"
                  onClick={() => go(action.href)}
                  onKeyDown={(e) => onItemKeyDown(e, index)}
                  initial={reduceMotion ? { opacity: 0 } : { opacity: 0, y: 12, scale: 0.94 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={reduceMotion ? { opacity: 0 } : { opacity: 0, y: 8, scale: 0.96 }}
                  transition={
                    reduceMotion
                      ? { duration: 0 }
                      : { duration: 0.18, delay: stackIndex * 0.04, ease: [0.2, 0.8, 0.2, 1] }
                  }
                  className="add-fab-item"
                  style={{
                    display: "inline-flex",
                    alignItems: "center",
                    gap: 10,
                    padding: "12px 18px",
                    borderRadius: 999,
                    border: "1px solid var(--border)",
                    background: "var(--surface)",
                    color: "var(--text)",
                    fontWeight: 600,
                    fontSize: 15,
                    cursor: "pointer",
                    boxShadow: "var(--shadow-lg)",
                    whiteSpace: "nowrap",
                  }}
                >
                  {action.icon}
                  {action.label}
                </motion.button>
              );
            })}
        </AnimatePresence>
      </div>

      <button
        ref={triggerRef}
        type="button"
        aria-label={open ? closeLabel : label}
        aria-expanded={open}
        aria-haspopup="menu"
        onClick={() => setOpen((v) => !v)}
        className="add-fab"
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 8,
          borderRadius: 999,
          border: "none",
          padding: "14px 20px",
          background: "var(--accent)",
          color: "#fff",
          fontWeight: 600,
          fontSize: 15,
          cursor: "pointer",
          boxShadow: "var(--shadow-lg)",
          transition: "transform 0.15s",
        }}
        onMouseDown={(e) => (e.currentTarget.style.transform = "scale(0.96)")}
        onMouseUp={(e) => (e.currentTarget.style.transform = "scale(1)")}
      >
        <motion.span
          aria-hidden
          animate={{ rotate: open && !reduceMotion ? 135 : 0 }}
          transition={{ duration: reduceMotion ? 0 : 0.2, ease: [0.2, 0.8, 0.2, 1] }}
          style={{ display: "inline-flex" }}
        >
          {/* The icon swap is belt-and-braces for reduced motion, where the
              rotation that would turn + into x is disabled. */}
          {open && reduceMotion ? <CloseIcon size={20} /> : <PlusIcon size={20} />}
        </motion.span>
        {/* The label would collide with the open menu, so it hides on open. */}
        {!open && label}
      </button>
    </div>
  );
}

export { ReceiptIcon };
