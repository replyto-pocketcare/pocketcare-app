/**
 * SupabaseConnector — bridges PowerSync to Supabase.
 * - fetchCredentials: gives PowerSync the current Supabase JWT (guest or registered).
 * - uploadData: flushes the local write queue to Postgres, preserving order.
 *
 * Financial-safety note: writes are applied in queue order and retried on
 * failure; because the ledger is append-only and server-authoritative, replays
 * are safe (no in-place money mutation).
 */
import type {
  AbstractPowerSyncDatabase,
  PowerSyncBackendConnector,
  PowerSyncCredentials,
  CrudEntry,
} from "@powersync/common";
import { UpdateType } from "@powersync/common";
import type { SupabaseClient } from "@supabase/supabase-js";
import { handleUploadFailure, clearAttempts, opKey } from "./quarantine.ts";

/** Postgres schema that holds all PocketCare tables (see 0001_init.sql). */
export const DB_SCHEMA = "pocketcare";

/**
 * Optional sink for structured sync failures.
 *
 * A plain module-level hook rather than a constructor option, so `packages/db`
 * stays free of any dependency on the app's diagnostics layer — the app opts in
 * by calling `setSyncDiagnosticSink` at startup, and this file neither knows nor
 * cares whether anything is listening.
 */
export type SyncDiagnostic = {
  table: string;
  op: string;
  rows: number;
  code?: string | undefined;
  message?: string | undefined;
  hint?: string | undefined;
  /** How the retry policy judged it, and whether it was dead-lettered. */
  cls?: string | undefined;
  attempts?: number | undefined;
  quarantined?: boolean | undefined;
};

let diagnosticSink: ((d: SyncDiagnostic) => void) | null = null;

export function setSyncDiagnosticSink(fn: ((d: SyncDiagnostic) => void) | null): void {
  diagnosticSink = fn;
}

/**
 * FAULT INJECTION — dev only.
 *
 * Every bug in this area has been one that reasoning missed and only running
 * the code would have caught: a deferred constraint that could never hold, a
 * getSnapshot that looped React, a stuck-op detector that could never fire.
 * Those paths are unreachable in normal use — you cannot casually produce an
 * RLS denial on demand — so they went untested.
 *
 * This makes them reachable: force uploads to a chosen table to fail with a
 * chosen SQLSTATE, and exercise the whole classify → retry → quarantine →
 * recover path deliberately.
 */
export interface FaultInjection {
  /** Unqualified table name, or "*" for everything. */
  table: string;
  /** SQLSTATE to report, e.g. "42501" (RLS) or "23503" (foreign key). */
  code: string;
  message?: string | undefined;
  status?: number | undefined;
}

let fault: FaultInjection | null = null;

/** Install (or clear) a fault. No-op in production builds — see the app's gate. */
export function setFaultInjection(f: FaultInjection | null): void {
  fault = f;
}

export function getFaultInjection(): FaultInjection | null {
  return fault;
}

function injectedErrorFor(table: string): { code: string; message: string; status?: number } | null {
  if (!fault) return null;
  const bare = table.includes(".") ? table.slice(table.lastIndexOf(".") + 1) : table;
  if (fault.table !== "*" && fault.table !== bare) return null;
  return {
    code: fault.code,
    message: fault.message ?? `injected fault (${fault.code}) for ${bare}`,
    ...(fault.status !== undefined ? { status: fault.status } : {}),
  };
}

/**
 * Keys we've recorded a failure for this session.
 *
 * Success clears the persisted retry counter, but doing a DELETE after every
 * successful run would add a write per op to bulk imports for no reason. Only
 * ops we know have failed can have a counter, so only those are cleared.
 */
const bumped = new Set<string>();

async function clearAttemptsFor(
  database: AbstractPowerSyncDatabase,
  run: readonly CrudEntry[],
): Promise<void> {
  for (const o of run) {
    const key = opKey(o.table, String(o.op), o.id);
    if (!bumped.delete(key)) continue;
    await clearAttempts(database, key);
  }
}

function reportSyncDiagnostic(d: SyncDiagnostic): void {
  try {
    diagnosticSink?.(d);
  } catch {
    // Diagnostics must never make a sync failure worse than it already is.
  }
}

