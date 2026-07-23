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

/** Postgres schema that holds all PocketCare tables (see 0001_init.sql). */
export const DB_SCHEMA = "pocketcare";

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

      let error: unknown = null;
      switch (op.op) {
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
        // Surface the real cause (e.g. a PostgREST "schema must be exposed"
        // error, or an RLS violation) instead of failing silently. PowerSync
        // will retry, so we rethrow after logging.
        console.error(
          `[PocketCare sync] upload failed for ${this.schema}.${op.table} (${op.op}, ${run.length} row(s)):`,
          error,
        );
        throw error;
      }
      i = j;
    }

    await batch.complete();
  }
}
