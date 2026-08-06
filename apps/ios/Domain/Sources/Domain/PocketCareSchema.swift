/**
 * Mirrors packages/db/src/index.ts's `AppSchema` (the PowerSync client
 * schema / local SQLite mirror), generated from
 * tools/golden-vectors/vectors/mobile-schema.json by
 * tools/golden-vectors/gen-mobile-schema.mjs. DO NOT HAND-EDIT — see that
 * script's header for how to regenerate after packages/db/src/index.ts
 * changes, and how this doubles as the schema-parity check across all three
 * platforms.
 * 
 * Every table has an implicit `id: TEXT` primary key managed by PowerSync
 * itself; it is intentionally omitted from `columns` below (present on every
 * table, so listing it 63 times would be noise, not information) and is
 * assumed by any code consuming this schema.
 * 
 * This is a data-driven schema DESCRIPTOR (table/column names, SQLite
 * storage type, indexes, local-only flags) — not per-table row model
 * classes. Strongly-typed row models are P2.5 (repositories) territory,
 * once the local SQLite driver is chosen for each platform.
 */

public enum ColumnType: String, Sendable {
    case text = "TEXT"
    case integer = "INTEGER"
    case real = "REAL"
}

public struct ColumnDef: Sendable {
    public let name: String
    public let type: ColumnType
}

public struct IndexColumnDef: Sendable {
    public let name: String
    public let ascending: Bool
    public let type: ColumnType
}

public struct IndexDef: Sendable {
    public let name: String
    public let columns: [IndexColumnDef]
}

public struct TableDef: Sendable {
    public let name: String
    public let viewName: String
    public let columns: [ColumnDef]
    public let indexes: [IndexDef]
    public let localOnly: Bool
    public let insertOnly: Bool
}

