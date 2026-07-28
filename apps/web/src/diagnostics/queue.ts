"use client";

/**
 * Inspecting and repairing the pending-upload queue, from inside the app.
 *
 * WHY: a stuck queue is the single most common cause of "syncing isn't
 * working", and until now the only way to see it was a browser console — which
 * is exactly what you don't have on a phone. The whole point of the diagnostics
 * work is that a support conversation shouldn't require devtools.
 *
 * THE FAILURE MODE THIS TARGETS: PowerSync uploads the queue in order and
 * retries forever on failure. If a queued row references a parent row that
 * never reached the server, its INSERT can never succeed — foreign key or RLS,
 * either way it's permanent — and **everything queued behind it is blocked**.
 * One orphaned row silently freezes all of a user's writes.
 */
import { getDb } from "../powersync";
import { logEvent } from "./log";

/** Parent lookups for the tables that can strand a child row. */
const FOREIGN_KEYS: Record<string, { column: string; parentTable: string }> = {
  split_group_members: { column: "group_id", parentTable: "split_groups" },
  expenses: { column: "group_id", parentTable: "split_groups" },
  expense_participants: { column: "expense_id", parentTable: "expenses" },
  expense_items: { column: "expense_id", parentTable: "expenses" },
  expense_item_shares: { column: "item_id", parentTable: "expense_items" },
  settlements: { column: "group_id", parentTable: "split_groups" },
  transaction_items: { column: "transaction_id", parentTable: "transactions" },
  transaction_labels: { column: "transaction_id", parentTable: "transactions" },
};

export interface QueuedOp {
  /** ps_crud row id — what we delete to discard the op. */
  readonly id: number;
  readonly table: string;
  readonly op: string;
  readonly rowId: string;
  /** True when this op references a parent row that doesn't exist locally. */
  readonly orphaned: boolean;
  readonly reason?: string | undefined;
}

interface PsCrudRow {
  id: number;
  data: string;
}

/**
 * Read the pending queue and flag orphans.
 *
 * Reads `ps_crud` directly — PowerSync's own `getCrudBatch()` caps at a batch
 * size and gives no row ids to delete, so it can't drive a repair UI.
 */
export async function inspectQueue(limit = 200): Promise<QueuedOp[]> {
  const db = getDb();
  if (!db) return [];

  let rows: PsCrudRow[] = [];
  try {
    rows = await db.getAll<PsCrudRow>("SELECT id, data FROM ps_crud ORDER BY id LIMIT ?", [limit]);
  } catch {
    // Older/newer PowerSync builds may name this differently; degrade to empty
    // rather than breaking the panel.
    return [];
  }

  const out: QueuedOp[] = [];
  for (const r of rows) {
    let parsed: { type?: string; op?: string; id?: string; data?: Record<string, unknown> };
    try {
      parsed = JSON.parse(r.data);
    } catch {
      continue;
    }
    const table = String(parsed.type ?? "");
    const op = String(parsed.op ?? "");
    const rowId = String(parsed.id ?? "");

    let orphaned = false;
    let reason: string | undefined;

    const fk = FOREIGN_KEYS[table];
    // Only PUT/INSERT can be orphaned — a delete of a missing parent is fine.
    if (fk && op.toUpperCase() === "PUT") {
      const parentId = parsed.data?.[fk.column];
      if (typeof parentId === "string" && parentId) {
        try {
          const parent = await db.getOptional<{ id: string }>(
            `SELECT id FROM ${fk.parentTable} WHERE id = ?`,
            [parentId],
          );
          if (!parent) {
            orphaned = true;
            reason = `${fk.parentTable} row is missing`;
          }
        } catch {
          /* table not in schema — can't judge, leave it alone */
        }
      }
    }

    out.push({ id: r.id, table, op, rowId, orphaned, ...(reason ? { reason } : {}) });
  }
  return out;
}

/**
 * Delete specific queued ops.
 *
 * Destructive and deliberately narrow: the UI only ever offers this for ops it
 * has PROVEN are orphaned. Discarding a good op silently loses a user's data,
 * so there is no "clear everything" button.
 */
export async function discardOps(ids: readonly number[]): Promise<number> {
  const db = getDb();
  if (!db || ids.length === 0) return 0;
  const placeholders = ids.map(() => "?").join(",");
  await db.execute(`DELETE FROM ps_crud WHERE id IN (${placeholders})`, ids as number[]);
  logEvent("info", "sync", `discarded ${ids.length} stuck change(s) from the upload queue`);
  return ids.length;
}

/** Compact summary for the shared log and for auto-reports. */
export function summarizeQueue(ops: readonly QueuedOp[]): string {
  if (ops.length === 0) return "empty";
  const byTable = new Map<string, number>();
  for (const o of ops) byTable.set(o.table, (byTable.get(o.table) ?? 0) + 1);
  const orphans = ops.filter((o) => o.orphaned);
  const parts = [...byTable.entries()].map(([t, n]) => `${t}×${n}`).join(", ");
  return orphans.length > 0
    ? `${ops.length} pending (${parts}) — ${orphans.length} STUCK: ${[...new Set(orphans.map((o) => `${o.table} (${o.reason})`))].join("; ")}`
    : `${ops.length} pending (${parts})`;
}
