"use client";

import { motion, useReducedMotion } from "framer-motion";

/**
 * The assistant's animated mark — built from the Sanvya leaf rather than a
 * generic 3D sphere, so the thing the user talks to is unmistakably ours.
 *
 * Layered as absolutely-positioned HTML rather than one animated SVG on
 * purpose: transform-origin on SVG groups is a well-known source of
 * cross-browser drift (`transform-box` support varies, and Safari has
 * historically mis-centred percentage origins). Composing HTML layers keeps
 * every rotation and scale about a genuine centre, and each layer promotes to
 * its own compositor layer, so the loop costs no main-thread work.
 *
 * Honours `prefers-reduced-motion`: the mark still renders in full, it simply
 * holds still — the brand reads the same, the vestibular trigger doesn't fire.
 */
export type OrbState = "idle" | "thinking";

export function AssistantOrb({ size = 132, state = "idle" }: { size?: number; state?: OrbState }) {
  const still = useReducedMotion();
  const busy = state === "thinking";

  // One knob drives the whole system: thinking simply runs the same motion
  // faster and a little wider, so the two states read as one object with a
  // change of mood rather than two different animations.
  const spin = busy ? 7 : 20;
  const breathe = busy ? 1.8 : 4.6;

  const loop = (duration: number, extra: object = {}) =>
    still ? { duration: 0 } : { duration, repeat: Infinity, ease: "easeInOut" as const, ...extra };

  return (
    <div className="orb" style={{ width: size, height: size }} aria-hidden>
      {/* Two offset halos breathing out of phase — reads as a soft glow that
          never quite repeats, instead of an obvious single pulse. */}
      <motion.span
        className="orb-halo"
        animate={still ? {} : { scale: [1, 1.16, 1], opacity: [0.34, 0.14, 0.34] }}
        transition={loop(breathe)}
      />
      <motion.span
        className="orb-halo orb-halo-2"
        animate={still ? {} : { scale: [1.1, 0.94, 1.1], opacity: [0.16, 0.32, 0.16] }}
        transition={loop(breathe * 1.35)}
      />

      {/* Orbiting seeds. Counter-rotating rings give depth without 3D. */}
      <motion.span
        className="orb-orbit"
        animate={still ? {} : { rotate: 360 }}
        transition={still ? { duration: 0 } : { duration: spin, repeat: Infinity, ease: "linear" }}
      >
        <span className="orb-seed" style={{ transform: "rotate(0deg) translateY(-46%)" }} />
        <span className="orb-seed orb-seed-sm" style={{ transform: "rotate(130deg) translateY(-46%)" }} />
        <span className="orb-seed orb-seed-sm" style={{ transform: "rotate(238deg) translateY(-46%)" }} />
      </motion.span>
      <motion.span
        className="orb-orbit orb-orbit-2"
        animate={still ? {} : { rotate: -360 }}
        transition={still ? { duration: 0 } : { duration: spin * 1.7, repeat: Infinity, ease: "linear" }}
      >
        <span className="orb-seed orb-seed-sm" style={{ transform: "rotate(64deg) translateY(-42%)" }} />
        <span className="orb-seed orb-seed-sm" style={{ transform: "rotate(196deg) translateY(-42%)" }} />
      </motion.span>

      {/* The core: our leaf, sitting in the accent gradient. */}
      <motion.span
        className="orb-core"
        animate={still ? {} : { scale: [1, 1.05, 1] }}
        transition={loop(breathe)}
      >
        <motion.svg
          viewBox="0 0 48 48"
          fill="none"
          className="orb-leaf"
          animate={still ? {} : { rotate: [-4, 4, -4] }}
          transition={loop(breathe * 1.6)}
        >
          <path d="M24 11c-8 4.5-10.5 16-0 25 10.5-9 8-20.5 0-25z" fill="#FFFDF9" />
          {/* The veins draw themselves in on a loop — the "thinking" tell. */}
          <motion.path
            d="M24 15v18"
            stroke="var(--accent)"
            strokeWidth="2.2"
            strokeLinecap="round"
            pathLength={1}
            animate={still ? {} : { pathLength: [0.15, 1, 0.15], opacity: [0.55, 1, 0.55] }}
            transition={loop(breathe * 0.9)}
          />
          <motion.path
            d="M24 22l4.5-3M24 27l-4.5-3"
            stroke="var(--accent)"
            strokeWidth="1.8"
            strokeLinecap="round"
            pathLength={1}
            animate={still ? {} : { pathLength: [0, 1, 0], opacity: [0.3, 1, 0.3] }}
            transition={loop(breathe * 0.9, { delay: 0.25 })}
          />
        </motion.svg>
      </motion.span>
    </div>
  );
}