export class SupabaseConnector implements PowerSyncBackendConnector {
  constructor(
    private readonly client: SupabaseClient,
    private readonly powerSyncUrl: string,
    /** Schema the tables live in; must be an Exposed schema in Supabase API settings. */
    private readonly schema: string = DB_SCHEMA,
  ) {}

  async fetchCredentials(): Promise<PowerSyncCredentials | null> {
    const { data, error } = await this.client.auth.getSession();
    if (error || !data.session) return null;
    return {
      endpoint: this.powerSyncUrl,
      token: data.session.access_token,
    };
  }

  async uploadData(database: AbstractPowerSyncDatabase): Promise<void> {
    const batch = await database.getCrudBatch();
    if (!batch) return;

    // Coalesce *consecutive* ops that share the same table + op type into a
    // single PostgREST request (array upsert / `id IN (...)` delete). This turns
    // a bulk import of N transactions — previously N HTTP round-trips — into a
    // handful of requests, while preserving the queue's ordering (we never
    // reorder across tables, so foreign-key ordering like account-before-txn is
    // untouched). PATCH stays per-row because two updates to the same table can
    // touch different columns and must not be merged into one payload.
    const ops = batch.crud as CrudEntry[];
    let i = 0;
    while (i < ops.length) {
      const op = ops[i]!;
      const rel = this.client.schema(this.schema).from(op.table);

      // Extend the run while the next op targets the same table + op type.
      let j = i + 1;
      while (
        j < ops.length &&
        ops[j]!.table === op.table &&
        ops[j]!.op === op.op &&
        op.op !== UpdateType.PATCH
      ) {
        j++;
      }
      const run = ops.slice(i, j);

      // Fault injection short-circuits the request entirely, so a forced
      // failure costs nothing and can't accidentally write.
      let error: unknown = injectedErrorFor(`${this.schema}.${op.table}`);
      if (!error) switch (op.op) {
        case UpdateType.PUT: {
          const rows = run.map((o) => ({ id: o.id, ...o.opData }));
          ({ error } = await rel.upsert(rows));
          break;
        }
        case UpdateType.DELETE: {
          const ids = run.map((o) => o.id);
          ({ error } = await rel.delete().in("id", ids));
          break;
        }
        case UpdateType.PATCH: {
          ({ error } = await rel.update(op.opData ?? {}).eq("id", op.id));
          break;
        }
      }

      if (error) {
        // Classify before reacting. A transient failure must keep retrying
        // forever; a permanent one must NOT, because retrying it forever is
        // what freezes every write queued behind it.
        const verdict = await handleUploadFailure(database, run, error, (k) => bumped.add(k));

        // Surface the real cause (e.g. a PostgREST "schema must be exposed"
        // error, or an RLS violation) instead of failing silently.
        console.error(
          `[PocketCare sync] upload failed for ${this.schema}.${op.table} (${op.op}, ${run.length} row(s), attempt ${verdict.attempts}, ${verdict.classification.cls})${verdict.quarantined ? " — moved to Problems syncing" : ""}:`,
          error,
        );
        // Also emit it structurally. The console line is captured as free text
        // by the diagnostics log, where the number-scrubber can't tell a
        // PostgREST code from an amount and redacts it — but the code is the
        // most diagnostic field there is, so pass it as its own key.
        reportSyncDiagnostic({
          table: `${this.schema}.${op.table}`,
          op: String(op.op),
          rows: run.length,
          code: (error as { code?: string }).code,
          message: (error as { message?: string }).message,
          hint: (error as { hint?: string }).hint,
          cls: verdict.classification.cls,
          attempts: verdict.attempts,
          quarantined: verdict.quarantined,
        });

        // Quarantined: the op is out of ps_crud and preserved in full, so the
        // queue can move on to everything that was stuck behind it.
        if (verdict.quarantined) {
          i = j;
          continue;
        }
        throw error;
      }

      // Succeeded — drop any retry counter so a later, unrelated failure on the
      // same row starts from zero rather than inheriting a stale count.
      await clearAttemptsFor(database, run);
      i = j;
    }

    await batch.complete();
  }
}
