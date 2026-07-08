"use client";

/** Story-style segmented progress: vertical on mobile, horizontal on desktop. */
export function ProgressRail({ total, activeIndex, layout, onJump }: {
  total: number; activeIndex: number; layout: "mobile" | "desktop"; onJump?: (i: number) => void;
}) {
  const vertical = layout === "mobile";
  const segs = Array.from({ length: total });
  return (
    <div
      aria-hidden
      style={{
        position: "absolute", zIndex: 20, display: "flex", gap: 5,
        flexDirection: vertical ? "column" : "row",
        ...(vertical
          ? { right: 10, top: "50%", transform: "translateY(-50%)", height: "min(46%, 320px)" }
          : { top: 14, left: "50%", transform: "translateX(-50%)", width: "min(52%, 520px)" }),
      }}
    >
      {segs.map((_, i) => (
        <button
          key={i}
          onClick={() => onJump?.(i)}
          title={`Insight ${i + 1}`}
          style={{
            flex: 1, border: "none", padding: 0, cursor: onJump ? "pointer" : "default",
            borderRadius: 999,
            width: vertical ? 4 : undefined, height: vertical ? undefined : 4,
            background: i <= activeIndex ? "var(--accent)" : "var(--border)",
            opacity: i <= activeIndex ? 1 : 0.7,
            transition: "background 0.25s, opacity 0.25s",
          }}
        />
      ))}
    </div>
  );
}
