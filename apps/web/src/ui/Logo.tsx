"use client";

/** PocketCare logo mark — an earthy leaf nestled in a rounded pocket. */
export function LogoMark({ size = 32 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 48 48" fill="none" aria-hidden>
      <rect width="48" height="48" rx="13" fill="var(--accent)" />
      {/* leaf */}
      <path d="M24 11c-8 4.5-10.5 16-0 25 10.5-9 8-20.5 0-25z" fill="#FFFDF9" />
      {/* vein */}
      <path d="M24 15v18" stroke="var(--accent)" strokeWidth="2.2" strokeLinecap="round" />
      <path d="M24 22l4.5-3M24 27l-4.5-3" stroke="var(--accent)" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
  );
}

export function Logo({ size = 30, wordmark = true }: { size?: number; wordmark?: boolean }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 10 }}>
      <LogoMark size={size} />
      {wordmark && (
        <strong style={{ fontSize: size * 0.62, letterSpacing: "-0.02em" }}>
          Pocket<span style={{ color: "var(--accent)" }}>Care</span>
        </strong>
      )}
    </span>
  );
}
