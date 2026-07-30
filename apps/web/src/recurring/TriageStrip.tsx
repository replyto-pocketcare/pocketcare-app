"use client";

/**
 * One-time triage for recurring items that predate groups.
 *
 * NOT an "Ungrouped" bucket — that was explicitly rejected. This is a prompt to
 * fix, styled like the "Due now" strip, that disappears permanently once every
 * item has a group. Each row pre-selects a suggested group where the name gives
 * one away, so the common case is a single confirm.
 */

import { useState } from "react";
import { useTranslation } from "react-i18next";
import { MaterialIcon } from "../ui/MaterialIcon";
import type { RecurringItem } from "../cashflow/recurring";
import { assignGroup, suggestGroup, type RecurringGroup } from "./groups";

export function TriageStrip({ items, groupsFor }: {
  /** Items with no group, across all three directions. */
  items: RecurringItem[];
  groupsFor: (it: RecurringItem) => RecurringGroup[];
}) {
  const { t } = useTranslation("recurring");
  const [picked, setPicked] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);

  if (items.length === 0) return null;

  const chosenFor = (it: RecurringItem): string => {
    const explicit = picked[it.templateId];
    if (explicit) return explicit;
    const options = groupsFor(it);
    return suggestGroup(it.name, options)?.id ?? options[0]?.id ?? "";
  };

  async function assignAll() {
    setBusy(true);
    try {
      for (const it of items) {
        const gid = chosenFor(it);
        if (gid) await assignGroup(it.templateId, gid);
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <section
      className="card"
      style={{ padding: 16, display: "grid", gap: 12, borderColor: "var(--accent-soft)", background: "var(--accent-ghost)" }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <MaterialIcon name="folder" size={18} />
        <strong style={{ fontSize: 14 }}>{t("triageTitle", { count: items.length })}</strong>
      </div>
      <p className="muted" style={{ margin: 0, fontSize: 13 }}>{t("triageBody")}</p>

      <div className="row-stack">
        {items.map((it) => {
          const options = groupsFor(it);
          return (
            <div key={it.templateId} className="row-tile" style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, flexWrap: "wrap" }}>
              <span style={{ fontWeight: 600, minWidth: 0, flex: "1 1 140px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{it.name}</span>
              <select
                className="input"
                style={{ flex: "0 1 200px", minWidth: 0 }}
                value={chosenFor(it)}
                onChange={(e) => setPicked((p) => ({ ...p, [it.templateId]: e.target.value }))}
              >
                {options.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
              </select>
            </div>
          );
        })}
      </div>

      <div style={{ display: "flex", justifyContent: "flex-end" }}>
        <button className="btn" disabled={busy} onClick={() => void assignAll()}>
          {busy ? t("triageSaving") : t("triageCta", { count: items.length })}
        </button>
      </div>
    </section>
  );
}
