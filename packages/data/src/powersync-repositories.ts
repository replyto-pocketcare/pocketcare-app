/**
 * PowerSync-backed repository implementations.
 * All writes go through the local SQLite DB (offline-first) and sync via the
 * connector. Money invariants are enforced here before anything is committed.
 */
import type { AbstractPowerSyncDatabase } from "@powersync/common";
import type { Account, Transaction, TransactionItem, CurrencyCode } from "@pocketcare/types";
import { itemsReconcile, money, type Money } from "@pocketcare/money";
import { deriveBalance, type LedgerEntry } from "@pocketcare/ledger";
import { periodBounds } from "@pocketcare/budget";
import type {
  AccountRepository,
  TransactionRepository,
  BalanceRepository,
  BudgetRepository,
  BudgetLike,
  CreditCardRepository,
  CreditCardDetails,
  NewTransactionInput,
  EditTransactionInput,
  TransactionAudit,
} from "./index.ts";

const uuid = () => globalThis.crypto.randomUUID();
const nowIso = () => new Date().toISOString();

export class PowerSyncAccountRepository implements AccountRepository {
  constructor(
    private readonly db: AbstractPowerSyncDatabase,
    private readonly getUserId: () => string,
  ) {}

  async list(): Promise<Account[]> {
    return this.db.getAll<Account>(
      "SELECT * FROM accounts WHERE deleted_at IS NULL ORDER BY created_at",
    );
  }

  async get(id: string): Promise<Account | null> {
    return this.db.getOptional<Account>("SELECT * FROM accounts WHERE id = ?", [id]);
  }

  async create(
    input: Omit<Account, "id" | "user_id" | "created_at" | "updated_at" | "deleted_at">,
  ): Promise<Account> {
    const id = uuid();
    const ts = nowIso();
    const row: Account = {
      ...input,
      id,
      user_id: this.getUserId(),
      created_at: ts,
      updated_at: ts,
      deleted_at: null,
    };
    await this.db.execute(
      `INSERT INTO accounts (id,user_id,name,type,currency,icon,color,is_archived,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?)`,
      [id, row.user_id, row.name, row.type, row.currency, row.icon, row.color, row.is_archived ? 1 : 0, ts, ts],
    );
    return row;
  }

  /** Set/adjust opening balance by appending a ledger entry — never rewrites history. */
  async setOpeningBalance(accountId: string, balance: Money, occurredAt: string): Promise<void> {
    const account = await this.get(accountId);
    if (!account) throw new Error(`Account ${accountId} not found`);
    if (account.currency !== balance.currency) {
      throw new Error("Opening balance currency must match account currency");
    }
    // First opening balance vs later correction: both are ledger entries.
    const existing = await this.db.getOptional<{ c: number }>(
      "SELECT COUNT(*) as c FROM transactions WHERE account_id = ? AND type = 'opening_balance'",
      [accountId],
    );
    const type = existing && existing.c > 0 ? "adjustment" : "opening_balance";
    const id = uuid();
    const ts = nowIso();
    await this.db.execute(
      `INSERT INTO transactions (id,user_id,account_id,type,amount,currency,occurred_at,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?)`,
      [id, this.getUserId(), accountId, type, balance.amount, balance.currency, occurredAt, ts, ts],
    );
  }

  async update(
    id: string,
    patch: Partial<Pick<Account, "name" | "type" | "color" | "icon" | "is_archived">> & { include_in_net_worth?: boolean },
  ): Promise<void> {
    const sets: string[] = [];
    const params: (string | number | null)[] = [];
    if (patch.name !== undefined) { sets.push("name = ?"); params.push(patch.name); }
    if (patch.type !== undefined) { sets.push("type = ?"); params.push(patch.type); }
    if (patch.color !== undefined) { sets.push("color = ?"); params.push(patch.color); }
    if (patch.icon !== undefined) { sets.push("icon = ?"); params.push(patch.icon); }
    if (patch.is_archived !== undefined) { sets.push("is_archived = ?"); params.push(patch.is_archived ? 1 : 0); }
    if (patch.include_in_net_worth !== undefined) { sets.push("include_in_net_worth = ?"); params.push(patch.include_in_net_worth ? 1 : 0); }
    if (sets.length === 0) return;
    sets.push("updated_at = ?"); params.push(nowIso());
    params.push(id);
    await this.db.execute(`UPDATE accounts SET ${sets.join(", ")} WHERE id = ?`, params);
  }

