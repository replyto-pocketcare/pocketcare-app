"use client";

/**
 * Create a group or trip. Extracted from the old `/groups` page when Splits and
 * Groups & trips were merged into one screen — it keeps using the `groups`
 * i18n namespace so none of its copy had to be duplicated.
 */

import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useBaseCurrency } from "../hooks";
import { Modal } from "../ui/Modal";
import { useConnections } from "./hooks";
import { createGroup } from "./write";

export function NewGroupModal({ open, onClose }: { open: boolean; onClose: (createdId?: string) => void }) {
  const { t } = useTranslation("groups");
  const base = useBaseCurrency();
  const connections = useConnections();

  const [name, setName] = useState("");
  const [kind, setKind] = useState<"group" | "trip">("trip");
  const [members, setMembers] = useState<string[]>([]);
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [auto, setAuto] = useState(false);
  const [busy, setBusy] = useState(false);
  const canAuto = !!start && !!end;

  function reset() {
    setName(""); setMembers([]); setStart(""); setEnd(""); setKind("trip"); setAuto(false);
  }

  async function create() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      const id = await createGroup({
        name, kind, currency: base,
        startDate: start || null, endDate: end || null,
        autoSplit: canAuto && auto, memberUserIds: members,
      });
      reset();
      onClose(id);
    } finally { setBusy(false); }
  }

  return (
    <Modal open={open} onClose={() => onClose()}>
      <div style={{ display: "grid", gap: 12 }}>
        <h2 style={{ margin: 0 }}>{t("newGroupTrip")}</h2>
        <div style={{ display: "flex", gap: 6 }}>
          {(["trip", "group"] as const).map((k) => (
            <button key={k} type="button" className="chip" data-active={k === kind} onClick={() => setKind(k)}>{t(`kind.${k}`)}</button>
          ))}
        </div>
        <input
          className="input"
          placeholder={kind === "trip" ? t("tripNamePlaceholder") : t("groupNamePlaceholder")}
          value={name}
          onChange={(e) => setName(e.target.value)}
        />

        {connections.length > 0 && (
          <>
            <span className="muted" style={{ fontSize: 12 }}>{t("addExistingFriends")}</span>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
              {connections.map((c) => {
                const on = members.includes(c.id);
                return (
                  <button
                    key={c.id}
                    type="button"
                    className="chip"
                    data-active={on}
                    onClick={() => setMembers((m) => (on ? m.filter((x) => x !== c.id) : [...m, c.id]))}
                  >
                    {c.name}
                  </button>
                );
              })}
            </div>
          </>
        )}

        <span className="muted" style={{ fontSize: 12 }}>{t("datesOptional")}</span>
        <div style={{ display: "flex", gap: 8 }}>
          <input className="input" type="date" value={start} onChange={(e) => { setStart(e.target.value); if (end && e.target.value > end) setEnd(e.target.value); }} />
          <input className="input" type="date" min={start || undefined} value={end} onChange={(e) => setEnd(e.target.value)} />
        </div>
        <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 14, opacity: canAuto ? 1 : 0.5 }}>
          <input type="checkbox" checked={canAuto && auto} disabled={!canAuto} onChange={(e) => setAuto(e.target.checked)} />
          {t("autoSplitCreate", { kind: t(`kind.${kind}`) })}
        </label>

        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
          <button className="btn ghost" onClick={() => onClose()}>{t("cancel")}</button>
          <button className="btn" onClick={() => void create()} disabled={busy || !name.trim()}>
            {busy ? t("creating") : t("create")}
          </button>
        </div>
      </div>
    </Modal>
  );
}
