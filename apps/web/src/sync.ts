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
  /** Human-readable upload/download error, if any (e.g. a PostgREST schema error). */
  error: string | null;
}

const EMPTY: SyncInfo = {
  connected: false, hasSynced: false, lastSyncedAt: null,
  uploading: false, downloading: false, error: null,
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
    error: errObj ? (errObj.message ?? String(errObj)) : null,
  };
}

export function useSyncStatus(): SyncInfo {
  const [info, setInfo] = useState<SyncInfo>(EMPTY);
  useEffect(() => {
    const db = getDb();
    if (!db) return;
    setInfo(read(db.currentStatus as LooseStatus));
    const dispose = db.registerListener({
      statusChanged: (s: unknown) => {
        const next = read(s as LooseStatus);
        // Keep the raw error in the console for debugging; the UI shows a
        // friendly message (see syncMessage) instead of the technical text.
        if (next.error) console.warn("[PocketCare sync]", next.error);
        setInfo(next);
      },
    });
    return () => { try { dispose?.(); } catch { /* noop */ } };
  }, []);
  return info;
}

export interface SyncMessage { text: string; tone: "info" | "warn" }

/**
 * User-facing sync state: a short, non-technical message (or null when fine).
 * Network/offline problems are expected and shown calmly; anything else is a
 * "we're on it" note. Raw errors never reach the UI.
 */
export function syncMessage(info: SyncInfo): SyncMessage | null {
  if (!info.error) return null;
  const offline = typeof navigator !== "undefined" && navigator.onLine === false;
  const networky = offline || /websocket|network|failed to fetch|load failed|connection|timeout|offline|ECONN|ETIMEDOUT/i.test(info.error);
  if (networky) {
    return { text: "You’re offline. Your changes are saved on this device and will sync automatically when you’re back online.", tone: "info" };
  }
  return { text: "We’re having trouble syncing right now — we’re on it. Your data is safe on this device.", tone: "warn" };
}
