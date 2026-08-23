/**
 * @sanvya/db — PowerSync client schema (local SQLite mirror).
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

const public_profiles = new Table({
  id: column.text,
  display_name: column.text,
  email: column.text,
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
    intent: column.text,
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
  pending_due: column.integer, // amount owed (minor units) for the current statement
  due_on: column.text, // date that pending_due is payable (may be next cycle)
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
  alert_time_utc: column.text,
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
  alert_time_utc: column.text,
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
  emis_paid: column.integer, // how many EMIs the user has already paid (derived from emi_payments when present)
  emi_payments: column.text, // JSON map { "<emiNo>": "<paidOn ISO date>" }
  emi_due_day: column.integer, // day-of-month (1–31) each EMI is due; combined with start_date to derive due dates
  auto_mark_paid: column.integer, // 0/1 — when on, past-due EMIs are treated as paid (derived at read time)
  rate_type: column.text, // 'fixed' (compute EMI + schedule) | 'variable' (user enters each month's EMI)
  // Account the EMI is charged to (usually a credit card). NULL = not linked.
  // Drives posting a due EMI onto the card, so it must sync — see 0047.
  funding_account_id: column.text,
  emi_amounts: column.text, // JSON map { "<emiNo>": <amountMinor> } — per-month EMI for variable loans
  alert_time_utc: column.text,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

// Planned Cashflow hub (BETA): named recurring incomes, planned payments, and
// savings/investment plans. `direction` splits income vs payment vs saving;
// `bucket` groups payments (subscription/loan/household/other); `timeframe`
// controls which summary tab an item rolls up into. `expected_return` (annual %,
// stored ×100 as int) powers the savings-growth + AI projection engine.

const holdings = new Table({
  user_id: column.text,
  account_id: column.text,
  symbol: column.text,
  exchange: column.text,
  quantity: column.real, // shares (stocks) or units (mutual funds)
  avg_cost: column.integer, // per-unit cost / NAV in minor units
  currency: column.text,
  auto_fetch: column.integer,
  instrument_type: column.text, // 'stock' | 'mf' (legacy; superseded by asset_class)
  off_list: column.integer, // 1 = not in our fetched catalog → gains/losses untracked
  name: column.text, // display name for off-list holdings (symbol may be blank)
  asset_class: column.text, // 'stock' | 'mf' | 'crypto' | 'fd' | 'sip' | 'other'
  current_value: column.integer, // user-supplied current value (minor units) for unpriced assets
  annual_rate: column.real, // FD / scheme interest rate % p.a.
  maturity_date: column.text, // FD maturity date (ISO)
  source_account_id: column.text, // savings/bank account that funded a NEW investment (null = tracking existing)
  planned_id: column.text, // linked planned_cashflow saving row (for SIPs)
  sip_amount: column.integer, // amount-based SIP: monthly amount (minor units)
  sip_start_date: column.text, // amount-based SIP: date it began (ISO)
  sip_day: column.integer, // amount-based SIP: day-of-month (1–28) the amount is debited to invest
  total_invested: column.integer, // running sum of contributions (minor units)
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
  // Redacted device log (0043). Mirrored here because PowerSync's local SQLite
  // only has the columns declared in this schema.
  diagnostics: column.text,
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
  updated_at: column.text, // insertRow/updateRow always set this
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

const price_offers = new Table({
  id: column.text,
  tier: column.text,
  cycle: column.text,
  price: column.integer,
  label: column.text,
  starts_at: column.text,
  ends_at: column.text,
  segment_id: column.text,
  active: column.integer,
  created_at: column.text,
  updated_at: column.text,
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
// `has_items` (0040) flags that this expense has an `expense_items` breakdown.
// PowerSync's local SQLite only has the columns declared here, so a column
// added to Postgres MUST be mirrored here or every read and write of it fails
// with "table expenses has no column named has_items".
const expenses = new Table(
  {
    group_id: column.text, created_by: column.text, description: column.text, amount: column.integer,
    currency: column.text, occurred_at: column.text, split_mode: column.text, version: column.integer,
    has_items: column.integer,
    created_at: column.text, updated_at: column.text, deleted_at: column.text,
  },
  { indexes: { by_group: ["group_id", "occurred_at"] } },
);
const expense_participants = new Table(
  { expense_id: column.text, group_id: column.text, user_id: column.text, paid_amount: column.integer, share_amount: column.integer, created_at: column.text, updated_at: column.text, deleted_at: column.text },
  { indexes: { by_group: ["group_id"], by_expense: ["expense_id"] } },
);
// `status` (0041) is confirmed | pending | disputed. It defaults to 'confirmed'
// server-side so every pre-existing row and the manual "mark settled" flow keep
// their original meaning; only the UPI pay flow writes 'pending'.
// NOTE: payment_handles and payment_handle_disclosures are DELIBERATELY absent
// from this schema — they are server-only and must never sync to a device.
const settlements = new Table(
  {
    group_id: column.text, from_user: column.text, to_user: column.text, amount: column.integer,
    currency: column.text, method: column.text, note: column.text, settled_at: column.text,
    created_by: column.text, status: column.text, confirmed_at: column.text,
    confirmed_by: column.text, upi_ref: column.text,
    created_at: column.text, updated_at: column.text, deleted_at: column.text,
  },
  { indexes: { by_group: ["group_id"], by_status: ["status"] } },
);
const expense_postings = new Table(
  { user_id: column.text, expense_id: column.text, settlement_id: column.text, transaction_id: column.text, role: column.text, created_at: column.text, updated_at: column.text, deleted_at: column.text },
  { indexes: { by_expense: ["expense_id"] } },
);
// Your audit trail of who fetched your UPI ID (0041). Holds no secret — the
// encrypted handle itself lives in `payment_handles`, which is server-only and
// deliberately NOT in this schema.
const payment_handle_disclosures = new Table(
  {
    owner_user_id: column.text, viewer_user_id: column.text, group_id: column.text,
    created_at: column.text,
  },
  { indexes: { by_created: ["created_at"] } },
);

// Itemized bills (0040). `expense_items` are the lines of a shared expense and
// `expense_item_shares` say who is on each line. Per-item shares are rolled up
// into `expense_participants` by the client, which remains the source of truth
// for balances — these two tables are the breakdown, not the ledger.
const expense_items = new Table(
  {
    expense_id: column.text, group_id: column.text, kind: column.text, description: column.text,
    quantity: column.integer, unit: column.text, unit_price: column.integer, amount: column.integer,
    split_mode: column.text, sort: column.integer,
    created_at: column.text, updated_at: column.text, deleted_at: column.text,
  },
  { indexes: { by_expense: ["expense_id", "sort"], by_group: ["group_id"] } },
);
const expense_item_shares = new Table(
  {
    item_id: column.text, expense_id: column.text, group_id: column.text, user_id: column.text,
    weight: column.integer, share_amount: column.integer,
    created_at: column.text, updated_at: column.text, deleted_at: column.text,
  },
  { indexes: { by_item: ["item_id"], by_expense: ["expense_id"], by_user: ["user_id"] } },
);
// A scan is private to the user who took it. Deliberately holds NO image bytes —
// `image_path` is a forward-compatible seam and is always null today.
const receipt_scans = new Table(
  {
    user_id: column.text, source: column.text, engine: column.text, merchant: column.text,
    occurred_at: column.text, currency: column.text,
    subtotal: column.integer, tax: column.integer, service_charge: column.integer,
    tip: column.integer, discount: column.integer, total: column.integer,
    confidence: column.integer, raw_text: column.text, parsed_json: column.text,
    transaction_id: column.text, expense_id: column.text, image_path: column.text,
    created_at: column.text, updated_at: column.text, deleted_at: column.text,
  },
  { indexes: { by_created: ["created_at"], by_txn: ["transaction_id"] } },
);
const split_invitations = new Table({
  group_id: column.text, inviter: column.text, invitee_email: column.text, token: column.text,
  status: column.text, accepted_by: column.text, created_at: column.text, updated_at: column.text, expires_at: column.text,
});
const connections = new Table({
  user_a: column.text, user_b: column.text, created_at: column.text, deleted_at: column.text,
});
// Dedicated recurring incomes & expenses (replaces templates+rules for tracking).
const recurring_items = new Table(
  {
    user_id: column.text, direction: column.text, name: column.text,
    amount: column.integer, currency: column.text, frequency: column.text, interval_count: column.integer,
    next_due: column.text, account_id: column.text, category_id: column.text,
    auto_post: column.integer, active: column.integer, alert_time_utc: column.text,
    // Everything the posting engine needs, so a recurring item no longer has to
    // borrow a transaction_templates row to describe the transaction it posts.
    to_account_id: column.text, description: column.text, note: column.text,
    payment_method: column.text, labels: column.text,
    split_group_id: column.text, split_mode: column.text, last_generated: column.text,
    source_table: column.text, source_id: column.text,
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

const notifications = new Table(
  {
    user_id: column.text, kind: column.text, title: column.text, subtitle: column.text, body: column.text,
    image_url: column.text, severity: column.text, href: column.text, data: column.text, dedupe_key: column.text,
    read_at: column.text, pushed_at: column.text,
    created_at: column.text, updated_at: column.text, deleted_at: column.text,
  },
  { indexes: { by_user_read: ["user_id", "read_at"] } }
);

const notification_prefs = new Table({
  user_id: column.text,
  push_enabled: column.integer,
  emi_due: column.integer,
  budget: column.integer,
  low_balance: column.integer,
  outlier: column.integer,
  group_invite: column.integer,
  group_expense: column.integer,
  low_balance_threshold: column.integer,
  emi_lead_days: column.integer,
  created_at: column.text,
  updated_at: column.text,
  deleted_at: column.text,
});

const audience_groups = new Table({
  id: column.text,
  name: column.text,
  description: column.text,
  sys_key: column.text,
  kind: column.text,
  rule: column.text,
  active: column.integer,
  created_at: column.text,
});

const audience_group_members = new Table(
  { group_id: column.text, user_id: column.text, joined_at: column.text, source: column.text },
  { indexes: { by_group: ["group_id"], by_user: ["user_id"] } }
);

/**
 * DEAD-LETTER QUEUE (sync fault tolerance, layer 3).
 *
 * LOCAL-ONLY, deliberately. A write that the server refuses is quarantined
 * here so the upload queue can move on — and if this table itself synced, the
 * quarantine record would join the very queue it was created to unblock, and a
 * failure to upload it would be quarantined again. Recovery is a device-local
 * concern; the row content already lives in local SQLite anyway.
 *
 * `id` is the ps_crud row id as text, so re-quarantining the same op upserts
 * rather than duplicating.
 */
