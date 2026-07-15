"use client";

import { useState, useRef, useEffect } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslation } from "react-i18next";
import { useQuery } from "@powersync/react";
import { format, money, type Money } from "@pocketcare/money";
import { useNetWorth, useAccountBalances, useAccountsLoading } from "../src/hooks";
import { HeroSkeleton, CardsSkeleton } from "../src/ui/Skeleton";
import { useEntitlement } from "../src/entitlement";
import { useAmountsHidden, setAmountsHidden } from "../src/prefs";
import { colorForId } from "../src/colors";
import { EyeIcon, EyeOffIcon, PlusIcon, SlidersIcon, LockIcon } from "../src/ui/icons";
import { Modal } from "../src/ui/Modal";
import { useDashboardTiles, setTileEnabled, reorderTiles, useTileSizes, setTileSize, W_COLS, H_ROWS, nextDim, type TileId, type TileSize } from "../src/dashboard";
import { TILE_CATALOG, TileView, tileMeta, TILE_HREF } from "../src/dashboard/tiles";

// Sensible default size per tile (content-heavy tiles start taller/wider).
const DEFAULT_SIZE: Partial<Record<TileId, TileSize>> = {
  recent: { w: "md", h: "lg" },
  spending: { w: "md", h: "lg" },
  trends: { w: "lg", h: "md" },
  splits: { w: "md", h: "md" },
  budgets: { w: "lg", h: "md" },
  goals: { w: "lg", h: "md" },
  subscriptions: { w: "md", h: "md" },
  cashflow: { w: "lg", h: "md" },
  netTrend: { w: "lg", h: "md" },
  byCategory: { w: "md", h: "md" },
  byLabel: { w: "md", h: "md" },
  monthCompare: { w: "lg", h: "md" },
};
const defaultSize = (id: TileId): TileSize => DEFAULT_SIZE[id] ?? { w: "md", h: "md" };

const WidthIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 12H3M7 8l-4 4 4 4M17 8l4 4-4 4" /></svg>
);
const HeightIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3v18M8 7l4-4 4 4M8 17l4 4 4-4" /></svg>
);
const CheckIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 13l4 4L19 7" /></svg>
);
const sizeBtn: React.CSSProperties = {
  width: 30, height: 30, borderRadius: 999, background: "var(--accent)", border: "2px solid var(--surface)",
  display: "grid", placeItems: "center", cursor: "pointer", boxShadow: "0 6px 14px -6px rgba(43,39,35,0.5)",
};
const moveBtn: React.CSSProperties = {
  width: 28, height: 28, borderRadius: 999, background: "var(--forest)", border: "2px solid var(--surface)",
  display: "grid", placeItems: "center", cursor: "pointer", boxShadow: "0 6px 14px -6px rgba(43,39,35,0.5)",
};

