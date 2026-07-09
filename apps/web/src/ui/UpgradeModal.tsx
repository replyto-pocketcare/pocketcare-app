"use client";

import Link from "next/link";
import { Modal } from "./Modal";
import { LockIcon } from "./icons";

/** Reusable "this needs Premium" dialog with a Go-Premium CTA. */
export function UpgradeModal({ open, onClose, title, message }: {
  open: boolean; onClose: () => void; title?: string; message: string;
}) {
  return (
    <Modal open={open} onClose={onClose}>
      <div style={{ display: "grid", gap: 12, textAlign: "center", justifyItems: "center" }}>
        <div style={{ color: "var(--text-2)" }}><LockIcon size={30} /></div>
        <h2 style={{ margin: 0 }}>{title ?? "A Premium feature"}</h2>
        <p className="muted" style={{ margin: 0, maxWidth: 360 }}>{message}</p>
        <div style={{ display: "flex", gap: 8, marginTop: 4 }}>
          <button className="btn ghost" onClick={onClose}>Not now</button>
          <Link href="/settings" className="btn" onClick={onClose}>Go Premium</Link>
        </div>
      </div>
    </Modal>
  );
}