const failed_writes = new Table(
  {
    /** Unqualified table the write targeted. */
    table_name: column.text,
    /** PUT / PATCH / DELETE. */
    op: column.text,
    /** id of the row that failed — how it's matched back to local data. */
    row_id: column.text,
    /** Full JSON payload. This is the user's data; it must not be lost. */
    payload: column.text,
    /** SQLSTATE, when PostgREST gave one. */
    code: column.text,
    message: column.text,
    /** "permanent" — transient failures are never quarantined. */
    cls: column.text,
    reason: column.text,
    attempts: column.integer,
    failed_at: column.text,
    /** Set once the user has retried or discarded it, so it leaves the list. */
    resolved_at: column.text,
    resolution: column.text,
  },
  { localOnly: true, indexes: { by_failed: ["failed_at"] } },
);

/**
 * Per-op retry counter, local-only.
 *
 * In memory would be lost on reload, and a permanent failure that reloads
 * before it reaches the attempt threshold would retry forever — exactly the
 * head-of-line block this is meant to end.
 */
const sync_attempts = new Table(
  { attempts: column.integer, last_code: column.text, updated_at: column.text },
  { localOnly: true },
);

export const AppSchema = new Schema({
  profiles,
  public_profiles,
  notifications,
  notification_prefs,
  audience_groups,
  audience_group_members,
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
  price_offers,
  assistant_threads,
  assistant_messages,
  assistant_memory,
  // Expense splitting (multi-user)
  split_groups,
  split_group_members,
  expenses,
  expense_participants,
  expense_items,
  expense_item_shares,
  settlements,
  expense_postings,
  split_invitations,
  connections,
  // Receipt / bill scanning
  receipt_scans,
  // Payments (0041) — the audit trail only; payment_handles is server-only.
  payment_handle_disclosures,
  recurring_items,
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
  // Sync fault tolerance (local-only; never uploaded)
  failed_writes,
  sync_attempts,
});

export type Database = (typeof AppSchema)["types"];

export {
  SupabaseConnector,
  setSyncDiagnosticSink,
  setFaultInjection,
  getFaultInjection,
  type SyncDiagnostic,
  type FaultInjection,
} from "./connector.ts";
export { opKey, quarantineOps, clearAttempts } from "./quarantine.ts";
export {
  createSupabaseClient,
  ensureUser,
  isGuest,
  upgradeGuestWithEmail,
  type SupabaseConfig,
} from "./auth.ts";
