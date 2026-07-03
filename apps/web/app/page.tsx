"use client";

import { useState } from "react";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { format, type Money } from "@pocketcare/money";
import { useNetWorth, useAccountBalances, useTier } from "../src/hooks";
import { useAmountsHidden, setAmountsHidden } from "../src/prefs";
import { colorForId } from "../src/colors";
import { getDb } from "../src/powersync";
import { EyeIcon, EyeOffIcon, PlusIcon, SlidersIcon, LockIcon } from "../src/ui/icons";
import { Modal } from "../src/ui/Modal";
import { useDashboardTiles, setTileEnabled, type TileId } from "../src/dashboard";
import { TILE_CATALOG, TileView, tileMeta } from "../src/dashboard/tiles";

export default function Dashboard() {
  const { total, available, base } = useNetWorth();
  const balances = useAccountBalances();
  const hidden = useAmountsHidden();
  const tier = useTier();
  const enabled = useDashboardTiles();
  const [showAvailable, setShowAvailable] = useState(false);
  const [customizing, setCustomizing] = useState(false);
  const { t } = useTranslation();
  const net = showAvailable ? available : total;

  const fmt = (m: Money) => (hidden ? "••••••" : format(m, "en-US"));

  // Only show tiles the user enabled; premium tiles need the premium tier.
  const visibleTiles = enabled.filter((id) => tier === "premium" || !tileMeta(id).premium);

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
    <div style={{ display: "grid", gap: 24 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1>{t("pages.dashboard", "Dashboard")}</h1>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <button className="chip" onClick={() => setCustomizing(true)} title="Customize tiles" style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
            <SlidersIcon size={16} /> Customize
          </button>
          <button className="chip" onClick={() => setAmountsHidden(!hidden)} title={hidden ? "Show amounts" : "Hide amounts"} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
            {hidden ? <EyeIcon size={16} /> : <EyeOffIcon size={16} />} {hidden ? "Show" : "Hide"}
          </button>
          <Link href="/accounts/new" className="btn ghost" style={{ gap: 6 }}><PlusIcon size={16} /> Account</Link>
        </div>
      </div>

      {/* Net worth hero */}
      <section className="card" style={{ padding: 28, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <div>
          <div className="muted" style={{ fontSize: 13 }}>{showAvailable ? t("netWorth.available", "Available net worth") : t("netWorth.title", "Net worth")}</div>
          <div style={{ fontSize: 44, fontWeight: 750, letterSpacing: "-0.02em", color: "var(--forest)" }}>{fmt(net)}</div>
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
                <div style={{ padding: 16, display: "grid", gap: 3, flex: 1 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                    <span className="muted" style={{ fontSize: 12, textTransform: "capitalize" }}>{account.type.replace("_", " ")}</span>
                    <button onClick={() => toggleNw(account.id, included)} title={included ? "In net worth — click to exclude" : "Excluded — click to include"}
                      style={{ background: "transparent", border: "none", cursor: "pointer", color: "var(--text-2)", opacity: included ? 1 : 0.45, display: "inline-flex", padding: 0 }}>
                      {included ? <EyeIcon size={16} /> : <EyeOffIcon size={16} />}
                    </button>
                  </div>
                  <span style={{ fontWeight: 600 }}>{account.name}</span>
                  <span style={{ fontSize: 20, fontWeight: 700 }}>{fmt(balance)}</span>
                </div>
              </div>
            );
          })}
        </div>
      </section>

      {/* Customizable tiles */}
      {visibleTiles.length > 0 ? (
        <div className="dash-grid">
          {visibleTiles.map((id) => (
            <div key={id} style={{ gridColumn: tileMeta(id).span === "full" ? "1 / -1" : "auto" }}>
              <TileView id={id} />
            </div>
          ))}
        </div>
      ) : (
        <section className="card" style={{ padding: 24, textAlign: "center", display: "grid", gap: 8 }}>
          <p className="muted">No tiles shown. Add some to your dashboard.</p>
          <button className="btn" style={{ justifySelf: "center", gap: 6 }} onClick={() => setCustomizing(true)}><SlidersIcon size={16} /> Customize</button>
        </section>
      )}

      <CustomizeModal open={customizing} onClose={() => setCustomizing(false)} enabled={enabled} tier={tier} />
    </div>
  );
}

function CustomizeModal({ open, onClose, enabled, tier }: {
  open: boolean; onClose: () => void; enabled: TileId[]; tier: string;
}) {
  return (
    <Modal open={open} onClose={onClose}>
      <div style={{ display: "grid", gap: 4, marginBottom: 12 }}>
        <h2 style={{ margin: 0 }}>Customize dashboard</h2>
        <p className="muted" style={{ fontSize: 13 }}>Choose which tiles appear, and in what order they’re listed.</p>
      </div>
      <div style={{ display: "grid", gap: 6, maxHeight: "56vh", overflowY: "auto" }}>
        {TILE_CATALOG.map((t) => {
          const on = enabled.includes(t.id);
          const locked = !!t.premium && tier !== "premium";
          return (
            <label key={t.id} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: "10px 12px", borderRadius: 10, border: "1px solid var(--border)", background: "var(--surface-2)", cursor: locked ? "not-allowed" : "pointer", opacity: locked ? 0.6 : 1 }}>
              <span style={{ display: "inline-flex", alignItems: "center", gap: 8, fontSize: 14 }}>
                {t.title}
                {locked && <span className="muted" style={{ display: "inline-flex", alignItems: "center", gap: 4, fontSize: 12 }}><LockIcon size={13} /> Premium</span>}
                {t.premium && !locked && <span className="muted" style={{ fontSize: 12 }}>· Premium</span>}
              </span>
              <input type="checkbox" checked={on} disabled={locked} onChange={(e) => setTileEnabled(t.id, e.target.checked)} />
            </label>
          );
        })}
      </div>
      {tier !== "premium" && (
        <p className="muted" style={{ fontSize: 12, marginTop: 10 }}>
          Premium tiles unlock with a <Link href="/settings">Premium plan</Link>.
        </p>
      )}
      <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 14 }}>
        <button className="btn" onClick={onClose}>Done</button>
      </div>
    </Modal>
  );
}
