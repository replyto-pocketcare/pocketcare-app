/**
 * Statement parsing/analysis domain types. Fully on-device: statements are
 * parsed in the browser and never sent anywhere. Amounts are integer MINOR
 * units; a transaction's `amount` is SIGNED — negative = debit/spend, positive
 * = credit/received. Dates are ISO `YYYY-MM-DD`.
 */

export type StatementKind = "bank" | "card";

export interface StatementTxn {
  date: string;          // YYYY-MM-DD
  description: string;
  amount: number;        // minor units, signed (− debit / + credit)
  balance?: number | null; // running balance (minor), if the statement has it
  category?: string | null; // filled by the on-device categorizer at review time
  ref?: string | null;   // cheque/UPI ref if present
}

export interface CardMeta {
  totalDue?: number | null;   // statement balance / total outstanding (minor)
  minDue?: number | null;     // minimum amount due (minor)
  dueDate?: string | null;    // YYYY-MM-DD
  thisMonthDue?: number | null; // amount due this cycle (minor)
}

export interface ParsedStatement {
  kind: StatementKind;
  label: string;                // detected bank/card name, else "Statement"
  currency: string;             // ISO code (default base)
  period: { from: string | null; to: string | null };
  openingBalance?: number | null;
  closingBalance?: number | null;
  txns: StatementTxn[];
  card?: CardMeta;
  /** What the parser is unsure about (e.g. a guessed column) — surfaced to the user. */
  warnings: string[];
  /** How the columns were mapped (for the review UI + manual override). */
  mapping?: ColumnMapping;
}

export interface ColumnMapping {
  date: string | null;
  description: string | null;
  debit: string | null;
  credit: string | null;
  amount: string | null;   // single signed-amount column (alternative to debit/credit)
  balance: string | null;
}
