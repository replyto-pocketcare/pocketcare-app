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
    label: column.text,
    note: column.text,
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
  scope: column.text,
  scope_ref: column.text,
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
  transaction_items,
  transaction_audit,
  categories,
  labels,
  credit_card_details,
  budgets,
  goals,
  goal_allocations,
  recurring_commitments,
  subscriptions,
  loans,
  holdings,
  exchange_rates,
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
