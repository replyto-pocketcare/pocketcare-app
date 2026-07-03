"use client";

import { getDb } from "../powersync";
import { toCsv } from "./csv";
import { EXPORT_HEADERS } from "./adapters";

interface ExportRow {
  occurred_at: string; type: string; amount: number; currency: string;
  account: string | null; to_account: string | null; to_amount: number | null;
  category: string | null; labels: string | null; method: string | null;
  note: string | null; description: string | null;
}

/** All non-deleted transactions as a PocketCare-format CSV string. */
export async function exportTransactionsCsv(): Promise<{ csv: string; count: number }> {
  const db = getDb();
  if (!db) return { csv: "", count: 0 };
  const rows = await db.getAll<ExportRow>(
    `SELECT t.occurred_at, t.type, t.amount, t.currency,
       a.name  AS account,
       a2.name AS to_account, t.to_amount,
       c.name  AS category,
       (SELECT GROUP_CONCAT(l.name, '|') FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id WHERE tl.transaction_id = t.id) AS labels,
       (SELECT pm.label FROM payment_methods pm WHERE pm.id = t.payment_method) AS method,
       t.note, t.description
     FROM transactions t
     LEFT JOIN accounts   a  ON a.id  = t.account_id
     LEFT JOIN accounts   a2 ON a2.id = t.to_account_id
     LEFT JOIN categories c  ON c.id  = t.category_id
     WHERE t.deleted_at IS NULL
     ORDER BY t.occurred_at`,
  );

  const table: (string | number)[][] = [EXPORT_HEADERS];
  for (const r of rows) {
    table.push([
      r.occurred_at,
      r.type,
      (r.amount / 100).toFixed(2),
      r.currency,
      r.account ?? "",
      r.to_account ?? "",
      r.to_amount != null ? (r.to_amount / 100).toFixed(2) : "",
      r.category ?? "",
      r.labels ?? "",
      r.method ?? "",
      r.note ?? "",
      r.description ?? "",
    ]);
  }
  return { csv: toCsv(table), count: rows.length };
}
