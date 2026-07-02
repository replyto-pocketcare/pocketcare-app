/**
 * @pocketcare/db — PowerSync client schema (local SQLite mirror).
 * Shared by mobile (native SQLite) and web (WASM SQLite). Money columns are
 * INTEGER minor units. The authoritative schema + constraints live in Postgres
 * (see supabase/migrations); this mirror is what the client reads/writes offline.
 */
import { column, Schema, Table } from "@powersync/common";

const accounts = new Table({
  user_id: column.text,
  name: column.text,
  type: column.text,
  currency: column.text,
  icon: column.text,
  color: column.text,
  is_archived: column.integer,
  include_in_net_worth: column.integer,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const transactions = new Table(
  {
    user_id: column.text,
    account_id: column.text,
    type: column.text,
    amount: column.integer,
    currency: column.text,
    category_id: column.text,
    note: column.text,
    description: column.text,
    payment_method: column.text,
    occurred_at: column.text,
    transfer_group_id: column.text,
    to_account_id: column.text,
    to_amount: column.integer,
    fx_rate: column.real,
    created_at: column.text,
    updated_at: column.text,
    deleted_at: column.text,
  },
  { indexes: { by_account: ["account_id", "occurred_at"] } },
);

// --- Lookup tables (global reference; id = code, plus a display label) ---
const lookup = () => new Table({ label: column.text, sort: column.integer });
const account_types = lookup();
const transaction_types = lookup();
const category_kinds = lookup();
const periods = lookup();
const commitment_kinds = lookup();
const tiers = lookup();
const rate_modes = lookup();
const payment_methods = lookup();
const account_type_payment_methods = new Table({
  account_type_id: column.text,
  payment_method_id: column.text,
});

// --- Junction tables (many-to-many) ---
const transaction_labels = new Table(
  { user_id: column.text, transaction_id: column.text, label_id: column.text, created_at: column.text },
  { indexes: { by_txn: ["transaction_id"], by_label: ["label_id"] } },
);
const budget_categories = new Table({ user_id: column.text, budget_id: column.text, category_id: column.text });
const budget_labels = new Table({ user_id: column.text, budget_id: column.text, label_id: column.text });

const transaction_items = new Table(
  {
    user_id: column.text,
    transaction_id: column.text,
    description: column.text,
    amount: column.integer,
    created_at: column.text,
    updated_at: column.text,
    deleted_at: column.text,
  },
  { indexes: { by_txn: ["transaction_id"] } },
);

const transaction_audit = new Table(
  {
    user_id: column.text,
    transaction_id: column.text,
    action: column.text,
    changes: column.text,
    created_at: column.text,
  },
  { indexes: { by_txn: ["transaction_id"] } },
);

const categories = new Table({
  user_id: column.text,
  name: column.text,
  kind: column.text,
  icon: column.text,
  color: column.text,
  is_system: column.integer,
  parent_id: column.text,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const labels = new Table({
  user_id: column.text,
  name: column.text,
  color: column.text,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const credit_card_details = new Table({
  user_id: column.text,
  account_id: column.text,
  statement_day: column.integer,
  due_day: column.integer,
  credit_limit: column.integer,
  card_last4: column.text,
  created_at: column.text,
  updated_at: column.text,
});

const budgets = new Table({
  user_id: column.text,
  name: column.text,
  period: column.text,
  start_date: column.text,
  end_date: column.text,
  limit_amount: column.integer,
  currency: column.text,
  threshold_pct: column.integer,
  rollover: column.integer,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const goals = new Table({
  user_id: column.text,
  name: column.text,
  target_amount: column.integer,
  currency: column.text,
  priority: column.integer,
  is_emergency_fund: column.integer,
  target_date: column.text,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const goal_allocations = new Table({
  user_id: column.text,
  goal_id: column.text,
  source_account_id: column.text,
  amount_blocked: column.integer,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const recurring_commitments = new Table({
  user_id: column.text,
  kind: column.text,
  amount: column.integer,
  currency: column.text,
  frequency: column.text,
  next_due: column.text,
  category_id: column.text,
  account_id: column.text,
  loan_id: column.text,
  subscription_id: column.text,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const subscriptions = new Table({
  user_id: column.text,
  name: column.text,
  amount: column.integer,
  currency: column.text,
  billing_cycle: column.text,
  purchased_on: column.text,
  next_renewal: column.text,
  category_id: column.text,
  is_active: column.integer,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const loans = new Table({
  user_id: column.text,
  lender: column.text,
  principal: column.integer,
  currency: column.text,
  interest_rate: column.real,
  tenure_months: column.integer,
  emi_amount: column.integer,
  start_date: column.text,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const holdings = new Table({
  user_id: column.text,
  account_id: column.text,
  symbol: column.text,
  quantity: column.real,
  avg_cost: column.integer,
  currency: column.text,
  auto_fetch: column.integer,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const exchange_rates = new Table(
  {
    base_currency: column.text,
    quote_currency: column.text,
    rate: column.real,
    as_of: column.text,
  },
  { indexes: { by_pair: ["base_currency", "quote_currency", "as_of"] } },
);

export const AppSchema = new Schema({
  accounts,
  transactions,
  transaction_labels,
  transaction_items,
  transaction_audit,
  categories,
  labels,
  credit_card_details,
  budgets,
  budget_categories,
  budget_labels,
  goals,
  goal_allocations,
  recurring_commitments,
  subscriptions,
  loans,
  holdings,
  exchange_rates,
  // Lookup / reference tables
  account_types,
  transaction_types,
  category_kinds,
  periods,
  commitment_kinds,
  tiers,
  rate_modes,
  payment_methods,
  account_type_payment_methods,
});

export type Database = (typeof AppSchema)["types"];

export { SupabaseConnector } from "./connector.ts";
export {
  createSupabaseClient,
  ensureUser,
  isGuest,
  upgradeGuestWithEmail,
  type SupabaseConfig,
} from "./auth.ts";
