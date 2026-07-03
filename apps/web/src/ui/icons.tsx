"use client";

/** Minimal, professional SVG icon set. All use currentColor and inherit size. */
type P = { size?: number; strokeWidth?: number };
const base = (size: number) => ({ width: size, height: size, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeLinecap: "round" as const, strokeLinejoin: "round" as const });

export function EyeIcon({ size = 18, strokeWidth = 1.8 }: P) {
  return (
    <svg {...base(size)} strokeWidth={strokeWidth} aria-hidden>
      <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

export function EyeOffIcon({ size = 18, strokeWidth = 1.8 }: P) {
  return (
    <svg {...base(size)} strokeWidth={strokeWidth} aria-hidden>
      <path d="M10.6 6.1A9.7 9.7 0 0 1 12 6c6.5 0 10 6 10 6a15.6 15.6 0 0 1-3.4 4.1M6.2 6.2A15.7 15.7 0 0 0 2 12s3.5 6 10 6a9.4 9.4 0 0 0 4.2-1" />
      <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2" />
      <path d="m2 2 20 20" />
    </svg>
  );
}

export function SlidersIcon({ size = 18, strokeWidth = 1.8 }: P) {
  return (
    <svg {...base(size)} strokeWidth={strokeWidth} aria-hidden>
      <path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3" />
      <path d="M2 14h4M10 8h4M18 16h4" />
    </svg>
  );
}

export function MoreIcon({ size = 18 }: P) {
  return (
    <svg {...base(size)} aria-hidden>
      <circle cx="12" cy="5" r="1.5" fill="currentColor" stroke="none" />
      <circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none" />
      <circle cx="12" cy="19" r="1.5" fill="currentColor" stroke="none" />
    </svg>
  );
}

export function SunIcon({ size = 18, strokeWidth = 1.8 }: P) {
  return (
    <svg {...base(size)} strokeWidth={strokeWidth} aria-hidden>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
  );
}

export function MoonIcon({ size = 18, strokeWidth = 1.8 }: P) {
  return (
    <svg {...base(size)} strokeWidth={strokeWidth} aria-hidden>
      <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" />
    </svg>
  );
}

export function LockIcon({ size = 18, strokeWidth = 1.8 }: P) {
  return (
    <svg {...base(size)} strokeWidth={strokeWidth} aria-hidden>
      <rect x="4.5" y="11" width="15" height="9" rx="2" />
      <path d="M8 11V8a4 4 0 0 1 8 0v3" />
    </svg>
  );
}

export function MenuIcon({ size = 20, strokeWidth = 1.8 }: P) {
  return (
    <svg {...base(size)} strokeWidth={strokeWidth} aria-hidden>
      <path d="M3 6h18M3 12h18M3 18h18" />
    </svg>
  );
}

export function PlusIcon({ size = 18, strokeWidth = 1.9 }: P) {
  return (
    <svg {...base(size)} strokeWidth={strokeWidth} aria-hidden>
      <path d="M12 5v14M5 12h14" />
    </svg>
  );
}

export function DownloadIcon({ size = 18, strokeWidth = 1.8 }: P) {
  return (
    <svg {...base(size)} strokeWidth={strokeWidth} aria-hidden>
      <path d="M12 3v12m0 0 4-4m-4 4-4-4" />
      <path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2" />
    </svg>
  );
}
