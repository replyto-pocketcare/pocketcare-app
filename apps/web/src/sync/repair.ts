"use client";

/**
 * Layer 0 — find and re-upload rows that never reached the server.
 *
 * WHY THIS EXISTS: `insertRow` writes the row to local SQLite; PowerSync
 * separately records an upload instruction in `ps_crud`. Deleting a queued op
 * (which the earlier "Discard" button did) removes the INSTRUCTION, not the
 * row. So a user who cleared a stuck queue still has their data on the device
 * — with nothing scheduled to send it. To them it looks lost.
 *
 * This finds those rows by diffing local ids against the server, shows them in
 * terms a person recognises (amount, date, description), lets them export, and
 * re-uploads them in foreign-key-safe order.
 *
 * DESIGN NOTES
 * - Re-upload goes DIRECT via supabase, not by tricking PowerSync into
 *   re-queueing. We know the full row and we control the ordering; a no-op
 *   UPDATE would produce a PATCH that matches zero server rows and silently
 *   does nothing.
 * - Parents before children, always. The whole class of bug we're fixing comes
 *   from children arriving without their parents.
 * - Export is offered BEFORE any repair. Nothing here should ever be the last
 *   copy of someone's data.
 */
import { getSupabase, getDb, getUserId } from "../powersync";
import { logEvent } from "../diagnostics/log";

/**
 * Tables to check, in dependency order. Parents first — this order is also the
 * order rows are re-uploaded in, so it must stay topologically sound.
 */
const REPAIR_ORDER: readonly string[] = [
  "accounts",
  "categories",
  "labels",
  "budgets",
  "goals",
  "transactions",
  "transaction_items",
  "transaction_labels",
  "split_groups",
  "split_group_members",
  "expenses",
  "expense_participants",
  "expense_items",
  "expense_item_shares",
  "settlements",
  "expense_postings",
  "goal_allocations",
  "loans",
  "subscriptions",
  "recurring_commitments",
  "holdings",
  "receipt_scans",
];

/** How a row is described to the user. Recognition matters more than precision. */
const DESCRIBERS: Record<string, (r: Record<string, unknown>) => string> = {
  transactions: (r) => `${r.description || "Transaction"} · ${money(r.amount, r.currency)} · ${date(r.occurred_at)}`,
  expenses: (r) => `${r.description || "Shared expense"} · ${money(r.amount, r.currency)} · ${date(r.occurred_at)}`,
  accounts: (r) => `Account “${r.name}”`,
  split_groups: (r) => `Group “${r.name}”`,
  budgets: (r) => `Budget “${r.name}”`,
  goals: (r) => `Goal “${r.name}”`,
  settlements: (r) => `Settlement · ${money(r.amount, r.currency)}`,
  categories: (r) => `Category “${r.name}”`,
  labels: (r) => `Label “${r.name}”`,
};

/**
 * Render a row the way its owner would recognise it.
 *
 * Shared with the dead-letter screen: whether a row is stranded or quarantined,
 * the user is answering the same question — "which of my things is this?"
 */
export function describeRow(table: string, row: Record<string, unknown>): string {
  const d = DESCRIBERS[table];
  return d ? d(row) : `${table.replace(/_/g, " ")} entry`;
}

const money = (amount: unknown, currency: unknown): string => {
  const n = Number(amount);
  if (!Number.isFinite(n)) return "—";
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency: String(currency || "INR") })
      .format(n / 100);
  } catch {
    return `${currency ?? ""} ${(n / 100).toFixed(2)}`;
  }
};

const date = (iso: unknown): string => {
  const d = new Date(String(iso));
  return Number.isNaN(d.getTime()) ? "" : d.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "2-digit" });
};

export interface StrandedRow {
  readonly table: string;
  readonly id: string;
  readonly label: string;
  readonly row: Record<string, unknown>;
}

export interface RepairScan {
  readonly stranded: StrandedRow[];
  /** Tables we couldn't check (offline, permission) — reported, never assumed clean. */
  readonly unchecked: string[];
}

/** PostgREST `in.(...)` has a URL length limit; chunk the id lists. */
const CHUNK = 100;

