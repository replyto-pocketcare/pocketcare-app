"use client";

import { useTranslation } from "react-i18next";
import Link from "next/link";
import { useEntitlement } from "../../src/entitlement";
import { LockIcon } from "../../src/ui/icons";
import { InsightFeed } from "../../src/ui/feed/InsightFeed";
import { DividendPanel } from "../../src/market/DividendPanel";
import { ProjectionPanel } from "../../src/market/ProjectionPanel";

export default function InsightsPage() {
  const { t } = useTranslation("insights");
  const { isPaid } = useEntitlement();

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

  return (
    <div style={{ display: "grid", gap: 14 }}>
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>{t("title")}</h1>
        <Link href="/statements" className="muted" style={{ fontSize: 13 }}>{t("statements")}</Link>
      </div>
      <DividendPanel />
      <ProjectionPanel />
      <InsightFeed />
    </div>
  );
}
