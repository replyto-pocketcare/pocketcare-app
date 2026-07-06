/**
 * @pocketcare/data — repository interfaces (the data-access contract).
 * Platform apps provide implementations backed by a PowerSync database; the
 * contract keeps money invariants explicit so every implementation upholds them.
 */
import type { Account, Transaction, TransactionItem, CurrencyCode } from "@pocketcare/types";
import type { Money } from "@pocketcare/money";

/** Input for creating a transaction together with its breakdown, atomically. */
export interface NewTransactionInput {
  account_id: string;
  type: Transaction["type"];
  amount: Money;
  category_id?: string | null;
  /** Label names to attach; resolved to label rows (find-or-create) and written to transaction_labels. */
  labels?: string[] | null;
  note?: string | null;
  description?: string | null;
  payment_method?: string | null;
  occurred_at: string;
  /** Breakdown items; must reconcile to `amount` (enforced before commit). */
  items?: { description: string; amount: Money }[];
  /** For transfers. */
  to_account_id?: string | null;
  to_amount?: Money | null;
}

export interface AccountRepository {
  list(): Promise<Account[]>;
  get(id: string): Promise<Account | null>;
  create(input: Omit<Account, "id" | "user_id" | "created_at" | "updated_at" | "deleted_at">): Promise<Account>;
  /** Update editable account fields (name, type, color, icon, net-worth inclusion). */
  update(id: string, patch: Partial<Pick<Account, "name" | "type" | "color" | "icon" | "is_archived">> & { include_in_net_worth?: boolean }): Promise<void>;
  /** Set/adjust the opening balance by inserting an opening_balance/adjustment entry (never rewrites history). */
  setOpeningBalance(accountId: string, balance: Money, occurredAt: string): Promise<void>;
  archive(id: string): Promise<void>;
}

export interface TransactionRepository {
  /**
   * Create a transaction (+ optional breakdown items) inside ONE local SQLite
   * transaction. Implementations MUST reject if items don't reconcile to the
   * total (see @pocketcare/money `itemsReconcile`). Transfers write both sides.
   */
  create(input: NewTransactionInput): Promise<Transaction>;
  listByAccount(accountId: string, limit?: number): Promise<Transaction[]>;
  items(transactionId: string): Promise<TransactionItem[]>;
  search(query: string, limit?: number): Promise<Transaction[]>;
  /**
   * Edit a transaction and append an audit record of what changed. Balances are
   * derived live, so they recompute automatically. If the amount changes and the
   * transaction had a breakdown, the items are cleared (they'd no longer reconcile).
   */
  update(id: string, patch: EditTransactionInput): Promise<void>;
  /** Chronological edit history for a transaction. */
  history(id: string): Promise<TransactionAudit[]>;
}

export interface EditTransactionInput {
  type?: Transaction["type"];
  account_id?: string;
  amount?: Money;
  category_id?: string | null;
  /** When provided, replaces the transaction's labels (find-or-create + rewrite junction). */
  labels?: string[] | null;
  note?: string | null;
  description?: string | null;
  payment_method?: string | null;
  occurred_at?: string;
  to_account_id?: string | null;
  to_amount?: Money | null;
  /** If provided, completely replaces the transaction's items. If empty/null, removes them. */
  items?: { id?: string; description: string; amount: Money }[] | null;
}

export interface TransactionAudit {
  id: string;
  transaction_id: string;
  action: string;
  /** JSON string of { field: { from, to } }. */
  changes: string | null;
  created_at: string;
}

export interface BalanceRepository {
  /**
   * Ledger-derived balance for an account (SUM of signed effects). Never read
   * from a mutable stored number — always derived (invariant #2).
   */
  accountBalance(accountId: string): Promise<Money>;
  /** Net worth in the user's base currency, converting via cached rates. */
  netWorth(base: CurrencyCode, includeBlocked: boolean): Promise<Money>;
}

/** Budget row shape the repo needs (subset of the DB row). */
export interface BudgetLike {
  id: string;
  name?: string | null;
  period: import("@pocketcare/types").Period;
  /** Optional fixed timeframe; when set it overrides the recurring period. */
  start_date?: string | null;
  end_date?: string | null;
  limit_amount: number;
  currency: CurrencyCode;
  threshold_pct: number;
}

export interface BudgetRepository {
  list(): Promise<BudgetLike[]>;
  /** Money spent in the budget's current period window, honoring its scope. */
  spentThisPeriod(budget: BudgetLike, asOf?: Date): Promise<Money>;
}

export interface CreditCardDetails {
  account_id: string;
  statement_day: number;
  due_day: number;
  credit_limit: number | null;
  /** Optional last 4 digits, shown on the card face. Never required. */
  card_last4?: string | null;
}

export interface CreditCardRepository {
  getDetails(accountId: string): Promise<CreditCardDetails | null>;
  upsertDetails(details: CreditCardDetails): Promise<void>;
  /**
   * Record settling the card bill FROM a chosen account (feature #6).
   * This only records a transfer transaction; it does not pay a real bill.
   */
  settle(input: {
    fromAccountId: string;
    cardAccountId: string;
    amount: Money;
    toAmount?: Money;
    occurredAt: string;
  }): Promise<void>;
}

export interface Repositories {
  accounts: AccountRepository;
  transactions: TransactionRepository;
  balances: BalanceRepository;
  budgets: BudgetRepository;
  creditCards: CreditCardRepository;
}

export {
  PowerSyncAccountRepository,
  PowerSyncTransactionRepository,
  PowerSyncBalanceRepository,
  PowerSyncBudgetRepository,
  PowerSyncCreditCardRepository,
} from "./powersync-repositories.ts";