/**
 * Diff local rows against the server.
 *
 * Requires a connection: "is this row on the server" is not answerable offline,
 * and guessing would either hide real loss or invent phantom loss.
 */
export async function scanForStranded(limitPerTable = 500): Promise<RepairScan> {
  const db = getDb();
  const supabase = getSupabase();
  if (!db) return { stranded: [], unchecked: [...REPAIR_ORDER] };

  const stranded: StrandedRow[] = [];
  const unchecked: string[] = [];

  for (const table of REPAIR_ORDER) {
    let local: Record<string, unknown>[] = [];
    try {
      local = await db.getAll<Record<string, unknown>>(
        `SELECT * FROM ${table} WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT ?`,
        [limitPerTable],
      );
    } catch {
      // Table not in this build's schema — skip quietly.
      continue;
    }
    if (local.length === 0) continue;

    const ids = local.map((r) => String(r.id));
    const present = new Set<string>();
    let failed = false;

    for (let i = 0; i < ids.length; i += CHUNK) {
      const chunk = ids.slice(i, i + CHUNK);
      const { data, error } = await supabase
        .schema("pocketcare")
        .from(table)
        .select("id")
        .in("id", chunk);
      if (error) { failed = true; break; }
      for (const row of data ?? []) present.add(String((row as { id: string }).id));
    }

    if (failed) {
      unchecked.push(table);
      continue;
    }

    const describe = DESCRIBERS[table] ?? (() => `${table} row`);
    for (const r of local) {
      const id = String(r.id);
      if (!present.has(id)) {
        stranded.push({ table, id, label: describe(r), row: r });
      }
    }
  }

  if (stranded.length > 0) {
    logEvent("warn", "repair", `found ${stranded.length} row(s) never uploaded`, {
      tables: [...new Set(stranded.map((s) => s.table))],
      count: stranded.length,
    });
  }
  return { stranded, unchecked };
}

export interface RepairResult {
  readonly uploaded: number;
  readonly failed: { table: string; id: string; label: string; error: string }[];
}

/**
 * Re-upload stranded rows, parents first.
 *
 * Uses upsert so a partially-succeeded repair can be run again safely — a
 * repair tool that can only be run once is a trap.
 */
export async function repairStranded(rows: readonly StrandedRow[]): Promise<RepairResult> {
  const supabase = getSupabase();
  const failed: RepairResult["failed"] = [];
  let uploaded = 0;

  for (const table of REPAIR_ORDER) {
    const forTable = rows.filter((r) => r.table === table);
    if (forTable.length === 0) continue;

    // One row at a time: a batch that fails tells us nothing about WHICH row
    // was bad, and identifying the bad row is the whole point.
    for (const item of forTable) {
      const { error } = await supabase
        .schema("pocketcare")
        .from(table)
        .upsert(item.row, { onConflict: "id" });
      if (error) {
        failed.push({ table, id: item.id, label: item.label, error: error.message });
      } else {
        uploaded++;
      }
    }
  }

  logEvent(failed.length > 0 ? "warn" : "info", "repair",
    `re-uploaded ${uploaded} row(s), ${failed.length} still failing`,
    { uploaded, failed: failed.length, tables: [...new Set(failed.map((f) => f.table))] });

  return { uploaded, failed };
}

/**
 * Everything stranded, as JSON. Offered before any repair or discard.
 *
 * Unredacted on purpose: this is the user's own data being handed back to
 * them, not a support log. It never leaves the device unless they send it.
 */
export function exportStranded(rows: readonly StrandedRow[]): string {
  return JSON.stringify(
    {
      exportedAt: new Date().toISOString(),
      user: safeUserId(),
      note: "Rows present on this device that were never uploaded to the server.",
      rows: rows.map((r) => ({ table: r.table, id: r.id, label: r.label, data: r.row })),
    },
    null,
    2,
  );
}

function safeUserId(): string {
  try {
    return getUserId();
  } catch {
    return "unknown";
  }
}

/** Trigger a file download of the export. */
export function downloadExport(json: string): void {
  const blob = new Blob([json], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `sanvya-unsynced-${new Date().toISOString().slice(0, 10)}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
