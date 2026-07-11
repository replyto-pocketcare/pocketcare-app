/**
 * @pocketcare/db — PowerSync client schema (local SQLite mirror).
 * Shared by mobile (native SQLite) and web (WASM SQLite). Money columns are
 * INTEGER minor units. The authoritative schema + constraints live in Postgres
 * (see supabase/migrations); this mirror is what the client reads/writes offline.
 */
import { column, Schema, Table } from "@powersync/common";

const profiles = new Table({
  id: column.text,
  base_currency: column.text,
  locale: column.text,
  rate_mode: column.text,
  theme: column.text,
  display_name: column.text,
  email: column.text,
  gender: column.text,
  country: column.text,
  created_at: column.text,
  updated_at: column.text,
});

// Shared promo-code redemptions (own rows).
const promo_redemptions = new Table({
  code: column.text,
  user_id: column.text,
  applied_until: column.text,
  redeemed_at: column.text,
});

const entitlements = new Table({
  user_id: column.text,
  tier: column.text,
  source: column.text,
  expires_at: column.text,
  monthly_quota_total: column.integer,
  monthly_quota_used: column.integer,
  purchased_quota_remaining: column.integer,
  quota_reset_date: column.text,
  additional_purchased_quota: column.integer,
  premium_trial_start_date: column.text,
  plan_id: column.text,
  billing_cycle: column.text,
  subscription_status: column.text,
  razorpay_subscription_id: column.text,
  razorpay_customer_id: column.text,
  current_period_end: column.text,
  comp_tier: column.text,   // complimentary tier from a redeemed coupon/promo
  comp_until: column.text,  // …valid until (time-bound)
  updated_at: column.text,
});

const payments = new Table(
  {
    user_id: column.text,
    kind: column.text,
    razorpay_order_id: column.text,
    razorpay_payment_id: column.text,
    razorpay_subscription_id: column.text,
    amount: column.integer,
    currency: column.text,
    status: column.text,
    credits_added: column.integer,
    created_at: column.text,
    updated_at: column.text,
  },
  { indexes: { by_user: ["user_id", "created_at"] } },
);

