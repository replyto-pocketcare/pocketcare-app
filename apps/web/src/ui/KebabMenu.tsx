"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { MoreIcon } from "./icons";

export interface KebabItem {
  label: string;
  onClick: () => void;
  /** Render in the danger colour (e.g. Remove/Delete). */
  danger?: boolean;
}

/**
 * A compact "⋮" button that opens a dropdown of row actions.
 *
 * THE DROPDOWN IS PORTALLED, and that is the whole point.
 *
 * It used to be `position: absolute` inside the row. Any ancestor with
 * `overflow: hidden` then clips it — and rows are *routinely* wrapped in
 * `.card` with `overflow: hidden` so the card's rounded corners crop their
 * contents (`recurring/GroupSection.tsx`, `groups/[id]/page.tsx`, …). The menu
 * was cut off, and the fix would have had to be repeated at every call site,
 * forever, with each new one a fresh chance to forget.
 *
 * Rendering into `document.body` with fixed coordinates makes it structurally
 * impossible: no ancestor can clip something that isn't inside it. The cost is
 * that fixed coordinates go stale when the page moves, so the menu closes on
 * scroll and resize rather than trying to chase the button.
 */
export function KebabMenu({ items, label = "Actions" }: { items: KebabItem[]; label?: string }) {
  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null);
  const btnRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  /** Has this open cycle already re-placed using the menu's real height? */
  const measured = useRef(false);

  const MENU_W = 168;
  const GAP = 6;

  /** Place the menu against the button, flipping and clamping to stay on screen. */
  const place = useCallback(() => {
    const btn = btnRef.current;
    if (!btn) return;
    const r = btn.getBoundingClientRect();
    // Measured if we can, estimated on the first frame before it exists.
    const h = menuRef.current?.offsetHeight ?? items.length * 44 + 2;

    // Below by default; above when there isn't room — the last row in a list is
    // exactly where this menu is most likely to be used, and it's the row with
    // the least space beneath it.
    const below = r.bottom + GAP;
    const top = below + h > window.innerHeight - 8 && r.top - GAP - h > 8 ? r.top - GAP - h : below;

    // Right-align to the button, then clamp so it can't run off either edge.
    const left = Math.min(Math.max(8, r.right - MENU_W), window.innerWidth - MENU_W - 8);
    setPos({ top, left });
  }, [items.length]);

  // Before paint, so the menu never appears in the wrong place for a frame.
  useLayoutEffect(() => {
    if (!open) {
      measured.current = false;
      setPos(null); // force a fresh measurement next time it opens
      return;
    }
    place();
  }, [open, place]);

  // Second pass, once: the first runs before the menu exists, so it flips using
  // an ESTIMATED height. Now that it's mounted, re-place with the real one —
  // guarded by a ref so this can't ping-pong with its own setPos.
  useLayoutEffect(() => {
    if (!open || !pos || measured.current || !menuRef.current) return;
    measured.current = true;
    place();
  }, [open, pos, place]);

  useEffect(() => {
    if (!open) return;

    // `pointerdown` covers mouse AND touch. The old handler listened only for
    // `mousedown`, so on a phone tapping outside never dismissed the menu.
    const onDown = (e: Event) => {
      const t = e.target as Node;
      if (btnRef.current?.contains(t) || menuRef.current?.contains(t)) return;
      setOpen(false);
    };
    // Fixed coordinates are only correct until the page moves, so don't try to
    // follow it — close. `capture` catches scrolls in any nested container.
    const onMove = () => setOpen(false);
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };

    document.addEventListener("pointerdown", onDown, true);
    window.addEventListener("scroll", onMove, true);
    window.addEventListener("resize", onMove);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onDown, true);
      window.removeEventListener("scroll", onMove, true);
      window.removeEventListener("resize", onMove);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const menu =
    open && pos && typeof document !== "undefined"
      ? createPortal(
          <div
            ref={menuRef}
            role="menu"
            style={{
              position: "fixed", top: pos.top, left: pos.left, width: MENU_W,
              // Below Modal's overlay (100) so a dialog always wins, well above
              // sticky headers and the app shell's banners.
              zIndex: 90,
              background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 10,
              boxShadow: "var(--shadow-lg)", overflow: "hidden",
            }}
          >
            {items.map((it, i) => (
              <button
                key={i}
                role="menuitem"
                onClick={() => { setOpen(false); it.onClick(); }}
                style={{
                  display: "block", width: "100%", textAlign: "left", padding: "11px 14px",
                  border: "none", borderTop: i ? "1px solid var(--border)" : "none",
                  background: "transparent", cursor: "pointer", fontSize: 14,
                  color: it.danger ? "var(--negative)" : "var(--text)",
                }}
              >
                {it.label}
              </button>
            ))}
          </div>,
          document.body,
        )
      : null;

  return (
    <div style={{ position: "relative", flexShrink: 0 }}>
      <button
        ref={btnRef}
        className="chip"
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        style={{ padding: 8, display: "inline-flex", alignItems: "center", justifyContent: "center", color: "var(--text-2)" }}
      >
        <MoreIcon size={18} />
      </button>
      {menu}
    </div>
  );
}
