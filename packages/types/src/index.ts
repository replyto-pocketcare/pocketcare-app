/**
 * @pocketcare/types — shared domain types & enums.
 * Uses const-object "enums" + union types (erasable syntax) so the code runs
 * under Node's TypeScript type-stripping and any bundler without transforms.
 */

// ----- Currency -----
/** ISO 4217 alphabetic code, e.g. "USD", "INR", "EUR". */
export type CurrencyCode = string;

// ----- Accounts -----
export const AccountType = {
  Savings: "savings",
  Current: "current",
  CreditCard: "credit_card",
  Cash: "cash",
  MutualFunds: "mutual_funds",
  Stocks: "stocks",
  Demat: "demat",
} as const;
export type AccountType = (typeof AccountType)[keyof typeof AccountType];

// ----- Transactions -----
export const TransactionType = {
  Income: "income",
  Expense: "expense",
  Transfer: "transfer",
  /** Sets/adjusts an account's starting balance without rewriting history. */
  OpeningBalance: "opening_balance",
  /** Compensating correction entry. */
  Adjustment: "adjustment",
} as const;
export type TransactionType = (typeof TransactionType)[keyof typeof TransactionType];

export const CategoryKind = {
  Income: "income",
  Expense: "expense",
} as const;
export type CategoryKind = (typeof CategoryKind)[keyof typeof CategoryKind];

// ----- Budgets -----
export const Period = {
  Daily: "daily",
  Weekly: "weekly",
  Monthly: "monthly",
  Yearly: "yearly",
} as const;
export type Period = (typeof Period)[keyof typeof Period];

export const BudgetScope = {
  Overall: "overall",
  Category: "category",
  Label: "label",
} as const;
export type BudgetScope = (typeof BudgetScope)[keyof typeof BudgetScope];

// ----- Recurring commitments -----
export const CommitmentKind = {
  Emi: "emi",
  Subscription: "subscription",
  RecurringExpense: "recurring_expense",
} as const;
export type CommitmentKind = (typeof CommitmentKind)[keyof typeof CommitmentKind];

// ----- Freemium -----
export const Tier = {
  Free: "free",
  Lite: "lite",
  Pro: "pro",
  /** Legacy alias kept for back-compat; treated as a paid tier. */
  Premium: "premium",
} as const;
export type Tier = (typeof Tier)[keyof typeof Tier];

// ----- Currency display mode (historical vs current FX) -----
export const RateMode = {
  Historical: "historical",
  Current: "current",
} as const;
export type RateMode = (typeof RateMode)[keyof typeof RateMode];

// ----- Core entity shapes (mirrors DB tables; see ARCHITECTURE.md §4) -----
/** Fields every synced row carries. */
export interface BaseRow {
  id: string;
  user_id: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface Account extends BaseRow {
  name: string;
  type: AccountType;
  currency: CurrencyCode;
  icon: string | null;
  color: string | null;
  is_archived: boolean;
  /** When false/absent, transactions can't take this account below zero. */
  allow_negative?: boolean;
}

export interface Transaction extends BaseRow {
  account_id: string;
  type: TransactionType;
  /** Minor units (e.g. cents/paise), integer. */
  amount: number;
  currency: CurrencyCode;
  category_id: string | null;
  note: string | null;
  description: string | null;
  payment_method: string | null;
  occurred_at: string;
  transfer_group_id: string | null;
  to_account_id: string | null;
  /** For cross-currency transfers: destination minor-unit amount. */
  to_amount: number | null;
  /** Rate captured at transfer time (to_amount / amount). */
  fx_rate: number | null;
}

export interface TransactionItem extends BaseRow {
  transaction_id: string;
  description: string;
  amount: number;
}

export interface ExchangeRate {
  base_currency: CurrencyCode;
  quote_currency: CurrencyCode;
  rate: number;
  as_of: string;
}
