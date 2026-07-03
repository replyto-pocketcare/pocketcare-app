"use client";

import { parseRecords } from "./csv";

/** Canonical transaction shape all importers produce and the exporter emits. */
export interface CanonRow {
  date: string;          // ISO date/datetime for occurred_at
  type: "income" | "expense" | "transfer" | "opening_balance" | "adjustment";
  amount: number;        // major units, positive
  currency: string;
  account: string;       // from-account name
  toAccount?: string;    // transfer destination name
  toAmount?: number;     // major units
  category?: string;
  labels?: string[];
  paymentMethod?: string; // display label, e.g. "UPI"
  note?: string;
  description?: string;
}

export interface ImportAdapter {
  id: string;
  label: string;
  beta?: boolean;
  /** Optional delimiter hint (defaults to auto-detect). */
  delimiter?: string;
  /** Map header-keyed records to canonical rows. Skip unparseable rows. */
  parse(records: Record<string, string>[]): CanonRow[];
}

const num = (v?: string): number => {
  if (!v) return 0;
  // Tolerate thousands separators and currency symbols; keep sign + decimal.
  const cleaned = v.replace(/[^0-9.,\-]/g, "").replace(/,(?=\d{3}\b)/g, "");
  const norm = cleaned.includes(",") && !cleaned.includes(".") ? cleaned.replace(",", ".") : cleaned.replace(/,/g, "");
  const n = Number.parseFloat(norm);
  return Number.isFinite(n) ? n : 0;
};

const splitLabels = (v?: string): string[] =>
  (v ?? "").split(/[|,]/).map((s) => s.trim()).filter(Boolean);

const toType = (t: string, amount: number): CanonRow["type"] => {
  const s = t.toLowerCase();
  if (s.includes("transfer")) return "transfer";
  if (s.includes("income") || s.includes("deposit") || s.includes("credit")) return "income";
  if (s.includes("opening")) return "opening_balance";
  if (s.includes("adjust")) return "adjustment";
  if (s.includes("expens") || s.includes("debit") || s.includes("withdraw")) return "expense";
  // Fall back to sign.
  return amount < 0 ? "expense" : "income";
};

// ---- PocketCare's own round-trippable format ----
const pocketcare: ImportAdapter = {
  id: "pocketcare",
  label: "PocketCare (CSV export)",
  parse(records) {
    return records.map((r) => {
      const amount = Math.abs(num(r["amount"]));
      const type = (r["type"] || "").toLowerCase() as CanonRow["type"];
      return {
        date: r["date"] || new Date().toISOString(),
        type: (["income", "expense", "transfer", "opening_balance", "adjustment"].includes(type) ? type : toType(r["type"] || "", num(r["amount"]))) as CanonRow["type"],
        amount,
        currency: (r["currency"] || "").toUpperCase(),
        account: r["account"] || "",
        toAccount: r["to account"] || r["to_account"] || undefined,
        toAmount: r["to amount"] || r["to_amount"] ? Math.abs(num(r["to amount"] || r["to_amount"])) : undefined,
        category: r["category"] || undefined,
        labels: splitLabels(r["labels"]),
        paymentMethod: r["payment method"] || r["payment_method"] || undefined,
        note: r["note"] || undefined,
        description: r["description"] || undefined,
      };
    }).filter((r) => r.account && r.amount > 0) as CanonRow[];
  },
};

// ---- Wallet by BudgetBakers (best-effort; verify against a real export) ----
const wallet: ImportAdapter = {
  id: "wallet",
  label: "Wallet by BudgetBakers (beta)",
  parse(records) {
    return records.map((r) => {
      const rawAmount = num(r["amount"]);
      const amount = Math.abs(rawAmount);
      const type = toType(r["type"] || "", rawAmount);
      return {
        date: r["date"] || new Date().toISOString(),
        type,
        amount,
        currency: (r["currency"] || "").toUpperCase(),
        account: r["account"] || "",
        category: r["category"] || undefined,
        labels: splitLabels(r["labels"] || r["label"]),
        paymentMethod: r["payment type"] || r["payment_type"] || undefined,
        note: r["note"] || r["description"] || r["payee"] || undefined,
      };
    }).filter((r) => r.account && r.amount > 0) as CanonRow[];
  },
};

export const IMPORT_ADAPTERS: ImportAdapter[] = [pocketcare, wallet];

export function parseWithAdapter(adapterId: string, text: string): CanonRow[] {
  const adapter = IMPORT_ADAPTERS.find((a) => a.id === adapterId) ?? pocketcare;
  return adapter.parse(parseRecords(text, adapter.delimiter));
}

/** Column order for PocketCare's own export (matches the pocketcare adapter). */
export const EXPORT_HEADERS = [
  "Date", "Type", "Amount", "Currency", "Account", "To Account", "To Amount",
  "Category", "Labels", "Payment Method", "Note", "Description",
];
