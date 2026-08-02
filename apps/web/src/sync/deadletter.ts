"use client";

/**
 * Layer 4 — reading and resolving the dead-letter queue.
 *
 * The connector quarantines writes the server refuses (see
 * `packages/db/src/quarantine.ts`). Quarantining alone would be a bad
 * half-measure: the queue unblocks, but the user's data sits in a table nobody
 * can see, which is data loss with extra steps. This is the half that makes it
 * visible and actionable.
 *
 * FOUR THINGS A USER CAN DO, and the reasoning behind each:
 *  - **Retry** — the cause may be gone (re-added to the group, parent row since
 *    uploaded). Cheap, safe, and the first thing to try.
 *  - **Export** — a JSON copy of their own data. Offered unprompted, and forced
 *    before Discard. Nothing here should ever be the last copy.
 *  - **Discard** — give up on this one write. Only ever after an export.
 *  - **Do nothing** — it stays listed. Never expires, never cleans itself up.
 */
import { getSupabase, getDb } from "../powersync";
import { explainForUser } from "@sanvya/sync-policy";
import { logEvent } from "../diagnostics/log";
import { describeRow, downloadExport } from "./repair";

export interface FailedWrite {
  readonly id: string;
  readonly table: string;
  readonly op: string;
  readonly rowId: string;
  readonly payload: Record<string, unknown>;
  readonly code: string | undefined;
  readonly message: string | undefined;
  readonly reason: string | undefined;
  readonly attempts: number;
  readonly failedAt: string;
  /** What the user is shown: which thing this is. */
  readonly label: string;
  /** What the user is shown: why it didn't save. */
  readonly explanation: string;
}

interface Row {
  id: string;
  table_name: string;
  op: string;
  row_id: string;
  payload: string;
  code: string | null;
  message: string | null;
  reason: string | null;
  attempts: number | null;
  failed_at: string;
}

/**
 * Unresolved quarantined writes, newest first.
 *
 * Merges the stored payload with the row still present in local SQLite: the
 * payload is what failed to upload, but the local row usually carries more
 * context (a description, a currency) that makes the label recognisable.
 */
export async function listFailedWrites(limit = 100): Promise<FailedWrite[]> {
  const db = getDb();
  if (!db) return [];

  let rows: Row[] = [];
  try {
    rows = await db.getAll<Row>(
      "SELECT * FROM failed_writes WHERE resolved_at IS NULL ORDER BY failed_at DESC LIMIT ?",
      [limit],
    );
  } catch {
    // Table absent on an older local schema — nothing quarantined, by definition.
    return [];
  }

  const out: FailedWrite[] = [];
  for (const r of rows) {
    let payload: Record<string, unknown> = {};
    try {
      payload = JSON.parse(r.payload) as Record<string, unknown>;
    } catch {
      /* keep going — a broken payload is still worth showing and exporting */
    }

    const local = await localRow(r.table_name, r.row_id);
    const merged = { ...payload, ...(local ?? {}), id: r.row_id };

    out.push({
      id: r.id,
      table: r.table_name,
      op: r.op,
      rowId: r.row_id,
      payload: merged,
      code: r.code ?? undefined,
      message: r.message ?? undefined,
      reason: r.reason ?? undefined,
      attempts: r.attempts ?? 0,
      failedAt: r.failed_at,
      label: describeRow(r.table_name, merged),
      explanation: explainForUser({ code: r.code ?? undefined, message: r.message ?? undefined }),
    });
  }
  return out;
}

async function localRow(table: string, id: string): Promise<Record<string, unknown> | null> {
  const db = getDb();
  if (!db) return null;
  try {
    return (await db.getOptional<Record<string, unknown>>(
      `SELECT * FROM ${table} WHERE id = ?`,
      [id],
    )) ?? null;
  } catch {
    return null;
  }
}

export interface RetryResult {
  readonly ok: boolean;
  readonly error?: string | undefined;
}

/**
 * Try the write again, directly.
 *
 * Direct rather than re-queued: we hold the complete row, so an upsert states
 * the intended end state plainly. Pushing it back into `ps_crud` would risk
 * re-blocking the queue with the very op we just freed it from.
 */
export async function retryFailedWrite(item: FailedWrite): Promise<RetryResult> {
  const supabase = getSupabase();
  const rel = supabase.schema("sanvya").from(item.table);

  const { error } =
    item.op.toUpperCase() === "DELETE"
      ? await rel.delete().eq("id", item.rowId)
      : await rel.upsert({ ...item.payload, id: item.rowId }, { onConflict: "id" });

  if (error) {
    logEvent("warn", "sync", `retry still failing for ${item.table}`, {
      table: item.table,
      code: error.code,
      message: error.message,
    });
    return { ok: false, error: error.message };
  }

  await resolve(item.id, "retried");
  logEvent("info", "sync", `retry succeeded for ${item.table}`, { table: item.table });
  return { ok: true };
}

/**
 * Give up on a write.
 *
 * Exports first, always — no argument, no opt-out. The previous Discard button
 * deleted queued ops with no copy and no record, and a user lost expenses they
 * could not identify or recover. That must not be possible again.
 */
export async function discardFailedWrite(item: FailedWrite): Promise<void> {
  downloadExport(exportFailedWrites([item]));
  await resolve(item.id, "discarded");
  logEvent("warn", "sync", `discarded a failed write to ${item.table} (exported first)`, {
    table: item.table,
    code: item.code,
  });
}

async function resolve(id: string, resolution: string): Promise<void> {
  const db = getDb();
  if (!db) return;
  // Kept, not deleted: the record of what happened is worth more than the row
  // it occupies, and it's how a support conversation reconstructs the story.
  await db.execute(
    "UPDATE failed_writes SET resolved_at = ?, resolution = ? WHERE id = ?",
    [new Date().toISOString(), resolution, id],
  );
}

/** Full, unredacted JSON — this is the user's own data being handed back. */
export function exportFailedWrites(items: readonly FailedWrite[]): string {
  return JSON.stringify(
    {
      exportedAt: new Date().toISOString(),
      note: "Changes made on this device that the server would not accept.",
      items: items.map((i) => ({
        table: i.table,
        operation: i.op,
        id: i.rowId,
        label: i.label,
        failedAt: i.failedAt,
        why: i.explanation,
        technical: { code: i.code, message: i.message, reason: i.reason, attempts: i.attempts },
        data: i.payload,
      })),
    },
    null,
    2,
  );
}