public enum PocketCareSchema {
    public static let tables: [TableDef] = [
        TableDef(
            name: "account_type_payment_methods",
            viewName: "account_type_payment_methods",
            columns: [
                ColumnDef(name: "account_type_id", type: .text),
                ColumnDef(name: "payment_method_id", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "account_types",
            viewName: "account_types",
            columns: [
                ColumnDef(name: "label", type: .text),
                ColumnDef(name: "sort", type: .integer),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "accounts",
            viewName: "accounts",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "type", type: .text),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "icon", type: .text),
                ColumnDef(name: "color", type: .text),
                ColumnDef(name: "is_archived", type: .integer),
                ColumnDef(name: "include_in_net_worth", type: .integer),
                ColumnDef(name: "allow_negative", type: .integer),
                ColumnDef(name: "kind", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "assistant_memory",
            viewName: "assistant_memory",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "notes", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "assistant_messages",
            viewName: "assistant_messages",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "thread_id", type: .text),
                ColumnDef(name: "role", type: .text),
                ColumnDef(name: "content", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_thread", columns: [IndexColumnDef(name: "thread_id", ascending: true, type: .text), IndexColumnDef(name: "created_at", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "assistant_threads",
            viewName: "assistant_threads",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "title", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "budget_categories",
            viewName: "budget_categories",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "budget_id", type: .text),
                ColumnDef(name: "category_id", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "budget_labels",
            viewName: "budget_labels",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "budget_id", type: .text),
                ColumnDef(name: "label_id", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "budgets",
            viewName: "budgets",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "period", type: .text),
                ColumnDef(name: "start_date", type: .text),
                ColumnDef(name: "end_date", type: .text),
                ColumnDef(name: "limit_amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "threshold_pct", type: .integer),
                ColumnDef(name: "alert_time_utc", type: .text),
                ColumnDef(name: "rollover", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "bug_reports",
            viewName: "bug_reports",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "diagnostics", type: .text),
                ColumnDef(name: "kind", type: .text),
                ColumnDef(name: "severity", type: .text),
                ColumnDef(name: "area", type: .text),
                ColumnDef(name: "title", type: .text),
                ColumnDef(name: "description", type: .text),
                ColumnDef(name: "app_version", type: .text),
                ColumnDef(name: "route", type: .text),
                ColumnDef(name: "platform", type: .text),
                ColumnDef(name: "user_agent", type: .text),
                ColumnDef(name: "viewport", type: .text),
                ColumnDef(name: "online", type: .integer),
                ColumnDef(name: "status", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "categories",
            viewName: "categories",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "kind", type: .text),
                ColumnDef(name: "icon", type: .text),
                ColumnDef(name: "color", type: .text),
                ColumnDef(name: "is_system", type: .integer),
                ColumnDef(name: "parent_id", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "category_kinds",
            viewName: "category_kinds",
            columns: [
                ColumnDef(name: "label", type: .text),
                ColumnDef(name: "sort", type: .integer),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "category_rules",
            viewName: "category_rules",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "kind", type: .text),
                ColumnDef(name: "key", type: .text),
                ColumnDef(name: "category_id", type: .text),
                ColumnDef(name: "weight", type: .integer),
                ColumnDef(name: "corrections", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_user_key", columns: [IndexColumnDef(name: "user_id", ascending: true, type: .text), IndexColumnDef(name: "key", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "commitment_kinds",
            viewName: "commitment_kinds",
            columns: [
                ColumnDef(name: "label", type: .text),
                ColumnDef(name: "sort", type: .integer),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "connections",
            viewName: "connections",
            columns: [
                ColumnDef(name: "user_a", type: .text),
                ColumnDef(name: "user_b", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "coupons",
            viewName: "coupons",
            columns: [
                ColumnDef(name: "code", type: .text),
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "tier", type: .text),
                ColumnDef(name: "months", type: .integer),
                ColumnDef(name: "reason", type: .text),
                ColumnDef(name: "expires_at", type: .text),
                ColumnDef(name: "redeemed_at", type: .text),
                ColumnDef(name: "applied_until", type: .text),
                ColumnDef(name: "created_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "credit_card_details",
            viewName: "credit_card_details",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "account_id", type: .text),
                ColumnDef(name: "statement_day", type: .integer),
                ColumnDef(name: "due_day", type: .integer),
                ColumnDef(name: "credit_limit", type: .integer),
                ColumnDef(name: "card_last4", type: .text),
                ColumnDef(name: "pending_due", type: .integer),
                ColumnDef(name: "due_on", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "entitlements",
            viewName: "entitlements",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "tier", type: .text),
                ColumnDef(name: "source", type: .text),
                ColumnDef(name: "expires_at", type: .text),
                ColumnDef(name: "monthly_quota_total", type: .integer),
                ColumnDef(name: "monthly_quota_used", type: .integer),
                ColumnDef(name: "purchased_quota_remaining", type: .integer),
                ColumnDef(name: "quota_reset_date", type: .text),
                ColumnDef(name: "additional_purchased_quota", type: .integer),
                ColumnDef(name: "premium_trial_start_date", type: .text),
                ColumnDef(name: "plan_id", type: .text),
                ColumnDef(name: "billing_cycle", type: .text),
                ColumnDef(name: "subscription_status", type: .text),
                ColumnDef(name: "razorpay_subscription_id", type: .text),
                ColumnDef(name: "razorpay_customer_id", type: .text),
                ColumnDef(name: "current_period_end", type: .text),
                ColumnDef(name: "comp_tier", type: .text),
                ColumnDef(name: "comp_until", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "exchange_rates",
            viewName: "exchange_rates",
            columns: [
                ColumnDef(name: "base_currency", type: .text),
                ColumnDef(name: "quote_currency", type: .text),
                ColumnDef(name: "rate", type: .real),
                ColumnDef(name: "as_of", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_pair", columns: [IndexColumnDef(name: "base_currency", ascending: true, type: .text), IndexColumnDef(name: "quote_currency", ascending: true, type: .text), IndexColumnDef(name: "as_of", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "expense_item_shares",
            viewName: "expense_item_shares",
            columns: [
                ColumnDef(name: "item_id", type: .text),
                ColumnDef(name: "expense_id", type: .text),
                ColumnDef(name: "group_id", type: .text),
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "weight", type: .integer),
                ColumnDef(name: "share_amount", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_item", columns: [IndexColumnDef(name: "item_id", ascending: true, type: .text)]),
                IndexDef(name: "by_expense", columns: [IndexColumnDef(name: "expense_id", ascending: true, type: .text)]),
                IndexDef(name: "by_user", columns: [IndexColumnDef(name: "user_id", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "expense_items",
            viewName: "expense_items",
            columns: [
                ColumnDef(name: "expense_id", type: .text),
                ColumnDef(name: "group_id", type: .text),
                ColumnDef(name: "kind", type: .text),
                ColumnDef(name: "description", type: .text),
                ColumnDef(name: "quantity", type: .integer),
                ColumnDef(name: "unit", type: .text),
                ColumnDef(name: "unit_price", type: .integer),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "split_mode", type: .text),
                ColumnDef(name: "sort", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_expense", columns: [IndexColumnDef(name: "expense_id", ascending: true, type: .text), IndexColumnDef(name: "sort", ascending: true, type: .integer)]),
                IndexDef(name: "by_group", columns: [IndexColumnDef(name: "group_id", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "expense_participants",
            viewName: "expense_participants",
            columns: [
                ColumnDef(name: "expense_id", type: .text),
                ColumnDef(name: "group_id", type: .text),
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "paid_amount", type: .integer),
                ColumnDef(name: "share_amount", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_group", columns: [IndexColumnDef(name: "group_id", ascending: true, type: .text)]),
                IndexDef(name: "by_expense", columns: [IndexColumnDef(name: "expense_id", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "expense_postings",
            viewName: "expense_postings",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "expense_id", type: .text),
                ColumnDef(name: "settlement_id", type: .text),
                ColumnDef(name: "transaction_id", type: .text),
                ColumnDef(name: "role", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_expense", columns: [IndexColumnDef(name: "expense_id", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "expenses",
            viewName: "expenses",
            columns: [
                ColumnDef(name: "group_id", type: .text),
                ColumnDef(name: "created_by", type: .text),
                ColumnDef(name: "description", type: .text),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "occurred_at", type: .text),
                ColumnDef(name: "split_mode", type: .text),
                ColumnDef(name: "version", type: .integer),
                ColumnDef(name: "has_items", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_group", columns: [IndexColumnDef(name: "group_id", ascending: true, type: .text), IndexColumnDef(name: "occurred_at", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "failed_writes",
            viewName: "failed_writes",
            columns: [
                ColumnDef(name: "table_name", type: .text),
                ColumnDef(name: "op", type: .text),
                ColumnDef(name: "row_id", type: .text),
                ColumnDef(name: "payload", type: .text),
                ColumnDef(name: "code", type: .text),
                ColumnDef(name: "message", type: .text),
                ColumnDef(name: "cls", type: .text),
                ColumnDef(name: "reason", type: .text),
                ColumnDef(name: "attempts", type: .integer),
                ColumnDef(name: "failed_at", type: .text),
                ColumnDef(name: "resolved_at", type: .text),
                ColumnDef(name: "resolution", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_failed", columns: [IndexColumnDef(name: "failed_at", ascending: true, type: .text)]),
            ],
            localOnly: true,
            insertOnly: false
        ),
        TableDef(
            name: "goal_allocations",
            viewName: "goal_allocations",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "goal_id", type: .text),
                ColumnDef(name: "source_account_id", type: .text),
                ColumnDef(name: "amount_blocked", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "goals",
            viewName: "goals",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "target_amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "priority", type: .integer),
                ColumnDef(name: "is_emergency_fund", type: .integer),
                ColumnDef(name: "target_date", type: .text),
                ColumnDef(name: "alert_time_utc", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "holdings",
            viewName: "holdings",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "account_id", type: .text),
                ColumnDef(name: "symbol", type: .text),
                ColumnDef(name: "exchange", type: .text),
                ColumnDef(name: "quantity", type: .real),
                ColumnDef(name: "avg_cost", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "auto_fetch", type: .integer),
                ColumnDef(name: "instrument_type", type: .text),
                ColumnDef(name: "off_list", type: .integer),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "asset_class", type: .text),
                ColumnDef(name: "current_value", type: .integer),
                ColumnDef(name: "annual_rate", type: .real),
                ColumnDef(name: "maturity_date", type: .text),
                ColumnDef(name: "source_account_id", type: .text),
                ColumnDef(name: "planned_id", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "labels",
            viewName: "labels",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "color", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "loans",
            viewName: "loans",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "lender", type: .text),
                ColumnDef(name: "principal", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "interest_rate", type: .real),
                ColumnDef(name: "tenure_months", type: .integer),
                ColumnDef(name: "emi_amount", type: .integer),
                ColumnDef(name: "start_date", type: .text),
                ColumnDef(name: "emis_paid", type: .integer),
                ColumnDef(name: "emi_payments", type: .text),
                ColumnDef(name: "emi_due_day", type: .integer),
                ColumnDef(name: "auto_mark_paid", type: .integer),
                ColumnDef(name: "rate_type", type: .text),
                ColumnDef(name: "funding_account_id", type: .text),
                ColumnDef(name: "emi_amounts", type: .text),
                ColumnDef(name: "alert_time_utc", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "market_dividends",
            viewName: "market_dividends",
            columns: [
                ColumnDef(name: "symbol", type: .text),
                ColumnDef(name: "exchange", type: .text),
                ColumnDef(name: "ex_date", type: .text),
                ColumnDef(name: "pay_date", type: .text),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_symbol", columns: [IndexColumnDef(name: "symbol", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "market_overview",
            viewName: "market_overview",
            columns: [
                ColumnDef(name: "symbol", type: .text),
                ColumnDef(name: "exchange", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "sector", type: .text),
                ColumnDef(name: "industry", type: .text),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "pe", type: .real),
                ColumnDef(name: "eps", type: .real),
                ColumnDef(name: "dividend_yield", type: .real),
                ColumnDef(name: "dividend_per_share", type: .real),
                ColumnDef(name: "ex_dividend_date", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_symbol", columns: [IndexColumnDef(name: "symbol", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "market_quotes",
            viewName: "market_quotes",
            columns: [
                ColumnDef(name: "symbol", type: .text),
                ColumnDef(name: "exchange", type: .text),
                ColumnDef(name: "price", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "change_abs", type: .integer),
                ColumnDef(name: "change_pct", type: .real),
                ColumnDef(name: "as_of", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_symbol", columns: [IndexColumnDef(name: "symbol", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "notification_prefs",
            viewName: "notification_prefs",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "push_enabled", type: .integer),
                ColumnDef(name: "emi_due", type: .integer),
                ColumnDef(name: "budget", type: .integer),
                ColumnDef(name: "low_balance", type: .integer),
                ColumnDef(name: "outlier", type: .integer),
                ColumnDef(name: "group_invite", type: .integer),
                ColumnDef(name: "group_expense", type: .integer),
                ColumnDef(name: "low_balance_threshold", type: .integer),
                ColumnDef(name: "emi_lead_days", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "notifications",
            viewName: "notifications",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "kind", type: .text),
                ColumnDef(name: "title", type: .text),
                ColumnDef(name: "body", type: .text),
                ColumnDef(name: "severity", type: .text),
                ColumnDef(name: "href", type: .text),
                ColumnDef(name: "data", type: .text),
                ColumnDef(name: "dedupe_key", type: .text),
                ColumnDef(name: "read_at", type: .text),
                ColumnDef(name: "pushed_at", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_user_read", columns: [IndexColumnDef(name: "user_id", ascending: true, type: .text), IndexColumnDef(name: "read_at", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "payment_handle_disclosures",
            viewName: "payment_handle_disclosures",
            columns: [
                ColumnDef(name: "owner_user_id", type: .text),
                ColumnDef(name: "viewer_user_id", type: .text),
                ColumnDef(name: "group_id", type: .text),
                ColumnDef(name: "created_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_created", columns: [IndexColumnDef(name: "created_at", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "payment_methods",
            viewName: "payment_methods",
            columns: [
                ColumnDef(name: "label", type: .text),
                ColumnDef(name: "sort", type: .integer),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "payments",
            viewName: "payments",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "kind", type: .text),
                ColumnDef(name: "razorpay_order_id", type: .text),
                ColumnDef(name: "razorpay_payment_id", type: .text),
                ColumnDef(name: "razorpay_subscription_id", type: .text),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "status", type: .text),
                ColumnDef(name: "credits_added", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_user", columns: [IndexColumnDef(name: "user_id", ascending: true, type: .text), IndexColumnDef(name: "created_at", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "periods",
            viewName: "periods",
            columns: [
                ColumnDef(name: "label", type: .text),
                ColumnDef(name: "sort", type: .integer),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "planned_cashflow",
            viewName: "planned_cashflow",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "direction", type: .text),
                ColumnDef(name: "bucket", type: .text),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "frequency", type: .text),
                ColumnDef(name: "timeframe", type: .text),
                ColumnDef(name: "next_due", type: .text),
                ColumnDef(name: "expected_return", type: .integer),
                ColumnDef(name: "category_id", type: .text),
                ColumnDef(name: "account_id", type: .text),
                ColumnDef(name: "notes", type: .text),
                ColumnDef(name: "is_active", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_user", columns: [IndexColumnDef(name: "user_id", ascending: true, type: .text), IndexColumnDef(name: "direction", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "profiles",
            viewName: "profiles",
            columns: [
                ColumnDef(name: "base_currency", type: .text),
                ColumnDef(name: "locale", type: .text),
                ColumnDef(name: "rate_mode", type: .text),
                ColumnDef(name: "theme", type: .text),
                ColumnDef(name: "display_name", type: .text),
                ColumnDef(name: "email", type: .text),
                ColumnDef(name: "gender", type: .text),
                ColumnDef(name: "country", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "promo_redemptions",
            viewName: "promo_redemptions",
            columns: [
                ColumnDef(name: "code", type: .text),
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "applied_until", type: .text),
                ColumnDef(name: "redeemed_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "rate_modes",
            viewName: "rate_modes",
            columns: [
                ColumnDef(name: "label", type: .text),
                ColumnDef(name: "sort", type: .integer),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "receipt_scans",
            viewName: "receipt_scans",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "source", type: .text),
                ColumnDef(name: "engine", type: .text),
                ColumnDef(name: "merchant", type: .text),
                ColumnDef(name: "occurred_at", type: .text),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "subtotal", type: .integer),
                ColumnDef(name: "tax", type: .integer),
                ColumnDef(name: "service_charge", type: .integer),
                ColumnDef(name: "tip", type: .integer),
                ColumnDef(name: "discount", type: .integer),
                ColumnDef(name: "total", type: .integer),
                ColumnDef(name: "confidence", type: .integer),
                ColumnDef(name: "raw_text", type: .text),
                ColumnDef(name: "parsed_json", type: .text),
                ColumnDef(name: "transaction_id", type: .text),
                ColumnDef(name: "expense_id", type: .text),
                ColumnDef(name: "image_path", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_created", columns: [IndexColumnDef(name: "created_at", ascending: true, type: .text)]),
                IndexDef(name: "by_txn", columns: [IndexColumnDef(name: "transaction_id", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "recurring_commitments",
            viewName: "recurring_commitments",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "kind", type: .text),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "frequency", type: .text),
                ColumnDef(name: "next_due", type: .text),
                ColumnDef(name: "category_id", type: .text),
                ColumnDef(name: "account_id", type: .text),
                ColumnDef(name: "loan_id", type: .text),
                ColumnDef(name: "subscription_id", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "recurring_groups",
            viewName: "recurring_groups",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "direction", type: .text),
                ColumnDef(name: "icon", type: .text),
                ColumnDef(name: "color", type: .text),
                ColumnDef(name: "sort", type: .integer),
                ColumnDef(name: "is_system", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_user", columns: [IndexColumnDef(name: "user_id", ascending: true, type: .text), IndexColumnDef(name: "direction", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "recurring_rules",
            viewName: "recurring_rules",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "template_id", type: .text),
                ColumnDef(name: "frequency", type: .text),
                ColumnDef(name: "interval_count", type: .integer),
                ColumnDef(name: "next_due", type: .text),
                ColumnDef(name: "last_generated", type: .text),
                ColumnDef(name: "auto_post", type: .integer),
                ColumnDef(name: "active", type: .integer),
                ColumnDef(name: "alert_time_utc", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_user", columns: [IndexColumnDef(name: "user_id", ascending: true, type: .text), IndexColumnDef(name: "next_due", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "security_audit",
            viewName: "security_audit",
            columns: [
                ColumnDef(name: "actor", type: .text),
                ColumnDef(name: "action", type: .text),
                ColumnDef(name: "subject_user", type: .text),
                ColumnDef(name: "grant_id", type: .text),
                ColumnDef(name: "detail", type: .text),
                ColumnDef(name: "prev_hash", type: .text),
                ColumnDef(name: "row_hash", type: .text),
                ColumnDef(name: "created_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "settlements",
            viewName: "settlements",
            columns: [
                ColumnDef(name: "group_id", type: .text),
                ColumnDef(name: "from_user", type: .text),
                ColumnDef(name: "to_user", type: .text),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "method", type: .text),
                ColumnDef(name: "note", type: .text),
                ColumnDef(name: "settled_at", type: .text),
                ColumnDef(name: "created_by", type: .text),
                ColumnDef(name: "status", type: .text),
                ColumnDef(name: "confirmed_at", type: .text),
                ColumnDef(name: "confirmed_by", type: .text),
                ColumnDef(name: "upi_ref", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_group", columns: [IndexColumnDef(name: "group_id", ascending: true, type: .text)]),
                IndexDef(name: "by_status", columns: [IndexColumnDef(name: "status", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "split_group_members",
            viewName: "split_group_members",
            columns: [
                ColumnDef(name: "group_id", type: .text),
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "role", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_group", columns: [IndexColumnDef(name: "group_id", ascending: true, type: .text)]),
                IndexDef(name: "by_user", columns: [IndexColumnDef(name: "user_id", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "split_groups",
            viewName: "split_groups",
            columns: [
                ColumnDef(name: "created_by", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "kind", type: .text),
                ColumnDef(name: "is_direct", type: .integer),
                ColumnDef(name: "start_date", type: .text),
                ColumnDef(name: "end_date", type: .text),
                ColumnDef(name: "auto_split", type: .integer),
                ColumnDef(name: "default_mode", type: .text),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "archived", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "split_invitations",
            viewName: "split_invitations",
            columns: [
                ColumnDef(name: "group_id", type: .text),
                ColumnDef(name: "inviter", type: .text),
                ColumnDef(name: "invitee_email", type: .text),
                ColumnDef(name: "token", type: .text),
                ColumnDef(name: "status", type: .text),
                ColumnDef(name: "accepted_by", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "expires_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "subscriptions",
            viewName: "subscriptions",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "billing_cycle", type: .text),
                ColumnDef(name: "purchased_on", type: .text),
                ColumnDef(name: "next_renewal", type: .text),
                ColumnDef(name: "category_id", type: .text),
                ColumnDef(name: "is_active", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "support_grants",
            viewName: "support_grants",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "scope", type: .text),
                ColumnDef(name: "wrapped_dek_for_support", type: .text),
                ColumnDef(name: "signature", type: .text),
                ColumnDef(name: "expires_at", type: .text),
                ColumnDef(name: "revoked_at", type: .text),
                ColumnDef(name: "created_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "sync_attempts",
            viewName: "sync_attempts",
            columns: [
                ColumnDef(name: "attempts", type: .integer),
                ColumnDef(name: "last_code", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [],
            localOnly: true,
            insertOnly: false
        ),
        TableDef(
            name: "tiers",
            viewName: "tiers",
            columns: [
                ColumnDef(name: "label", type: .text),
                ColumnDef(name: "sort", type: .integer),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "transaction_audit",
            viewName: "transaction_audit",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "transaction_id", type: .text),
                ColumnDef(name: "action", type: .text),
                ColumnDef(name: "changes", type: .text),
                ColumnDef(name: "created_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_txn", columns: [IndexColumnDef(name: "transaction_id", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "transaction_items",
            viewName: "transaction_items",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "transaction_id", type: .text),
                ColumnDef(name: "description", type: .text),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_txn", columns: [IndexColumnDef(name: "transaction_id", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "transaction_labels",
            viewName: "transaction_labels",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "transaction_id", type: .text),
                ColumnDef(name: "label_id", type: .text),
                ColumnDef(name: "created_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_txn", columns: [IndexColumnDef(name: "transaction_id", ascending: true, type: .text)]),
                IndexDef(name: "by_label", columns: [IndexColumnDef(name: "label_id", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "transaction_templates",
            viewName: "transaction_templates",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "name", type: .text),
                ColumnDef(name: "type", type: .text),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "account_id", type: .text),
                ColumnDef(name: "to_account_id", type: .text),
                ColumnDef(name: "category_id", type: .text),
                ColumnDef(name: "description", type: .text),
                ColumnDef(name: "note", type: .text),
                ColumnDef(name: "payment_method", type: .text),
                ColumnDef(name: "labels", type: .text),
                ColumnDef(name: "split_group_id", type: .text),
                ColumnDef(name: "split_mode", type: .text),
                ColumnDef(name: "sort", type: .integer),
                ColumnDef(name: "group_id", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_user", columns: [IndexColumnDef(name: "user_id", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "transaction_types",
            viewName: "transaction_types",
            columns: [
                ColumnDef(name: "label", type: .text),
                ColumnDef(name: "sort", type: .integer),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "transactions",
            viewName: "transactions",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "account_id", type: .text),
                ColumnDef(name: "type", type: .text),
                ColumnDef(name: "amount", type: .integer),
                ColumnDef(name: "currency", type: .text),
                ColumnDef(name: "category_id", type: .text),
                ColumnDef(name: "note", type: .text),
                ColumnDef(name: "description", type: .text),
                ColumnDef(name: "payment_method", type: .text),
                ColumnDef(name: "occurred_at", type: .text),
                ColumnDef(name: "transfer_group_id", type: .text),
                ColumnDef(name: "to_account_id", type: .text),
                ColumnDef(name: "to_amount", type: .integer),
                ColumnDef(name: "fx_rate", type: .real),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
                ColumnDef(name: "deleted_at", type: .text),
            ],
            indexes: [
                IndexDef(name: "by_account", columns: [IndexColumnDef(name: "account_id", ascending: true, type: .text), IndexColumnDef(name: "occurred_at", ascending: true, type: .text)]),
            ],
            localOnly: false,
            insertOnly: false
        ),
        TableDef(
            name: "user_keys",
            viewName: "user_keys",
            columns: [
                ColumnDef(name: "user_id", type: .text),
                ColumnDef(name: "salt", type: .text),
                ColumnDef(name: "wrapped_dek_passphrase", type: .text),
                ColumnDef(name: "wrapped_dek_recovery", type: .text),
                ColumnDef(name: "signing_public_jwk", type: .text),
                ColumnDef(name: "wrapped_signing_private", type: .text),
                ColumnDef(name: "created_at", type: .text),
                ColumnDef(name: "updated_at", type: .text),
            ],
            indexes: [],
            localOnly: false,
            insertOnly: false
        ),
    ]

    public static let byName: [String: TableDef] = Dictionary(uniqueKeysWithValues: tables.map { ($0.name, $0) })
}
