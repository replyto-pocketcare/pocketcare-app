"use client";

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { AnimatePresence, motion } from "framer-motion";

/** Everything focusable inside the dialog, in document order. */
const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function Modal({ open, onClose, children, label }: {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  /** Accessible name. Falls back to "Dialog" — pass something specific. */
  label?: string;
}) {
  // Render into <body> via a portal so the fixed overlay is anchored to the
  // viewport — NOT to a transformed ancestor (framer-motion route/page
  // animations set `transform`, which otherwise re-anchors `position:fixed` and
  // pushes dialogs below the fold on mobile).
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  // Lock body scroll while a dialog is open.
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = prev; };
  }, [open]);

  const panelRef = useRef<HTMLDivElement>(null);
  const restoreTo = useRef<HTMLElement | null>(null);

  /**
   * Keyboard contract for a dialog: Escape closes it, and Tab cycles WITHIN it.
   * Without the trap, tabbing walked straight out into the page behind the
   * scrim — the page is still there, just visually dimmed — so a keyboard or
   * screen-reader user could operate controls they can't see.
   */
  const onKeyDown = useCallback((e: KeyboardEvent) => {
    if (!open) return;
    if (e.key === "Escape") { e.stopPropagation(); onClose(); return; }
    if (e.key !== "Tab") return;

    const panel = panelRef.current;
    if (!panel) return;
    const items = [...panel.querySelectorAll<HTMLElement>(FOCUSABLE)]
      .filter((el) => el.offsetParent !== null || el === document.activeElement);
    if (items.length === 0) { e.preventDefault(); panel.focus(); return; }

    const first = items[0]!;
    const last = items[items.length - 1]!;
    const active = document.activeElement;
    // Wrap at both ends, and pull focus back in if it has already escaped.
    if (e.shiftKey && (active === first || !panel.contains(active))) {
      e.preventDefault(); last.focus();
    } else if (!e.shiftKey && (active === last || !panel.contains(active))) {
      e.preventDefault(); first.focus();
    }
  }, [open, onClose]);

  useEffect(() => {
    if (!open) return;
    document.addEventListener("keydown", onKeyDown, true);
    return () => document.removeEventListener("keydown", onKeyDown, true);
  }, [open, onKeyDown]);

  // Move focus in on open, and put it back where it came from on close —
  // otherwise focus lands on <body> and keyboard users lose their place.
  useEffect(() => {
    if (!open) return;
    restoreTo.current = document.activeElement as HTMLElement | null;
    const id = requestAnimationFrame(() => {
      const panel = panelRef.current;
      if (!panel) return;
      const firstField = panel.querySelector<HTMLElement>(FOCUSABLE);
      (firstField ?? panel).focus({ preventScroll: true });
    });
    return () => {
      cancelAnimationFrame(id);
      restoreTo.current?.focus?.({ preventScroll: true });
    };
  }, [open]);

  const content = (
    <AnimatePresence>
      {open && (
        <motion.div
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
          onClick={onClose}
          style={{ position: "fixed", inset: 0, background: "rgba(43,39,35,0.45)", backdropFilter: "blur(2px)", zIndex: 100, overflowY: "auto", WebkitOverflowScrolling: "touch" }}
        >
          {/* min-height:100% + auto margins keep the card centred when it fits and
              fully reachable (scroll from the top) when it's taller than the screen. */}
          <div style={{ minHeight: "100%", display: "flex", alignItems: "center", justifyContent: "center", padding: "24px 16px", boxSizing: "border-box" }}>
            <motion.div
              ref={panelRef}
              role="dialog"
              aria-modal="true"
              aria-label={label ?? "Dialog"}
              tabIndex={-1}
              initial={{ opacity: 0, scale: 0.94, y: 12 }} animate={{ opacity: 1, scale: 1, y: 0 }} exit={{ opacity: 0, scale: 0.96, y: 8 }}
              transition={{ type: "spring", stiffness: 220, damping: 22 }}
              onClick={(e) => e.stopPropagation()}
              className="card"
              style={{ maxWidth: 440, width: "100%", padding: 24, margin: "auto", outline: "none" }}
            >
              {children}
            </motion.div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );

  if (!mounted) return null;
  return createPortal(content, document.body);
}
