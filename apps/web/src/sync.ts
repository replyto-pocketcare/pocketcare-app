"use client";

import { useEffect, useState } from "react";
import { getDb } from "./powersync";

/** Live PowerSync connection + data-flow status, surfaced to the UI. */
export interface SyncInfo {
  connected: boolean;
  hasSynced: boolean;
  lastSyncedAt: Date | null;
  uploading: boolean;
  downloading: boolean;
  /** True network state (navigator.onLine) — the source of truth for "offline". */
  online: boolean;
  /** Human-readable upload/download error, if any (e.g. a PostgREST schema error). */
  error: string | null;
}

const isOnline = () => (typeof navigator === "undefined" ? true : navigator.onLine !== false);

const EMPTY: SyncInfo = {
  connected: false, hasSynced: false, lastSyncedAt: null,
  uploading: false, downloading: false, online: true, error: null,
};

// PowerSync's SyncStatus is loosely typed across versions; read defensively.
type LooseStatus = {
  connected?: boolean;
  hasSynced?: boolean;
  lastSyncedAt?: Date | null;
  dataFlowStatus?: { uploading?: boolean; downloading?: boolean; uploadError?: unknown; downloadError?: unknown };
};

function read(s: LooseStatus | undefined | null): SyncInfo {
  const flow = s?.dataFlowStatus;
  const errObj = (flow?.uploadError ?? flow?.downloadError) as { message?: string } | undefined;
  return {
    connected: Boolean(s?.connected),
    hasSynced: Boolean(s?.hasSynced),
    lastSyncedAt: s?.lastSyncedAt ?? null,
    uploading: Boolean(flow?.uploading),
    downloading: Boolean(flow?.downloading),
    online: isOnline(),
    error: errObj ? (errObj.message ?? String(errObj)) : null,
  };
}

export function useSyncStatus(): SyncInfo {
  const [info, setInfo] = useState<SyncInfo>(EMPTY);
  useEffect(() => {
    const db = getDb();
    const refresh = (s?: LooseStatus) => {
      const next = read(s ?? (db?.currentStatus as LooseStatus));
      // Keep the raw error in the console for debugging; the UI shows a friendly
      // message (see syncMessage) instead of the technical text.
      if (next.error) console.warn("[PocketCare sync]", next.error);
      setInfo(next);
    };
    refresh();
    // Track the real network state so the UI never claims "offline" while online.
    const onNet = () => refresh();
    window.addEventListener("online", onNet);
    window.addEventListener("offline", onNet);
    const dispose = db?.registerListener({ statusChanged: (s: unknown) => refresh(s as LooseStatus) });
    return () => {
      window.removeEventListener("online", onNet);
      window.removeEventListener("offline", onNet);
      try { dispose?.(); } catch { /* noop */ }
    };
  }, []);
  return info;
}

/**
 * True while the app is online but the FIRST sync from the server hasn't
 * finished — i.e. the local DB may still be empty because data is downloading.
 * Pages use this to show skeletons instead of a misleading "no data" / "add your
 * first…" empty state during the initial sync. Offline → not pending (nothing to
 * wait for; show whatever's local).
 */
export function useInitialSyncPending(): boolean {
  const info = useSyncStatus();
  return info.online && !info.hasSynced;
}

export interface SyncMessage {
  text: string; 
  tone: "info" | "warn";
  action?: "force-sync";
}

/**
 * User-facing sync state: a short, non-technical message (or null when fine).
 * - Truly offline → calm "you're offline" note.
 * - Online but a transient network/websocket blip → nothing (it auto-reconnects).
 * - Online with a real (non-network) error → a "we're on it" warning.
 * Raw errors never reach the UI.
 */
export function syncMessage(info: SyncInfo): SyncMessage | null {
  if (!info.online) {
    return { text: "You’re offline. Your changes are saved on this device and will sync automatically when you’re back online.", tone: "info" };
  }
  if (!info.error) return null;
  const networky = /websocket|network|failed to fetch|load failed|connection|timeout|offline|ECONN|ETIMEDOUT/i.test(info.error);
  if (networky) return null; // online + transient connection issue → PowerSync retries; don't alarm
  
  return { 
    text: "We’re having trouble syncing right now. Your data is safe on this device.", 
    tone: "warn",
    action: "force-sync"
  };
}
