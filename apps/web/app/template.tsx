"use client";

import { motion } from "framer-motion";
import type { ReactNode } from "react";

/** Smooth fade/slide on every route change (app-wide polish). */
export default function Template({ children }: { children: ReactNode }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.28, ease: [0.2, 0, 0, 1] }}
    >
      {children}
    </motion.div>
  );
}