const accounts = new Table({
  user_id: column.text,
  name: column.text,
  type: column.text,
  currency: column.text,
  icon: column.text,
  color: column.text,
  is_archived: column.integer,
  include_in_net_worth: column.integer,
  allow_negative: column.integer, // 0 = block overdraft (default), 1 = allow negative balance
  kind: column.text, // 'real' (default) | 'receivable' | 'payable' (hidden virtual accounts)
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
  exchange: column.text,
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

// Alpha Vantage market data (global, read-only; populated by the market-sync
// edge function). Composite PKs synthesize a text `id` in the sync stream.
const market_quotes = new Table(
  {
    symbol: column.text,
    exchange: column.text,
    price: column.integer, // minor units, per share
    currency: column.text,
    change_abs: column.integer,
    change_pct: column.real,
    as_of: column.text,
    updated_at: column.text,
  },
  { indexes: { by_symbol: ["symbol"] } },
);
const market_dividends = new Table(
  {
    symbol: column.text,
    exchange: column.text,
    ex_date: column.text,
    pay_date: column.text,
    amount: column.integer, // per share, minor units
    currency: column.text,
    updated_at: column.text,
  },
  { indexes: { by_symbol: ["symbol"] } },
);
const market_overview = new Table(
  {
    symbol: column.text,
    exchange: column.text,
    name: column.text,
    sector: column.text,
    industry: column.text,
    currency: column.text,
    pe: column.real,
    eps: column.real,
    dividend_yield: column.real,
    dividend_per_share: column.real,
    ex_dividend_date: column.text,
    updated_at: column.text,
  },
  { indexes: { by_symbol: ["symbol"] } },
);

// Zero-trust encryption: wrapped keys, consent grants, hash-chained audit.
// The server only ever holds wrapped keys + ciphertext (see SECURITY_ENCRYPTION_PLAN.md).
const user_keys = new Table({
  user_id: column.text,
  salt: column.text,
  wrapped_dek_passphrase: column.text,
  wrapped_dek_recovery: column.text,
  signing_public_jwk: column.text, // JSON string
  wrapped_signing_private: column.text,
  created_at: column.text,
  updated_at: column.text,
});
const support_grants = new Table({
  user_id: column.text,
  scope: column.text,
  wrapped_dek_for_support: column.text,
  signature: column.text,
  expires_at: column.text,
  revoked_at: column.text,
  created_at: column.text,
});
const security_audit = new Table({
  actor: column.text,
  action: column.text,
  subject_user: column.text,
  grant_id: column.text,
  detail: column.text,
  prev_hash: column.text,
  row_hash: column.text,
  created_at: column.text,
});

// Beta bug reports + reward coupons.
const bug_reports = new Table({
  user_id: column.text,
  kind: column.text, // 'bug' | 'suggestion'
  severity: column.text,
  area: column.text,
  title: column.text,
  description: column.text,
  app_version: column.text,
  route: column.text,
  platform: column.text,
  user_agent: column.text,
  viewport: column.text,
  online: column.integer,
  status: column.text,
  created_at: column.text,
});
const coupons = new Table({
  code: column.text,
  user_id: column.text,
  tier: column.text,
  months: column.integer,
  reason: column.text,
  expires_at: column.text,
  redeemed_at: column.text,
  applied_until: column.text,
  created_at: column.text,
});

// AI assistant persistence (chat history + per-user memory).
const assistant_threads = new Table({
  user_id: column.text,
  title: column.text,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});
const assistant_messages = new Table(
  {
    user_id: column.text,
    thread_id: column.text,
    role: column.text,
    content: column.text,
    created_at: column.text,
    updated_at: column.text,
  },
  { indexes: { by_thread: ["thread_id", "created_at"] } },
);
const assistant_memory = new Table({
  user_id: column.text,
  notes: column.text,
  created_at: column.text,
  updated_at: column.text,
});

// --- Expense splitting (multi-user shared ledger) ---
const split_groups = new Table({
  created_by: column.text, name: column.text, kind: column.text, is_direct: column.integer,
  start_date: column.text, end_date: column.text, auto_split: column.integer,
  default_mode: column.text, currency: column.text, archived: column.integer,
  created_at: column.text, updated_at: column.text, deleted_at: column.text,
});
const split_group_members = new Table(
  { group_id: column.text, user_id: column.text, role: column.text, created_at: column.text, updated_at: column.text, deleted_at: column.text },
  { indexes: { by_group: ["group_id"], by_user: ["user_id"] } },
);
const expenses = new Table(
  { group_id: column.text, created_by: column.text, description: column.text, amount: column.integer, currency: column.text, occurred_at: column.text, split_mode: column.text, version: column.integer, created_at: column.text, updated_at: column.text, deleted_at: column.text },
  { indexes: { by_group: ["group_id", "occurred_at"] } },
);
const expense_participants = new Table(
  { expense_id: column.text, group_id: column.text, user_id: column.text, paid_amount: column.integer, share_amount: column.integer, created_at: column.text, updated_at: column.text, deleted_at: column.text },
  { indexes: { by_group: ["group_id"], by_expense: ["expense_id"] } },
);
const settlements = new Table(
  { group_id: column.text, from_user: column.text, to_user: column.text, amount: column.integer, currency: column.text, method: column.text, note: column.text, settled_at: column.text, created_by: column.text, created_at: column.text, updated_at: column.text, deleted_at: column.text },
  { indexes: { by_group: ["group_id"] } },
);
const expense_postings = new Table(
  { user_id: column.text, expense_id: column.text, settlement_id: column.text, transaction_id: column.text, role: column.text, created_at: column.text, updated_at: column.text, deleted_at: column.text },
  { indexes: { by_expense: ["expense_id"] } },
);
const split_invitations = new Table({
  group_id: column.text, inviter: column.text, invitee_email: column.text, token: column.text,
  status: column.text, accepted_by: column.text, created_at: column.text, updated_at: column.text, expires_at: column.text,
});
const connections = new Table({
  user_a: column.text, user_b: column.text, created_at: column.text, deleted_at: column.text,
});
const transaction_templates = new Table(
  {
    user_id: column.text, name: column.text, type: column.text, amount: column.integer, currency: column.text,
    account_id: column.text, to_account_id: column.text, category_id: column.text, description: column.text,
    note: column.text, payment_method: column.text, labels: column.text, split_group_id: column.text, split_mode: column.text,
    sort: column.integer,
    created_at: column.text, updated_at: column.text, deleted_at: column.text,
  },
  { indexes: { by_user: ["user_id"] } },
);
const recurring_rules = new Table(
  {
    user_id: column.text, template_id: column.text, frequency: column.text, interval_count: column.integer,
    next_due: column.text, last_generated: column.text, auto_post: column.integer, active: column.integer,
    created_at: column.text, updated_at: column.text, deleted_at: column.text,
  },
  { indexes: { by_user: ["user_id", "next_due"] } },
);

const category_rules = new Table(
  {
    user_id: column.text, kind: column.text, key: column.text, category_id: column.text,
    weight: column.integer, corrections: column.integer,
    created_at: column.text, updated_at: column.text, deleted_at: column.text,
  },
  { indexes: { by_user_key: ["user_id", "key"] } }
);

export const AppSchema = new Schema({
  profiles,
  entitlements,
  payments,
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
  market_quotes,
  market_dividends,
  market_overview,
  user_keys,
  support_grants,
  security_audit,
  bug_reports,
  coupons,
  promo_redemptions,
  assistant_threads,
  assistant_messages,
  assistant_memory,
  // Expense splitting (multi-user)
  split_groups,
  split_group_members,
  expenses,
  expense_participants,
  settlements,
  expense_postings,
  split_invitations,
  connections,
  transaction_templates,
  recurring_rules,
  category_rules,
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