  async archive(id: string): Promise<void> {
    await this.db.execute(
      "UPDATE accounts SET is_archived = 1, updated_at = ? WHERE id = ?",
      [nowIso(), id],
    );
  }
}

export class PowerSyncTransactionRepository implements TransactionRepository {
  constructor(
    private readonly db: AbstractPowerSyncDatabase,
    private readonly getUserId: () => string,
  ) {}

  /** Atomic write of a transaction + its breakdown items, with reconcile guard. */
  async create(input: NewTransactionInput): Promise<Transaction> {
    const items = input.items ?? [];
    if (items.length > 0 && !itemsReconcile(input.amount, items.map((i) => i.amount))) {
      throw new Error("Breakdown items must sum exactly to the transaction amount");
    }
    if (input.type === "transfer" && !input.to_account_id) {
      throw new Error("Transfer requires a destination account");
    }

    const userId = this.getUserId();
    const ts = nowIso();
    const id = uuid();
    const transferGroup = input.type === "transfer" ? uuid() : null;
    const toAmount = input.to_amount ?? null;
    const fxRate =
      toAmount && input.amount.amount !== 0 ? toAmount.amount / input.amount.amount : null;

    const row: Transaction = {
      id,
      user_id: userId,
      account_id: input.account_id,
      type: input.type,
      amount: input.amount.amount,
      currency: input.amount.currency,
      category_id: input.category_id ?? null,
      label: input.label ?? null,
      note: input.note ?? null,
      description: input.description ?? null,
      payment_method: input.payment_method ?? null,
      occurred_at: input.occurred_at,
      transfer_group_id: transferGroup,
      to_account_id: input.to_account_id ?? null,
      to_amount: toAmount?.amount ?? null,
      fx_rate: fxRate,
      created_at: ts,
      updated_at: ts,
      deleted_at: null,
    };

    await this.db.writeTransaction(async (tx) => {
      await tx.execute(
        `INSERT INTO transactions
          (id,user_id,account_id,type,amount,currency,category_id,label,note,description,payment_method,occurred_at,
           transfer_group_id,to_account_id,to_amount,fx_rate,created_at,updated_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
        [
          row.id, row.user_id, row.account_id, row.type, row.amount, row.currency,
          row.category_id, row.label, row.note, row.description, row.payment_method, row.occurred_at, row.transfer_group_id,
          row.to_account_id, row.to_amount, row.fx_rate, ts, ts,
        ],
      );
      for (const item of items) {
        await tx.execute(
          `INSERT INTO transaction_items (id,user_id,transaction_id,description,amount,created_at,updated_at)
           VALUES (?,?,?,?,?,?,?)`,
          [uuid(), userId, id, item.description, item.amount.amount, ts, ts],
        );
      }
    });

    return row;
  }

  async listByAccount(accountId: string, limit = 50): Promise<Transaction[]> {
    return this.db.getAll<Transaction>(
      `SELECT * FROM transactions WHERE account_id = ? AND deleted_at IS NULL
       ORDER BY occurred_at DESC LIMIT ?`,
      [accountId, limit],
    );
  }

  async items(transactionId: string): Promise<TransactionItem[]> {
    return this.db.getAll<TransactionItem>(
      "SELECT * FROM transaction_items WHERE transaction_id = ? AND deleted_at IS NULL",
      [transactionId],
    );
  }

  async search(query: string, limit = 50): Promise<Transaction[]> {
    const like = `%${query}%`;
    return this.db.getAll<Transaction>(
      `SELECT * FROM transactions
       WHERE deleted_at IS NULL AND (label LIKE ? OR note LIKE ? OR description LIKE ?)
       ORDER BY occurred_at DESC LIMIT ?`,
      [like, like, like, limit],
    );
  }

  async update(id: string, patch: EditTransactionInput): Promise<void> {
    const before = await this.db.getOptional<Transaction>("SELECT * FROM transactions WHERE id = ?", [id]);
    if (!before) throw new Error(`Transaction ${id} not found`);

    const changes: Record<string, { from: unknown; to: unknown }> = {};
    const sets: string[] = [];
    const params: (string | number | null)[] = [];
    const track = (col: string, from: unknown, to: unknown) => {
      if (to !== undefined && to !== from) {
        changes[col] = { from, to };
        sets.push(`${col} = ?`);
        params.push(to as string | number | null);
      }
    };

    track("type", before.type, patch.type);
    track("account_id", before.account_id, patch.account_id);
    track("amount", before.amount, patch.amount?.amount);
    track("category_id", before.category_id, patch.category_id);
    track("label", before.label, patch.label);
    track("note", before.note, patch.note);
    track("description", before.description, patch.description);
    track("payment_method", before.payment_method, patch.payment_method);
    track("occurred_at", before.occurred_at, patch.occurred_at);
    track("to_account_id", before.to_account_id, patch.to_account_id);
    track("to_amount", before.to_amount, patch.to_amount?.amount ?? undefined);

    if (sets.length === 0) return;

    const ts = nowIso();
    await this.db.writeTransaction(async (tx) => {
      // If the amount changed, any existing breakdown no longer reconciles — clear it.
      if (changes.amount) {
        await tx.execute("UPDATE transaction_items SET deleted_at = ?, updated_at = ? WHERE transaction_id = ? AND deleted_at IS NULL", [ts, ts, id]);
      }
      sets.push("updated_at = ?");
      params.push(ts, id);
      await tx.execute(`UPDATE transactions SET ${sets.join(", ")} WHERE id = ?`, params);
      await tx.execute(
        `INSERT INTO transaction_audit (id, user_id, transaction_id, action, changes, created_at) VALUES (?,?,?,?,?,?)`,
        [uuid(), before.user_id, id, "update", JSON.stringify(changes), ts],
      );
    });
  }

  async history(id: string): Promise<TransactionAudit[]> {
    return this.db.getAll<TransactionAudit>(
      "SELECT id, transaction_id, action, changes, created_at FROM transaction_audit WHERE transaction_id = ? ORDER BY created_at DESC",
      [id],
    );
  }
}

export class PowerSyncBalanceRepository implements BalanceRepository {
  constructor(private readonly db: AbstractPowerSyncDatabase) {}

  async accountBalance(accountId: string): Promise<Money> {
    const account = await this.db.getOptional<{ currency: CurrencyCode }>(
      "SELECT currency FROM accounts WHERE id = ?",
      [accountId],
    );
    if (!account) throw new Error(`Account ${accountId} not found`);
    // Pull every entry that could touch this account and derive the balance.
    const entries = await this.db.getAll<LedgerEntry>(
      `SELECT type, account_id, amount, to_account_id, to_amount FROM transactions
       WHERE deleted_at IS NULL AND (account_id = ? OR to_account_id = ?)`,
      [accountId, accountId],
    );
    return deriveBalance(accountId, account.currency, entries);
  }

  async netWorth(base: CurrencyCode, _includeBlocked: boolean): Promise<Money> {
    // Placeholder: full multi-account + FX aggregation lands in Phase 5.
    // Account-level balances (above) are correct today.
    return money(0, base);
  }
}

export class PowerSyncBudgetRepository implements BudgetRepository {
  constructor(private readonly db: AbstractPowerSyncDatabase) {}

  async list(): Promise<BudgetLike[]> {
    return this.db.getAll<BudgetLike>(
      "SELECT id, name, scope, scope_ref, category_ids, label_names, period, start_date, end_date, limit_amount, currency, threshold_pct FROM budgets WHERE deleted_at IS NULL",
    );
  }

  /** Sum of expenses in the budget's window (custom range or current period), honoring scope. */
  async spentThisPeriod(budget: BudgetLike, asOf = new Date()): Promise<Money> {
    let start: Date;
    let endExclusive: Date;
    if (budget.start_date && budget.end_date) {
      start = new Date(budget.start_date);
      // Make end inclusive of the whole end day.
      endExclusive = new Date(new Date(budget.end_date).getTime() + 86_400_000);
    } else {
      ({ start, endExclusive } = periodBounds(budget.period, asOf));
    }
    const where: string[] = [
      "type = 'expense'",
      "deleted_at IS NULL",
      "occurred_at >= ?",
      "occurred_at < ?",
      "currency = ?",
    ];
    const params: (string | number)[] = [
      start.toISOString(),
      endExclusive.toISOString(),
      budget.currency,
    ];
    // Multi-select categories/labels. Fall back to the legacy single scope_ref.
    const split = (s?: string | null) => (s ?? "").split(",").map((x) => x.trim()).filter(Boolean);
    const catIds = split(budget.category_ids);
    const labelNames = split(budget.label_names);
    if (catIds.length === 0 && labelNames.length === 0 && budget.scope_ref) {
      if (budget.scope === "category") catIds.push(budget.scope_ref);
      else if (budget.scope === "label") labelNames.push(budget.scope_ref);
    }

    const ors: string[] = [];
    if (catIds.length) {
      ors.push(`category_id IN (${catIds.map(() => "?").join(",")})`);
      params.push(...catIds);
    }
    for (const n of labelNames) {
      // Transactions may carry multiple comma-joined labels — match a whole token.
      ors.push("(label = ? OR label LIKE ? OR label LIKE ? OR label LIKE ?)");
      params.push(n, `${n}, %`, `%, ${n}`, `%, ${n}, %`);
    }
    if (ors.length) where.push(`(${ors.join(" OR ")})`);
    // No categories/labels selected → overall (all expenses).
    const row = await this.db.get<{ total: number | null }>(
      `SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE ${where.join(" AND ")}`,
      params,
    );
    return money(row.total ?? 0, budget.currency);
  }
}

export class PowerSyncCreditCardRepository implements CreditCardRepository {
  constructor(
    private readonly db: AbstractPowerSyncDatabase,
    private readonly getUserId: () => string,
    private readonly transactions: PowerSyncTransactionRepository,
  ) {}

  async getDetails(accountId: string): Promise<CreditCardDetails | null> {
    return this.db.getOptional<CreditCardDetails>(
      "SELECT account_id, statement_day, due_day, credit_limit, card_last4 FROM credit_card_details WHERE account_id = ?",
      [accountId],
    );
  }

  async upsertDetails(details: CreditCardDetails): Promise<void> {
    const ts = nowIso();
    const last4 = details.card_last4 ?? null;
    const existing = await this.getDetails(details.account_id);
    if (existing) {
      await this.db.execute(
        "UPDATE credit_card_details SET statement_day = ?, due_day = ?, credit_limit = ?, card_last4 = ?, updated_at = ? WHERE account_id = ?",
        [details.statement_day, details.due_day, details.credit_limit, last4, ts, details.account_id],
      );
    } else {
      await this.db.execute(
        `INSERT INTO credit_card_details (id,user_id,account_id,statement_day,due_day,credit_limit,card_last4,created_at,updated_at)
         VALUES (?,?,?,?,?,?,?,?,?)`,
        [uuid(), this.getUserId(), details.account_id, details.statement_day, details.due_day, details.credit_limit, last4, ts, ts],
      );
    }
  }

  /** Settle the bill = record a transfer from the chosen account to the card. */
  async settle(input: {
    fromAccountId: string;
    cardAccountId: string;
    amount: Money;
    toAmount?: Money;
    occurredAt: string;
  }): Promise<void> {
    await this.transactions.create({
      account_id: input.fromAccountId,
      type: "transfer",
      amount: input.amount,
      to_account_id: input.cardAccountId,
      to_amount: input.toAmount ?? null,
      label: "Credit card settlement",
      occurred_at: input.occurredAt,
    });
  }
}
