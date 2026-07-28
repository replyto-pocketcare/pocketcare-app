"use client";

import { useEffect } from "react";
import { useTranslation } from "react-i18next";
import Link from "next/link";
import { useEntitlement } from "../../src/entitlement";
import { LockIcon } from "../../src/ui/icons";
import { InsightFeed } from "../../src/ui/feed/InsightFeed";

/**
 * Insights is the card feed and nothing else — no page title, no side panels.
 * The dividend and projection panels that used to live here are now generated
 * as insight cards (see src/insights/generators.ts); their interactive controls
 * moved to /investments, where the holdings they describe already are.
 */
export default function InsightsPage() {
  const { t } = useTranslation("insights");
  const { isPaid } = useEntitlement();

  // Drop the shell's padding/width cap so the feed is genuinely full-bleed.
  // Only for the paid feed — the upgrade prompt below is normal page content.
  useEffect(() => {
    if (!isPaid) return;
    document.body.dataset.fullbleed = "true";
    return () => { delete document.body.dataset.fullbleed; };
  }, [isPaid]);

  if (!isPaid) {
    return (
      <div className="fade-up" style={{ display: "grid", gap: 16, maxWidth: 560 }}>
        <h1>{t("title")}</h1>
        <div className="card" style={{ position: "relative", padding: 28, display: "grid", gap: 12, textAlign: "center", overflow: "hidden" }}>
          <div aria-hidden style={{ position: "absolute", inset: 0, filter: "blur(7px)", opacity: 0.5, pointerEvents: "none",
            background: "radial-gradient(60% 40% at 30% 25%, var(--accent) 0, transparent 60%), radial-gradient(50% 40% at 75% 70%, var(--positive) 0, transparent 60%)" }} />
          <div style={{ position: "relative", display: "grid", gap: 12 }}>
            <div style={{ display: "flex", justifyContent: "center", color: "var(--text-2)" }}><LockIcon size={30} /></div>
            <h2>{t("feedTitle")}</h2>
            <p className="muted">{t("feedBody")}</p>
            <Link href="/settings" className="btn" style={{ justifySelf: "center" }}>{t("goPremium")}</Link>
          </div>
        </div>
      </div>
    );
  }

  return <InsightFeed />;
}
