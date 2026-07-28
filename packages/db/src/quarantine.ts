/**
 * Dead-letter queue for uploads the server will never accept.
 *
 * THE PROBLEM THIS SOLVES: PowerSync uploads `ps_crud` strictly in order and
 * retries forever. That is correct for a network blip and catastrophic for a
 * rejected write — an op that can never succeed blocks every write queued
 * behind it, indefinitely. A user in that state sees "syncing…" while nothing
 * they do is saved, and the only previous escape was a Discard button that
 * deleted the op outright. That cost a real user real data.
 *
 * So: after a few attempts, a failure classified permanent is **moved**, not
 * deleted. The full payload goes to the local-only `failed_writes` table, the
 * op leaves `ps_crud`, and the queue drains. Nothing is destroyed without the
 * user seeing it first (see the "Problems syncing" screen).
 *
 * Local-only on purpose: a synced quarantine table would put its own rows into
 * the queue it exists to unblock.
 */
import type { AbstractPowerSyncDatabase, CrudEntry } from "@powersync/common";
import { classifyFailure, shouldQuarantine, type Classification } from "@pocketcare/sync-policy";

/**
 * Stable identity for one logical write, used as the retry-counter key.
 *
 * Keyed on table + op + row id rather than the `ps_crud` row id, so the count
 * survives PowerSync re-deriving the queue and, more importantly, a page
 * reload — an in-memory counter would reset and the op would retry forever,
 * which is the exact failure being fixed.
 */
export function opKey(table: string, op: string, rowId: string): string {
  return `${table}|${op}|${rowId}`;
}

/** Read the attempt count for an op. Missing row means this is attempt 1. */
export async function bumpAttempts(
  db: AbstractPowerSyncDatabase,
  key: string,
  code: string | undefined,
): Promise<number> {
  try {
    const existing = await db.getOptional<{ attempts: number }>(
      "SELECT attempts FROM sync_attempts WHERE id = ?",
      [key],
    );
    const attempts = (existing?.attempts ?? 0) + 1;
    const now = new Date().toISOString();
    // NOT `ON CONFLICT`: PowerSync exposes every table as a VIEW backed by
    // INSTEAD OF triggers, and SQLite cannot UPSERT into a view. The read
    // above already told us which branch we need.
    if (existing) {
      await db.execute(
        "UPDATE sync_attempts SET attempts = ?, last_code = ?, updated_at = ? WHERE id = ?",
        [attempts, code ?? null, now, key],
      );
    } else {
      await db.execute(
        "INSERT INTO sync_attempts (id, attempts, last_code, updated_at) VALUES (?, ?, ?, ?)",
        [key, attempts, code ?? null, now],
      );
    }
    return attempts;
  } catch {
    // If the counter table is unavailable (older local schema), report attempt 1
    // so nothing is ever quarantined on the strength of a broken counter.
    return 1;
  }
}

export async function clearAttempts(db: AbstractPowerSyncDatabase, key: string): Promise<void> {
  try {
    await db.execute("DELETE FROM sync_attempts WHERE id = ?", [key]);
  } catch {
    /* best effort */
  }
}

export interface QuarantineOutcome {
  readonly quarantined: number;
  readonly classification: Classification;
}

/**
 * Move a run of failed ops out of the upload queue and into `failed_writes`.
 *
 * ORDER MATTERS: the payload is written first and the queue entry deleted
 * second. If the process dies between the two, the op is still queued and will
 * simply be quarantined again — the insert is an upsert keyed on the ps_crud
 * id, so a repeat is harmless. The reverse order would lose the write.
 */
export async function quarantineOps(
  db: AbstractPowerSyncDatabase,
  ops: readonly CrudEntry[],
  failure: { code?: string | undefined; message?: string | undefined; status?: number | undefined },
  classification: Classification,
  attempts: number,
): Promise<number> {
  const now = new Date().toISOString();
  const ids: number[] = [];

  for (const op of ops) {
    // `clientId` is the ps_crud row id — stable, and what we delete by.
    const crudId = Number((op as unknown as { clientId?: number }).clientId ?? NaN);
    const rowKey = Number.isFinite(crudId) ? String(crudId) : `${op.table}:${op.id}`;
    // Delete-then-insert rather than `ON CONFLICT`: PowerSync exposes tables as
    // VIEWs backed by INSTEAD OF triggers, and SQLite cannot UPSERT a view.
    // Re-quarantining the same op should replace it, not duplicate it.
    await db.execute("DELETE FROM failed_writes WHERE id = ?", [rowKey]);
    await db.execute(
      `INSERT INTO failed_writes
         (id, table_name, op, row_id, payload, code, message, cls, reason, attempts, failed_at, resolved_at, resolution)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)`,
      [
        rowKey,
        op.table,
        String(op.op),
        op.id,
        JSON.stringify(op.opData ?? {}),
        failure.code ?? null,
        failure.message ?? null,
        classification.cls,
        classification.reason,
        attempts,
        now,
      ],
    );
    if (Number.isFinite(crudId)) ids.push(crudId);
  }

  if (ids.length > 0) {
    await db.execute(
      `DELETE FROM ps_crud WHERE id IN (${ids.map(() => "?").join(",")})`,
      ids,
    );
  }
  return ops.length;
}

/**
 * Decide what to do about a failed run, and do it.
 *
 * Returns true when the run was quarantined and the caller should carry on with
 * the rest of the batch; false when it should rethrow so PowerSync retries.
 */
export async function handleUploadFailure(
  db: AbstractPowerSyncDatabase,
  run: readonly CrudEntry[],
  error: unknown,
  /** Told which key gained a counter, so the caller can clear it on success. */
  onBump?: (key: string) => void,
): Promise<{ quarantined: boolean; classification: Classification; attempts: number }> {
  const e = error as { code?: string; message?: string; status?: number };
  const classification = classifyFailure({ code: e.code, message: e.message, status: e.status });

  const head = run[0]!;
  const key = opKey(head.table, String(head.op), head.id);
  onBump?.(key);
  const attempts = await bumpAttempts(db, key, e.code);

  if (!shouldQuarantine(classification, attempts)) {
    return { quarantined: false, classification, attempts };
  }

  try {
    await quarantineOps(db, run, e, classification, attempts);
    await clearAttempts(db, key);
    return { quarantined: true, classification, attempts };
  } catch {
    // If quarantining itself fails, retrying is strictly safer than pretending
    // we handled it — the alternative is dropping the write on the floor.
    return { quarantined: false, classification, attempts };
  }
}
