"use client";

import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Modal } from "./Modal";
import { MaterialIcon } from "./MaterialIcon";
import { NAV_CATALOG, NAV_SLOTS, setBottomNavIds } from "../navPrefs";

/** Lets the user pick which 3 destinations sit in the floating bottom bar
 *  (Home and More are fixed). Opened from the "More" sheet's edit icon. */
export function BottomNavCustomizer({ open, onClose, current }: { open: boolean; onClose: () => void; current: string[] }) {
  const { t } = useTranslation();
  const [picked, setPicked] = useState<string[]>(current);

  const toggle = (id: string) => {
    setPicked((prev) => {
      if (prev.includes(id)) return prev.filter((x) => x !== id);
      if (prev.length >= NAV_SLOTS) return prev; // full — ignore extra taps rather than bump someone silently
      return [...prev, id];
    });
  };

  const save = () => {
    setBottomNavIds(picked);
    onClose();
  };

  return (
    <Modal open={open} onClose={onClose} label={t("nav.customize", "Customize bottom bar")}>
      <h2 style={{ margin: "0 0 4px", fontSize: 18 }}>{t("nav.customize", "Customize bottom bar")}</h2>
      <p className="muted" style={{ fontSize: 13, margin: "0 0 14px" }}>
        {t("nav.customizeHint", "Pick {{n}} to keep one tap away. Home and More always stay put.", { n: NAV_SLOTS })}
      </p>
      <div style={{ display: "grid", gap: 4, maxHeight: "50vh", overflowY: "auto" }}>
        {NAV_CATALOG.map((item) => {
          const active = picked.includes(item.id);
          const disabled = !active && picked.length >= NAV_SLOTS;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => toggle(item.id)}
              disabled={disabled}
              style={{
                display: "flex", alignItems: "center", gap: 10, padding: "10px 12px", borderRadius: 10,
                border: "none", textAlign: "left", cursor: disabled ? "default" : "pointer",
                background: active ? "var(--accent-ghost)" : "transparent",
                color: disabled ? "var(--text-3)" : "var(--text)", fontSize: 14.5, fontWeight: active ? 650 : 500,
                opacity: disabled ? 0.55 : 1,
              }}
            >
              <MaterialIcon name={item.icon} size={20} />
              {t(item.tkey, item.label)}
              <span style={{
                marginLeft: "auto", width: 20, height: 20, borderRadius: 999, display: "grid", placeItems: "center",
                border: `1.5px solid ${active ? "var(--accent)" : "var(--border-strong)"}`,
                background: active ? "var(--accent)" : "transparent",
              }}>
                {active && <MaterialIcon name="check" size={13} style={{ color: "#fff" }} />}
              </span>
            </button>
          );
        })}
      </div>
      <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 16 }}>
        <button className="btn ghost" onClick={onClose}>{t("common.cancel", "Cancel")}</button>
        <button className="btn" disabled={picked.length !== NAV_SLOTS} onClick={save}>{t("common.save", "Save")}</button>
      </div>
    </Modal>
  );
}
