"use client";

import { useEffect, useState } from "react";

/** Tracks the user's reduced-motion preference reactively. */
export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const on = () => setReduced(mq.matches);
    on();
    mq.addEventListener("change", on);
    return () => mq.removeEventListener("change", on);
  }, []);
  return reduced;
}

function hasWebGL(): boolean {
  try {
    const c = document.createElement("canvas");
    return Boolean(c.getContext("webgl2") || c.getContext("webgl"));
  } catch { return false; }
}

/**
 * Whether to render the 3D visuals. False when the user prefers reduced motion
 * or the device lacks WebGL — in which case cards fall back to 2D recharts.
 */
export function usePrefer3D(): boolean {
  const reduced = useReducedMotion();
  const [webgl, setWebgl] = useState(false);
  useEffect(() => { setWebgl(hasWebGL()); }, []);
  return webgl && !reduced;
}

/** Resolve a theme to a concrete hex (three.js can't read CSS variables). */
export const THEME_HEX: Record<string, string> = {
  positive: "#5f7a52",
  warning: "#c08a3e",
  celebratory: "#b06a4f",
  neutral: "#3e4a38",
};
