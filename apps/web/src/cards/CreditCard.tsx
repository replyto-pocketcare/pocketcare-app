"use client";

/** A polished CSS credit-card face with details rendered on it. */
export function CreditCard({
  name,
  color,
  currency,
  last4,
  network = "PocketCare",
}: {
  name: string;
  color: string;
  currency: string;
  last4: string;
  network?: string;
}) {
  // Derive a rich two-stop gradient from the account colour.
  const grad = `linear-gradient(135deg, ${color} 0%, ${shade(color, -18)} 62%, ${shade(color, -34)} 100%)`;
  return (
    <div
      style={{
        position: "relative",
        width: "100%",
        aspectRatio: "1.586",
        borderRadius: 18,
        background: grad,
        color: "#fff",
        padding: 22,
        boxShadow: "0 18px 40px -18px rgba(43,39,35,0.55)",
        overflow: "hidden",
        display: "flex",
        flexDirection: "column",
        justifyContent: "space-between",
        isolation: "isolate",
      }}
    >
      {/* sheen */}
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(120% 120% at 0% 0%, rgba(255,255,255,0.22), transparent 45%)", zIndex: -1 }} />
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
        <span style={{ fontWeight: 700, letterSpacing: "0.02em", fontSize: 15 }}>{network}</span>
        {/* contactless */}
        <span style={{ opacity: 0.85, fontSize: 18 }}>))) </span>
      </div>

      {/* chip */}
      <div style={{ width: 44, height: 34, borderRadius: 7, background: "linear-gradient(135deg,#e8d4a8,#c9a86a)", boxShadow: "inset 0 0 0 1px rgba(0,0,0,0.15)" }} />

      <div style={{ fontSize: 19, letterSpacing: "0.14em", fontFamily: "ui-monospace, monospace" }}>
        {last4 ? <>••••&nbsp;&nbsp;••••&nbsp;&nbsp;••••&nbsp;&nbsp;{last4}</> : <span style={{ opacity: 0.6 }}>•••• •••• •••• ••••</span>}
      </div>

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end" }}>
        <div>
          <div style={{ fontSize: 10, opacity: 0.7, textTransform: "uppercase", letterSpacing: "0.1em" }}>Card holder</div>
          <div style={{ fontWeight: 600, fontSize: 15 }}>{name}</div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div style={{ fontSize: 10, opacity: 0.7, textTransform: "uppercase", letterSpacing: "0.1em" }}>Currency</div>
          <div style={{ fontWeight: 600 }}>{currency}</div>
        </div>
      </div>
    </div>
  );
}

/** Lighten/darken a hex colour by percent (-100..100). */
function shade(hex: string, percent: number): string {
  const h = hex.replace("#", "");
  const num = parseInt(h.length === 3 ? h.split("").map((c) => c + c).join("") : h, 16);
  const amt = Math.round(2.55 * percent);
  const r = Math.max(0, Math.min(255, (num >> 16) + amt));
  const g = Math.max(0, Math.min(255, ((num >> 8) & 0xff) + amt));
  const b = Math.max(0, Math.min(255, (num & 0xff) + amt));
  return `rgb(${r}, ${g}, ${b})`;
}