export default function Dashboard() {
  const { total, available, base } = useNetWorth();
  const balances = useAccountBalances();
  const hidden = useAmountsHidden();
  const { isPaid } = useEntitlement();
  const enabled = useDashboardTiles();
  const sizes = useTileSizes();
  const [showAvailable, setShowAvailable] = useState(false);
  const [showAdd, setShowAdd] = useState(false);
  const [editing, setEditing] = useState(false);
  const { t } = useTranslation();
  const net = showAvailable ? available : total;
  const accountsLoading = useAccountsLoading();

  const fmt = (m: Money) => (hidden ? "••••••" : format(m, "en-US"));

  // Hide the global "Add transaction" FAB while rearranging (see globals.css).
  useEffect(() => {
    document.body.dataset.dashEdit = editing ? "true" : "false";
    return () => { delete document.body.dataset.dashEdit; };
  }, [editing]);

  // Only show tiles the user enabled; premium tiles need a paid plan.
  const visibleTiles = enabled.filter((id) => isPaid || !tileMeta(id).premium);
  const sizeOf = (id: TileId): TileSize => sizes[id] ?? defaultSize(id);

  // While the local DB is still returning results, show placeholders rather
  // than the misleading "create your first account" screen.
  if (balances.length === 0 && accountsLoading) {
    return (
      <div style={{ display: "grid", gap: 24 }}>
        <HeroSkeleton height={110} />
        <CardsSkeleton count={4} />
      </div>
    );
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
              Reorder with the ▲▼ arrows (or drag on desktop) · handles resize
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

      {/* Net worth hero — rich green-gradient tile with trend sparkline */}
      <NetWorthHero net={net} base={base} fmt={fmt} showAvailable={showAvailable} onToggle={() => setShowAvailable((v) => !v)} />

      {/* Accounts — compact colored chips inside one card; manage the rest via View all */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 14 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
          <h2 style={{ margin: 0 }}>Accounts</h2>
          <Link href="/accounts" className="chip" style={{ fontSize: 13 }}>View all{balances.length > 8 ? ` (${balances.length})` : ""}</Link>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(min(112px, 100%), 1fr))", gap: 8 }}>
          {balances.slice(0, 8).map(({ account, balance }) => {
            const color = account.color || colorForId(account.id);
            return (
              <Link key={account.id} href={`/accounts/${account.id}/edit`} style={{ background: color, color: "#fff", borderRadius: 12, padding: "9px 11px", display: "grid", gap: 1, minWidth: 0, boxShadow: "0 6px 16px -12px rgba(43,39,35,0.6)" }}>
                <span style={{ fontSize: 10, opacity: 0.85, textTransform: "capitalize", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{account.type.replace("_", " ")}</span>
                <span style={{ fontSize: 12, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{account.name}</span>
                <span style={{ fontSize: 14.5, fontWeight: 750, textShadow: "0 1px 2px rgba(0,0,0,0.22)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{fmt(balance)}</span>
              </Link>
            );
          })}
        </div>
      </section>

      {/* Customizable tiles — long-press to edit, drag to reorder, tap corner to resize */}
      {visibleTiles.length > 0 ? (
        <DraggableGrid ids={visibleTiles} editing={editing} onLongPress={() => setEditing(true)} sizeOf={sizeOf} />
      ) : (
        <section className="card" style={{ padding: 24, textAlign: "center", display: "grid", gap: 8 }}>
          <p className="muted">No tiles shown. Add some to your dashboard.</p>
          <button className="btn" style={{ justifySelf: "center", gap: 6 }} onClick={() => setShowAdd(true)}><PlusIcon size={16} /> Add a widget</button>
        </section>
      )}

      <AddWidgetModal open={showAdd} onClose={() => setShowAdd(false)} enabled={enabled} isPaid={isPaid} />

      {/* Floating edit toolbar — stays visible while rearranging (header scrolls away). */}
      {editing && (
        <div style={{ position: "fixed", left: "50%", bottom: "calc(20px + env(safe-area-inset-bottom, 0px))", transform: "translateX(-50%)", zIndex: 70, display: "flex", gap: 8, padding: 6, borderRadius: 999, background: "var(--surface)", border: "1px solid var(--border)", boxShadow: "var(--shadow-lg)" }}>
          <button className="btn ghost" onClick={() => setShowAdd(true)} style={{ gap: 6 }}><PlusIcon size={16} /> Widget</button>
          <button className="btn" onClick={() => setEditing(false)} style={{ gap: 7, background: "var(--positive)", boxShadow: "0 12px 28px -10px rgba(95,102,71,0.9)" }}><CheckIcon /> Done</button>
        </div>
      )}
    </div>
  );
}

/** Decorative area sparkline for the net-worth hero (light line on dark card). */
function Sparkline({ values }: { values: number[] }) {
  if (values.length < 2) return null;
  const w = 300, h = 64, pad = 3;
  const min = Math.min(...values), max = Math.max(...values), range = max - min || 1;
  const pts = values.map((v, i) => [(i / (values.length - 1)) * w, h - pad - ((v - min) / range) * (h - pad * 2)] as const);
  const line = pts.map((p, i) => `${i ? "L" : "M"}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(" ");
  const area = `${line} L ${w} ${h} L 0 ${h} Z`;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" width="100%" height="64" style={{ marginTop: 16, display: "block" }}>
      <defs>
        <linearGradient id="nwFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c6cdb3" stopOpacity="0.5" />
          <stop offset="1" stopColor="#c6cdb3" stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill="url(#nwFill)" />
      <path d={line} fill="none" stroke="#eaf0da" strokeWidth="2.2" vectorEffect="non-scaling-stroke" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** Net-worth hero — deep-green gradient card with a delta pill and trend sparkline. */
function NetWorthHero({ net, base, fmt, showAvailable, onToggle }: {
  net: Money; base: string; fmt: (m: Money) => string; showAvailable: boolean; onToggle: () => void;
}) {
  const { data: rows = [] } = useQuery<{ ym: string; type: string; total: number }>(
    "SELECT strftime('%Y-%m', occurred_at) as ym, type, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense') GROUP BY ym, type ORDER BY ym",
  );
  const byMonth = new Map<string, { inc: number; exp: number }>();
  for (const r of rows) {
    const o = byMonth.get(r.ym) ?? { inc: 0, exp: 0 };
    if (r.type === "income") o.inc = r.total; else o.exp = r.total;
    byMonth.set(r.ym, o);
  }
  const months = [...byMonth.values()].slice(-8);
  const deltaMinor = months.length ? months[months.length - 1]!.inc - months[months.length - 1]!.exp : 0;
  let acc = 0;
  const spark = months.map((o) => (acc += (o.inc - o.exp) / 100));
  const up = deltaMinor >= 0;

  return (
    <section style={{ position: "relative", overflow: "hidden", borderRadius: 24, padding: "26px 28px", color: "#f1ede3", background: "linear-gradient(150deg, #5f6647 0%, #3e4a38 100%)", boxShadow: "0 20px 44px -22px rgba(62,74,56,0.7)", minWidth: 0, maxWidth: "100%", boxSizing: "border-box" }}>
      <button onClick={onToggle} className="press" style={{ position: "absolute", top: 18, right: 18, zIndex: 2, border: "none", cursor: "pointer", background: "rgba(255,255,255,0.14)", color: "#eaf0da", fontSize: 12, fontWeight: 600, padding: "5px 12px", borderRadius: 999 }}>
        {showAvailable ? "Excluding blocked" : "Including blocked"}
      </button>
      <div style={{ fontSize: 12, fontWeight: 600, letterSpacing: "0.06em", textTransform: "uppercase", color: "#c6cdb3" }}>
        {showAvailable ? "Available net worth" : "Net worth"}
      </div>
      <div style={{ fontSize: "clamp(30px, 9vw, 46px)", fontWeight: 750, letterSpacing: "-0.01em", marginTop: 6, overflowWrap: "anywhere" }}>{fmt(net)}</div>
      {months.length > 0 && (
        <div style={{ display: "inline-flex", alignItems: "center", gap: 6, marginTop: 10, padding: "4px 11px", borderRadius: 999, background: "rgba(255,255,255,0.14)", fontSize: 12.5, fontWeight: 600, color: up ? "#dde7c9" : "#f0d8c9" }}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={up ? "#dde7c9" : "#f0d8c9"} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d={up ? "M5 15l7-7 7 7" : "M5 9l7 7 7-7"} /></svg>
          {up ? "+" : "−"}{fmt(money(Math.abs(deltaMinor), base))} this month
        </div>
      )}
      <Sparkline values={spark} />
      <div style={{ fontSize: 12.5, color: "#c6cdb3", marginTop: 8 }}>Base currency {base}</div>
    </section>
  );
}

/**
 * Dashboard tiles with an edit mode that mirrors the design:
 *  - Long-press any tile to enter edit mode (or the Customize button). No permanent
 *    drag handle; a quick swipe still scrolls the page (both normal and edit mode).
 *  - Dragging lifts the tile so it follows the finger while a dashed terracotta
 *    snap zone shows exactly where it will land; other tiles reflow live.
 *  - A corner handle cycles the tile between half- and full-width (persisted).
 *  - A remove handle takes the tile off the dashboard.
 */
function DraggableGrid({ ids, editing, onLongPress, sizeOf }: {
  ids: TileId[]; editing: boolean; onLongPress: () => void; sizeOf: (id: TileId) => TileSize;
}) {
  const router = useRouter();
  const [order, setOrder] = useState<TileId[]>(ids);
  const [dragging, setDragging] = useState<TileId | null>(null);
  const [pointer, setPointer] = useState<{ x: number; y: number }>({ x: 0, y: 0 });
  const grab = useRef<{ ox: number; oy: number }>({ ox: 0, oy: 0 });
  const size = useRef<{ w: number; h: number }>({ w: 0, h: 0 });
  const refs = useRef<Map<TileId, HTMLElement>>(new Map());
  const hold = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const start = useRef<{ x: number; y: number } | null>(null);
  // Touch (coarse pointer) devices reorder with the ▲▼ buttons instead of drag,
  // which is unreliable on mobile (text selection, no scroll, bad placeholder).
  const [coarse, setCoarse] = useState(false);
  useEffect(() => { setCoarse(typeof matchMedia !== "undefined" && matchMedia("(pointer: coarse)").matches); }, []);
  useEffect(() => { if (!dragging) setOrder(ids); }, [ids.join(","), dragging]);

  const clearHold = () => { if (hold.current) { clearTimeout(hold.current); hold.current = undefined; } };

  function moveBy(id: TileId, dir: -1 | 1) {
    setOrder((prev) => {
      const i = prev.indexOf(id), j = i + dir;
      if (i < 0 || j < 0 || j >= prev.length) return prev;
      const next = [...prev];
      const [m] = next.splice(i, 1);
      next.splice(j, 0, m!);
      reorderTiles(next);
      return next;
    });
  }

  function pickUp(id: TileId, el: HTMLElement, pid: number, x: number, y: number) {
    const r = el.getBoundingClientRect();
    grab.current = { ox: x - r.left, oy: y - r.top };
    size.current = { w: r.width, h: r.height };
    try { el.setPointerCapture(pid); } catch { /* capture may fail if released */ }
    setPointer({ x, y });
    setDragging(id);
  }

  function reorderAt(x: number, y: number) {
    let target: TileId | null = null;
    for (const [tid, el] of refs.current) {
      const r = el.getBoundingClientRect();
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) { target = tid; break; }
    }
    if (!target || target === dragging) return;
    setOrder((prev) => {
      const from = prev.indexOf(dragging!), to = prev.indexOf(target!);
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
    const pid = e.pointerId, x = e.clientX, y = e.clientY;
    if (coarse) {
      // No drag on touch. Long-press only enters edit mode; reorder via ▲▼.
      // Null the ref when it fires so a released long-press isn't read as a tap.
      if (!editing) hold.current = setTimeout(() => { hold.current = undefined; onLongPress(); }, 500);
      return;
    }
    // Mouse: require a brief hold before picking up, so a quick click/scroll
    // isn't hijacked. Longer when not yet editing.
    const delay = editing ? 150 : 400;
    hold.current = setTimeout(() => { hold.current = undefined; if (!editing) onLongPress(); pickUp(id, el, pid, x, y); }, delay);
  }
  function pmove(e: React.PointerEvent) {
    if (dragging) {
      e.preventDefault();
      setPointer({ x: e.clientX, y: e.clientY });
      reorderAt(e.clientX, e.clientY);
      return;
    }
    if (hold.current && start.current && (Math.abs(e.clientX - start.current.x) > 8 || Math.abs(e.clientY - start.current.y) > 8)) {
      clearHold(); // moved before the hold fired — it's a scroll, let it through
    }
  }
  function up(e?: React.PointerEvent, id?: TileId) {
    // A tap = released before the press-hold timer fired and we never dragged.
    const wasTap = !!hold.current && !dragging;
    clearHold();
    if (dragging) { reorderTiles(order); setDragging(null); return; }
    // No tap should go to waste: navigate to the tile's detail view (some
    // deep-link to a section via #hash). Skip if a tap landed on an inner
    // control (its own link/button handles it) or while editing the layout.
    if (wasTap && !editing && e && id) {
      const t = e.target as HTMLElement;
      if (t.closest("a, button, select, input, textarea, label")) return;
      const href = TILE_HREF[id];
      if (href) router.push(href);
    }
  }

  return (
    <>
      <div className="dash-grid">
        {order.map((id) => {
          const sz = sizeOf(id);
          const isDrag = dragging === id;
          return (
            <div
              key={id}
              className="dash-tile"
              ref={(el) => { if (el) refs.current.set(id, el); else refs.current.delete(id); }}
              onPointerDown={(e) => down(e, id)}
              onPointerMove={pmove}
              onPointerUp={(e) => up(e, id)}
              onPointerCancel={() => up()}
              style={{
                gridColumn: `span ${W_COLS[sz.w]}`,
                gridRow: `span ${H_ROWS[sz.h]}`,
                position: "relative",
                touchAction: isDrag ? "none" : "auto",
                cursor: editing ? (isDrag ? "grabbing" : "grab") : "pointer",
              }}
            >
              {isDrag ? (
                // Dashed snap zone showing where the lifted tile will land.
                <div style={{ height: "100%", borderRadius: 24, border: "2px dashed var(--accent)", background: "var(--accent-ghost)" }} />
              ) : (
                <>
                  {editing && (
                    <div style={{ position: "absolute", top: 10, left: 10, zIndex: 6, display: "flex", gap: 6 }} onPointerDown={(e) => e.stopPropagation()}>
                      <button
                        aria-label="Cycle width" title={`Width: ${sz.w}`}
                        onClick={() => setTileSize(id, { ...sz, w: nextDim(sz.w) })}
                        style={sizeBtn}
                      ><WidthIcon /></button>
                      <button
                        aria-label="Cycle height" title={`Height: ${sz.h}`}
                        onClick={() => setTileSize(id, { ...sz, h: nextDim(sz.h) })}
                        style={sizeBtn}
                      ><HeightIcon /></button>
                    </div>
                  )}
                  {editing && (
                    <div style={{ position: "absolute", top: 10, right: 10, zIndex: 6, display: "flex", gap: 6 }} onPointerDown={(e) => e.stopPropagation()}>
                      <button aria-label="Move earlier" title="Move up" onClick={() => moveBy(id, -1)} style={moveBtn}>
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M18 15l-6-6-6 6" /></svg>
                      </button>
                      <button aria-label="Move later" title="Move down" onClick={() => moveBy(id, 1)} style={moveBtn}>
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M6 9l6 6 6-6" /></svg>
                      </button>
                      <button aria-label="Remove tile" title="Remove" onClick={() => setTileEnabled(id, false)}
                        style={{ width: 28, height: 28, borderRadius: 999, background: "var(--negative)", border: "2px solid var(--surface)", display: "grid", placeItems: "center", cursor: "pointer", boxShadow: "0 6px 14px -6px rgba(43,39,35,0.5)" }}>
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round"><path d="M5 12h14" /></svg>
                      </button>
                    </div>
                  )}
                  {/* Freeze interactions inside the tile while editing so drags don't trigger links. */}
                  <div className="dash-tile-body" style={{ pointerEvents: editing ? "none" : "auto" }}>
                    <TileView id={id} />
                  </div>
                </>
              )}
            </div>
          );
        })}
      </div>

      {/* Lifted tile follows the pointer. */}
      {dragging && (
        <div className="dash-tile-body" style={{ position: "fixed", left: pointer.x - grab.current.ox, top: pointer.y - grab.current.oy, width: size.current.w, height: size.current.h, zIndex: 1000, pointerEvents: "none", transform: "scale(1.03)", filter: "drop-shadow(0 24px 44px rgba(43,39,35,0.34))", opacity: 0.97 }}>
          <TileView id={dragging} />
        </div>
      )}
    </>
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
