"use client";

import { fromMajor } from "@pocketcare/money";
import { getDb, getRepositories } from "../powersync";
import { insertRow } from "../write";
import { getBaseCurrency } from "../prefs";
import type { CanonRow } from "./adapters";

export interface ImportResult { created: number; skipped: number; failed: number; errors: string[] }

function toIso(s: string): string {
  if (!s) return new Date().toISOString();
  const d = new Date(s);
  if (!Number.isNaN(d.getTime())) return d.toISOString();
  // Try DD/MM/YYYY [HH:mm]
  const m = s.match(/^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{2,4})(?:[ T](\d{1,2}):(\d{2}))?/);
  if (m) {
    const [, dd, mm, yy, hh = "0", mi = "0"] = m;
    const yr = yy!.length === 2 ? 2000 + Number(yy) : Number(yy);
    const dt = new Date(yr, Number(mm) - 1, Number(dd), Number(hh), Number(mi));
    if (!Number.isNaN(dt.getTime())) return dt.toISOString();
  }
  return new Date().toISOString();
}

const kindForType = (t: string): "income" | "expense" => (t === "income" ? "income" : "expense");

/** Best-effort account type from its name (users can change it afterward). */
function guessAccountType(name: string): string {
  const n = name.toLowerCase();
  if (/stock|equit|\bshares?\b/.test(n)) return "stocks";
  if (/mutual|\bmf\b|\bsip\b/.test(n)) return "mutual_funds";
  if (/credit|\bcard\b/.test(n)) return "credit_card";
  if (/cash|wallet/.test(n)) return "cash";
  if (/current|checking/.test(n)) return "current";
  return "savings";
}

/**
 * Import canonical rows: find-or-create accounts, categories and labels, then
 * create transactions through the repository (ledger + labels junction).
 */
export async function importTransactions(
  rows: CanonRow[],
  opts: { skipDuplicates: boolean } = { skipDuplicates: true },
): Promise<ImportResult> {
  const db = getDb();
  if (!db) return { created: 0, skipped: 0, failed: rows.length, errors: ["Database not ready"] };
  const repos = getRepositories();
  const base = getBaseCurrency();

  const accountCache = new Map<string, string>();
  const categoryCache = new Map<string, string>();

  const methodRows = await db.getAll<{ id: string; label: string }>("SELECT id, label FROM payment_methods");
  const methodByLabel = new Map(methodRows.map((m) => [m.label.toLowerCase(), m.id]));

  async function ensureAccount(name: string, currency: string): Promise<string> {
    const key = name.trim().toLowerCase();
    const hit = accountCache.get(key);
    if (hit) return hit;
    const found = await db!.getOptional<{ id: string }>(
      "SELECT id FROM accounts WHERE deleted_at IS NULL AND lower(name) = ? LIMIT 1",
      [key],
    );
    const id = found?.id ?? await insertRow("accounts", {
      name: name.trim(), type: guessAccountType(name), currency: currency || base,
      icon: null, color: null, is_archived: 0, include_in_net_worth: 1,
    });
    accountCache.set(key, id);
    return id;
  }

  async function ensureCategory(name: string, kind: "income" | "expense"): Promise<string> {
    const key = `${kind}:${name.trim().toLowerCase()}`;
    const hit = categoryCache.get(key);
    if (hit) return hit;
    const found = await db!.getOptional<{ id: string }>(
      "SELECT id FROM categories WHERE deleted_at IS NULL AND kind = ? AND lower(name) = ? LIMIT 1",
      [kind, name.trim().toLowerCase()],
    );
    const id = found?.id ?? await insertRow("categories", {
      name: name.trim(), kind, is_system: 0, parent_id: null, icon: null, color: null,
    });
    categoryCache.set(key, id);
    return id;
  }

  const res: ImportResult = { created: 0, skipped: 0, failed: 0, errors: [] };

  for (const row of rows) {
    try {
      const currency = row.currency || base;
      const occurredAt = toIso(row.date);
      const amountMinor = fromMajor(row.amount, currency).amount;
      const fromId = await ensureAccount(row.account, currency);

      if (opts.skipDuplicates) {
        const dup = await db.getOptional<{ id: string }>(
          "SELECT id FROM transactions WHERE deleted_at IS NULL AND account_id = ? AND amount = ? AND type = ? AND occurred_at = ? LIMIT 1",
          [fromId, amountMinor, row.type, occurredAt],
        );
        if (dup) { res.skipped++; continue; }
      }

      let toId: string | null = null;
      if (row.type === "transfer") {
        if (!row.toAccount) { res.failed++; res.errors.push(`Transfer without destination: ${row.account} ${row.amount}`); continue; }
        toId = await ensureAccount(row.toAccount, currency);
      }
      const catId = row.category && (row.type === "income" || row.type === "expense")
        ? await ensureCategory(row.category, kindForType(row.type))
        : null;
      const methodId = row.paymentMethod ? methodByLabel.get(row.paymentMethod.toLowerCase()) ?? null : null;

      await repos.transactions.create({
        account_id: fromId,
        type: row.type,
        amount: fromMajor(row.amount, currency),
        category_id: catId,
        labels: row.labels ?? [],
        note: row.note ?? null,
        description: row.description ?? null,
        payment_method: methodId,
        occurred_at: occurredAt,
        to_account_id: toId,
        to_amount: row.type === "transfer" && row.toAmount != null ? fromMajor(row.toAmount, currency) : null,
      });
      res.created++;
    } catch (e) {
      res.failed++;
      if (res.errors.length < 8) res.errors.push((e as Error).message);
    }
  }
  return res;
}
