"use client";

import type { ReactNode } from "react";
import { AnimatePresence, motion } from "framer-motion";

export function Modal({ open, onClose, children }: { open: boolean; onClose: () => void; children: ReactNode }) {
  return (
    <AnimatePresence>
      {open && (
        // The overlay is itself the scroll container, and an inner wrapper with
        // min-height:100% centers the card while keeping tall content reachable
        // on mobile (plain place-items:center can push the top off-screen).
        <motion.div
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
          onClick={onClose}
          style={{ position: "fixed", inset: 0, background: "rgba(43,39,35,0.45)", backdropFilter: "blur(2px)", zIndex: 100, overflowY: "auto", WebkitOverflowScrolling: "touch" }}
        >
          <div style={{ minHeight: "100%", display: "flex", alignItems: "center", justifyContent: "center", padding: "24px 16px", boxSizing: "border-box" }}>
            <motion.div
              initial={{ opacity: 0, scale: 0.94, y: 12 }} animate={{ opacity: 1, scale: 1, y: 0 }} exit={{ opacity: 0, scale: 0.96, y: 8 }}
              transition={{ type: "spring", stiffness: 220, damping: 22 }}
              onClick={(e) => e.stopPropagation()}
              className="card"
              style={{ maxWidth: 440, width: "100%", padding: 24 }}
            >
              {children}
            </motion.div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
