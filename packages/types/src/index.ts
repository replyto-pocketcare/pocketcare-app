/**
 * @sanvya/types — shared domain types & enums.
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

/**
 * Accounts that only RECORD investments — they hold holdings, not spendable
 * money.
 *
 * Money cannot physically leave a demat account to pay a credit card bill or
 * settle up with a friend: you would have to sell, wait to settle, and withdraw
 * first. Offering them in those pickers invites a transaction that never
 * happened, which then quietly misstates both the cash balance and the
 * portfolio.
 *
 * The Investments feature still moves money INTO these accounts when funding a
 * holding — that is the one legitimate direction, and it uses its own account
 * list rather than the general pickers this guards.
 *
 * One definition on purpose: this list was previously written out three times
 * (INVESTMENT_TYPES in RecurringModal, DEMAT_TYPES on the Investments page, and
 * inline SQL on Loans) and had already drifted — the Friends picker excluded
 * 'stocks' and 'mutual_funds' but not 'demat', so a demat account could still
 * be chosen to settle a debt.
 */
export const INVESTMENT_ACCOUNT_TYPES: readonly AccountType[] = [
  AccountType.Demat,
  AccountType.Stocks,
  AccountType.MutualFunds,
];

export const isInvestmentAccount = (type: string | null | undefined): boolean =>
  !!type && (INVESTMENT_ACCOUNT_TYPES as readonly string[]).includes(type);

/** SQL predicate for pickers that move real money. Alias-free; prefix if joined. */
export const NOT_INVESTMENT_ACCOUNT_SQL =
  `IFNULL(type,'') NOT IN (${INVESTMENT_ACCOUNT_TYPES.map((t) => `'${t}'`).join(",")})`;

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
