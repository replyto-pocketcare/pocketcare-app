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

    for (const op of batch.crud as CrudEntry[]) {
      const table = this.client.schema(this.schema).from(op.table);
      let result;
      switch (op.op) {
        case UpdateType.PUT:
          result = await table.upsert({ id: op.id, ...op.opData });
          break;
        case UpdateType.PATCH:
          result = await table.update(op.opData ?? {}).eq("id", op.id);
          break;
        case UpdateType.DELETE:
          result = await table.delete().eq("id", op.id);
          break;
      }
      if (result?.error) throw result.error;
    }

    await batch.complete();
  }
}
