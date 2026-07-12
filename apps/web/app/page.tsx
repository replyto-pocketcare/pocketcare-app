"use client";

import { useState, useRef, useEffect } from "react";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { format, type Money } from "@pocketcare/money";
import { useNetWorth, useAccountBalances } from "../src/hooks";
import { useEntitlement } from "../src/entitlement";
import { useAmountsHidden, setAmountsHidden } from "../src/prefs";
import { colorForId } from "../src/colors";
import { getDb } from "../src/powersync";
import { EyeIcon, EyeOffIcon, PlusIcon, SlidersIcon, LockIcon, ScaleIcon } from "../src/ui/icons";
import { Modal } from "../src/ui/Modal";
import { useDashboardTiles, setTileEnabled, reorderTiles, useTileSpans, setTileSpan, type TileId, type TileSpan } from "../src/dashboard";
import { TILE_CATALOG, TileView, tileMeta } from "../src/dashboard/tiles";

const ResizeIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 21H5a1 1 0 0 1-1-1v-4M15 3h4a1 1 0 0 1 1 1v4M4 20l6-6M20 4l-6 6" /></svg>
);
const CheckIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 13l4 4L19 7" /></svg>
);

export default function Dashboard() {
  const { total, available, base } = useNetWorth();
  const balances = useAccountBalances();
  const hidden = useAmountsHidden();
  const { isPaid } = useEntitlement();
  const enabled = useDashboardTiles();
  const spans = useTileSpans();
  const [showAvailable, setShowAvailable] = useState(false);
  const [showAdd, setShowAdd] = useState(false);
  const [editing, setEditing] = useState(false);
  const { t } = useTranslation();
  const net = showAvailable ? available : total;

  const fmt = (m: Money) => (hidden ? "••••••" : format(m, "en-US"));

  // Only show tiles the user enabled; premium tiles need a paid plan.
  const visibleTiles = enabled.filter((id) => isPaid || !tileMeta(id).premium);
  const spanOf = (id: TileId): TileSpan => spans[id] ?? tileMeta(id).span;

  async function toggleNw(id: string, included: boolean) {
    await getDb()?.execute("UPDATE accounts SET include_in_net_worth = ?, updated_at = ? WHERE id = ?", [included ? 0 : 1, new Date().toISOString(), id]);
  }

  if (balances.length === 0) {
    return (
      <div className="fade-up" style={{ minHeight: "70vh", display: "grid", placeItems: "center" }}>
        <div className="card" style={{ maxWidth: 460, padding: 36, textAlign: "center", display: "grid", gap: 14, background: "radial-gradient(120% 120% at 50% 0%, var(--accent-ghost), var(--surface) 70%)" }}>
          <h1 style={{ fontSize: 26 }}>Welcome to PocketCare</h1>
          <p className="muted" style={{ lineHeight: 1.6 }}>Start by adding your first account — a bank, cash, a card, or investments.</p>
          <Link href="/accounts/new" className="btn" style={{ justifySelf: "center", padding: "12px 20px", gap: 6 }}><PlusIcon size={16} /> Add your first account</Link>
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: "grid", gap: 24, minWidth: 0, maxWidth: "100%", overflowX: "hidden" }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12, flexWrap: "wrap" }}>
        <div>
          <h1>{t("pages.dashboard", "Dashboard")}</h1>
          {editing && (
            <div style={{ fontSize: 12.5, color: "var(--accent)", marginTop: 5 }}>
              Drag cards to rearrange · tap the corner handle to resize
            </div>
          )}
        </div>
        {editing ? (
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button className="btn ghost" onClick={() => setShowAdd(true)} style={{ gap: 6 }}><PlusIcon size={16} /> Widget</button>
            <button className="btn" onClick={() => setEditing(false)} style={{ gap: 7, background: "var(--positive)", boxShadow: "0 10px 24px -12px rgba(95,102,71,0.9)" }}><CheckIcon /> Done</button>
          </div>
        ) : (
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button className="chip" onClick={() => setEditing(true)} title="Customize tiles" style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <SlidersIcon size={16} /> Customize
            </button>
            <button className="chip" onClick={() => setAmountsHidden(!hidden)} title={hidden ? "Show amounts" : "Hide amounts"} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              {hidden ? <EyeIcon size={16} /> : <EyeOffIcon size={16} />} {hidden ? "Show" : "Hide"}
            </button>
            <Link href="/accounts/new" className="btn ghost" style={{ gap: 6 }}><PlusIcon size={16} /> Account</Link>
          </div>
        )}
      </div>

      {/* Net worth hero */}
      <section className="card" style={{ padding: 28, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap", minWidth: 0, maxWidth: "100%", boxSizing: "border-box" }}>
        <div style={{ minWidth: 0 }}>
          <div className="muted" style={{ fontSize: 13 }}>{showAvailable ? t("netWorth.available", "Available net worth") : t("netWorth.title", "Net worth")}</div>
          <div style={{ fontSize: "clamp(30px, 9vw, 44px)", fontWeight: 750, letterSpacing: "-0.02em", color: "var(--forest)", overflowWrap: "anywhere" }}>{fmt(net)}</div>
          <div className="muted" style={{ fontSize: 13 }}>Base currency {base}</div>
        </div>
        <button className="chip" data-active={showAvailable} onClick={() => setShowAvailable((v) => !v)}>
          {showAvailable ? "Excluding blocked" : "Including blocked"}
        </button>
      </section>

      {/* Accounts */}
      <section style={{ display: "grid", gap: 12 }}>
        <h2>Accounts</h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(min(230px, 100%), 1fr))", gap: 12 }}>
          {balances.map(({ account, balance }) => {
            const included = account.include_in_net_worth !== 0;
            const color = account.color || colorForId(account.id);
            return (
              <div key={account.id} className="card" style={{ padding: 0, overflow: "hidden", display: "flex" }}>
                <div style={{ width: 5, background: color }} />
                <div style={{ padding: 16, display: "grid", gap: 3, flex: 1, minWidth: 0 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
                    <span className="muted" style={{ fontSize: 12, textTransform: "capitalize", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{account.type.replace("_", " ")}</span>
                    <button onClick={() => toggleNw(account.id, included)} title={included ? "Counts toward net worth — click to exclude" : "Excluded from net worth — click to include"}
                      style={{ background: "transparent", border: "none", cursor: "pointer", color: included ? "var(--accent)" : "var(--text-2)", opacity: included ? 1 : 0.4, display: "inline-flex", padding: 0, flexShrink: 0 }}>
                      <ScaleIcon size={16} />
                    </button>
                  </div>
                  <span style={{ fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{account.name}</span>
                  <span style={{ fontSize: 20, fontWeight: 700, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{fmt(balance)}</span>
                </div>
              </div>
            );
          })}
        </div>
      </section>

      {/* Customizable tiles — long-press to edit, drag to reorder, tap corner to resize */}
      {visibleTiles.length > 0 ? (
        <DraggableGrid ids={visibleTiles} editing={editing} onLongPress={() => setEditing(true)} spanOf={spanOf} />
      ) : (
        <section className="card" style={{ padding: 24, textAlign: "center", display: "grid", gap: 8 }}>
          <p className="muted">No tiles shown. Add some to your dashboard.</p>
          <button className="btn" style={{ justifySelf: "center", gap: 6 }} onClick={() => setShowAdd(true)}><PlusIcon size={16} /> Add a widget</button>
        </section>
      )}

      <AddWidgetModal open={showAdd} onClose={() => setShowAdd(false)} enabled={enabled} isPaid={isPaid} />
    </div>
  );
}

/**
 * Dashboard tiles with an edit mode that mirrors the design:
 *  - Long-press any tile (~450ms) to enter edit mode (or the Customize button).
 *  - In edit mode tiles wiggle; drag a tile to reorder — the layout snaps live to
 *    the 2-column grid slots by hit-testing rendered rects, persisted on release.
 *  - A corner handle cycles the tile between half- and full-width (persisted).
 *  - A remove handle takes the tile off the dashboard.
 */
function DraggableGrid({ ids, editing, onLongPress, spanOf }: {
  ids: TileId[]; editing: boolean; onLongPress: () => void; spanOf: (id: TileId) => TileSpan;
}) {
  const [order, setOrder] = useState<TileId[]>(ids);
  const [dragging, setDragging] = useState<TileId | null>(null);
  const refs = useRef<Map<TileId, HTMLElement>>(new Map());
  const hold = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const start = useRef<{ x: number; y: number } | null>(null);
  useEffect(() => { if (!dragging) setOrder(ids); }, [ids.join(","), dragging]);

  const clearHold = () => { if (hold.current) { clearTimeout(hold.current); hold.current = undefined; } };

  function reorderTo(e: React.PointerEvent) {
    if (!dragging) return;
    const { clientX: x, clientY: y } = e;
    let target: TileId | null = null;
    for (const [tid, el] of refs.current) {
      const r = el.getBoundingClientRect();
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) { target = tid; break; }
    }
    if (!target || target === dragging) return;
    setOrder((prev) => {
      const from = prev.indexOf(dragging), to = prev.indexOf(target!);
      if (from < 0 || to < 0) return prev;
      const next = [...prev];
      const [m] = next.splice(from, 1);
      next.splice(to, 0, m!);
      return next;
    });
  }

  function down(e: React.PointerEvent, id: TileId) {
    start.current = { x: e.clientX, y: e.clientY };
    const el = e.currentTarget as HTMLElement;
    const pid = e.pointerId;
    if (editing) {
      el.setPointerCapture(pid);
      setDragging(id);
    } else {
      // Long-press enters edit mode and begins dragging the held tile.
      hold.current = setTimeout(() => { onLongPress(); el.setPointerCapture(pid); setDragging(id); }, 450);
    }
  }
  function pmove(e: React.PointerEvent) {
    if (dragging) { reorderTo(e); return; }
    if (hold.current && start.current && (Math.abs(e.clientX - start.current.x) > 8 || Math.abs(e.clientY - start.current.y) > 8)) {
      clearHold(); // moved before the hold fired — treat as a scroll
    }
  }
  function up() {
    clearHold();
    if (dragging) { reorderTiles(order); setDragging(null); }
  }

  return (
    <div className="dash-grid">
      {order.map((id) => {
        const full = spanOf(id) === "full";
        const isDrag = dragging === id;
        return (
          <div
            key={id}
            ref={(el) => { if (el) refs.current.set(id, el); else refs.current.delete(id); }}
            onPointerDown={(e) => down(e, id)}
            onPointerMove={pmove}
            onPointerUp={up}
            onPointerCancel={up}
            style={{
              gridColumn: full ? "1 / -1" : "auto",
              position: "relative",
              borderRadius: 24,
              touchAction: editing ? "none" : "auto",
              cursor: editing ? (isDrag ? "grabbing" : "grab") : "default",
              opacity: isDrag ? 0.7 : 1,
              transform: isDrag ? "scale(0.99)" : undefined,
              boxShadow: isDrag ? "var(--shadow-lg)" : undefined,
              zIndex: isDrag ? 5 : undefined,
              transition: "box-shadow 150ms ease, opacity 150ms ease",
              animation: editing && !isDrag ? "tileWiggle 0.55s ease-in-out infinite" : undefined,
            }}
          >
            {editing && (
              <>
                <button
                  aria-label={full ? "Make half width" : "Make full width"} title="Resize"
                  onPointerDown={(e) => e.stopPropagation()}
                  onClick={() => setTileSpan(id, full ? "half" : "full")}
                  style={{ position: "absolute", top: 10, left: 10, zIndex: 6, width: 30, height: 30, borderRadius: 999, background: "var(--accent)", border: "2px solid var(--surface)", display: "grid", placeItems: "center", cursor: "pointer", boxShadow: "0 6px 14px -6px rgba(43,39,35,0.5)" }}
                >
                  <ResizeIcon />
                </button>
                <button
                  aria-label="Remove tile" title="Remove"
                  onPointerDown={(e) => e.stopPropagation()}
                  onClick={() => setTileEnabled(id, false)}
                  style={{ position: "absolute", top: 10, right: 10, zIndex: 6, width: 28, height: 28, borderRadius: 999, background: "var(--negative)", border: "2px solid var(--surface)", display: "grid", placeItems: "center", cursor: "pointer", boxShadow: "0 6px 14px -6px rgba(43,39,35,0.5)" }}
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round"><path d="M5 12h14" /></svg>
                </button>
              </>
            )}
            {/* Freeze interactions inside the tile while editing so drags don't trigger links. */}
            <div style={{ pointerEvents: editing ? "none" : "auto" }}>
              <TileView id={id} />
            </div>
          </div>
        );
      })}
    </div>
  );
}

/** Add-a-widget picker — the tiles not currently on the dashboard. */
function AddWidgetModal({ open, onClose, enabled, isPaid }: {
  open: boolean; onClose: () => void; enabled: TileId[]; isPaid: boolean;
}) {
  const available = TILE_CATALOG.filter((t) => !enabled.includes(t.id));
  return (
    <Modal open={open} onClose={onClose}>
      <div style={{ display: "grid", gap: 4, marginBottom: 12 }}>
        <h2 style={{ margin: 0 }}>Add a widget</h2>
        <p className="muted" style={{ fontSize: 13 }}>Pick a tile to add to your dashboard. Resize and reorder it right on the page.</p>
      </div>

      <div style={{ display: "grid", gap: 8, maxHeight: "60vh", overflowY: "auto" }}>
        {available.length === 0 ? (
          <p className="muted" style={{ fontSize: 13, padding: "8px 2px" }}>Every widget is already on your dashboard.</p>
        ) : available.map((t) => {
          const locked = !!t.premium && !isPaid;
          return (
            <div key={t.id} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: "11px 14px", borderRadius: 12, border: "1px solid var(--border)", background: "var(--surface-2)", opacity: locked ? 0.6 : 1 }}>
              <span style={{ display: "inline-flex", alignItems: "center", gap: 8, fontSize: 14 }}>
                {t.title}
                {locked && <span className="muted" style={{ display: "inline-flex", alignItems: "center", gap: 4, fontSize: 12 }}><LockIcon size={13} /> Premium</span>}
              </span>
              <button className="btn" style={{ padding: "6px 14px", gap: 5 }} disabled={locked} onClick={() => { setTileEnabled(t.id, true); }}><PlusIcon size={14} /> Add</button>
            </div>
          );
        })}
      </div>

      {!isPaid && (
        <p className="muted" style={{ fontSize: 12, marginTop: 10 }}>
          Premium tiles unlock with a <Link href="/settings">Lite or Pro plan</Link>.
        </p>
      )}
      <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 14 }}>
        <button className="btn" onClick={onClose}>Done</button>
      </div>
    </Modal>
  );
}
