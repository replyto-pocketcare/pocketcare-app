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
      statusChanged: (s: unknown) => setInfo(read(s as LooseStatus)),
    });
    return () => { try { dispose?.(); } catch { /* noop */ } };
  }, []);
  return info;
}
