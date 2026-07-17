"use client";

import { fromMajor } from "@pocketcare/money";
import { getDb, getRepositories } from "../powersync";
import { insertRow, nowIso } from "../write";
import { getBaseCurrency } from "../prefs";
import { createGroup } from "../splits/write";

/** Anthropic tool definitions the model may call. All are WRITE actions and
 * require explicit user confirmation before they run (handled by the chat UI). */
export const ASSISTANT_TOOLS = [
  {
    name: "create_goal",
    description:
      "Create a savings goal (e.g. for a purchase like an iPhone). Use the user's base currency unless they specify another.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Short goal name, e.g. 'iPhone 16'." },
        target_amount: { type: "number", description: "Target amount in major units (e.g. 79900 for ₹79,900)." },
        by_date: { type: "string", description: "Optional target date, ISO YYYY-MM-DD." },
        currency: { type: "string", description: "ISO currency code; defaults to the base currency." },
      },
      required: ["name", "target_amount"],
    },
  },
  {
    name: "reserve_to_goal",
    description: "Set aside (block) money from a savings account toward an existing goal.",
    input_schema: {
      type: "object",
      properties: {
        goal_name: { type: "string", description: "Name of the goal to reserve money for." },
        amount: { type: "number", description: "Amount to reserve, in major units." },
      },
      required: ["goal_name", "amount"],
    },
  },
  {
    name: "create_budget",
    description: "Create a spending budget with a monthly/weekly/etc. limit.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Budget name, e.g. 'Festival shopping'." },
        limit_amount: { type: "number", description: "Limit in major units." },
        period: { type: "string", enum: ["daily", "weekly", "monthly", "yearly"], description: "Recurring period." },
        currency: { type: "string", description: "ISO currency code; defaults to base currency." },
      },
      required: ["name", "limit_amount", "period"],
    },
  },
  {
    name: "record_transaction",
    description:
      "Record an income or expense the user tells you about (e.g. 'log ₹200 for coffee'). Books it on a real account (their named one, else the first account). Not for splitting bills with friends.",
    input_schema: {
      type: "object",
      properties: {
        type: { type: "string", enum: ["expense", "income"], description: "Whether money went out (expense) or came in (income)." },
        amount: { type: "number", description: "Amount in major units." },
        description: { type: "string", description: "Short description, e.g. 'Coffee'." },
        category: { type: "string", description: "Optional category name (matched to an existing category)." },
        account: { type: "string", description: "Optional account name to use; defaults to the first account." },
      },
      required: ["type", "amount"],
    },
  },
  {
    name: "create_subscription",
    description: "Add a recurring subscription (e.g. Netflix) so it's tracked in the user's monthly obligations.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Subscription name, e.g. 'Netflix'." },
        amount: { type: "number", description: "Amount per billing cycle, in major units." },
        billing_cycle: { type: "string", enum: ["daily", "weekly", "monthly", "yearly"], description: "Billing cycle." },
      },
      required: ["name", "amount", "billing_cycle"],
    },
  },
  {
    name: "create_group",
    description: "Create a split group or trip (for sharing expenses with friends). For a trip, include its dates. After creating, tell the user to invite people from Groups & trips → Invite.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Group/trip name, e.g. 'Goa'." },
        kind: { type: "string", enum: ["group", "trip"], description: "'trip' for a dated getaway, 'group' for an ongoing household/flatmates group." },
        start_date: { type: "string", description: "Trip start date, ISO YYYY-MM-DD (optional; for trips)." },
        end_date: { type: "string", description: "Trip end date, ISO YYYY-MM-DD (optional; for trips)." },
        auto_split: { type: "boolean", description: "If true (and dates are set), expenses added within the dates auto-split equally with the group." },
      },
      required: ["name", "kind"],
    },
  },
  {
    name: "remember",
    description:
      "Save ONE short, durable fact about the user for future chats (a lasting goal, preference, income cadence, or constraint). Use sparingly — not one-off details. Runs silently, no confirmation.",
    input_schema: {
      type: "object",
      properties: { fact: { type: "string", description: "One concise fact, under ~120 characters." } },
      required: ["fact"],
    },
  },
] as const;

export type ToolName = (typeof ASSISTANT_TOOLS)[number]["name"];
/** Financial writes that must be confirmed by the user before running. */
const CONFIRM_TOOLS = new Set(["create_goal", "reserve_to_goal", "create_budget", "record_transaction", "create_subscription", "create_group"]);
export const needsConfirm = (name: string): boolean => CONFIRM_TOOLS.has(name);

/**
 * Reject obviously-invalid / placeholder tool calls (e.g. the model firing
 * record_transaction with amount 0 for a navigation request). Invalid calls are
 * never surfaced as a confirm card — the model is told to use a link instead.
 */
export function isValidToolInput(name: string, input: Record<string, unknown>): boolean {
  const pos = (v: unknown) => typeof v === "number" && Number.isFinite(v) && v > 0;
  const str = (v: unknown) => typeof v === "string" && v.trim().length > 0;
  switch (name) {
    case "record_transaction": return pos(input.amount) && (input.type === "expense" || input.type === "income");
    case "create_goal": return str(input.name) && pos(input.target_amount);
    case "reserve_to_goal": return str(input.goal_name) && pos(input.amount);
    case "create_budget": return str(input.name) && pos(input.limit_amount);
    case "create_subscription": return str(input.name) && pos(input.amount);
    case "create_group": return str(input.name);
    default: return true;
  }
}

/** One-line, human-readable summary of a proposed action for the confirm card. */
export function describeToolCall(name: string, input: Record<string, unknown>): string {
  const cur = (input.currency as string) || getBaseCurrency();
  switch (name) {
    case "create_goal":
      return `Create goal “${input.name}” — target ${cur} ${input.target_amount}${input.by_date ? ` by ${input.by_date}` : ""}`;
    case "reserve_to_goal":
      return `Reserve ${cur} ${input.amount} toward “${input.goal_name}”`;
    case "create_budget":
      return `Create ${input.period} budget “${input.name}” — limit ${cur} ${input.limit_amount}`;
    case "record_transaction":
      return `Record ${input.type} of ${cur} ${input.amount}${input.description ? ` — ${input.description}` : ""}${input.account ? ` (${input.account})` : ""}`;
    case "create_subscription":
      return `Add subscription “${input.name}” — ${cur} ${input.amount}/${String(input.billing_cycle).replace("ly", "")}`;
    case "create_group":
      return `Create ${input.kind} “${input.name}”${input.start_date ? ` · ${input.start_date}${input.end_date ? `–${input.end_date}` : ""}` : ""}${input.auto_split ? " · auto-split" : ""}`;
    case "remember":
      return `Remembered: ${input.fact}`;
    default:
      return `Run ${name}`;
  }
}

/** Execute a confirmed tool call against local SQLite. Returns a result string. */
export async function executeTool(name: string, input: Record<string, unknown>): Promise<string> {
  const db = getDb();
  if (!db) return "Error: database not ready.";
  const base = getBaseCurrency();

  if (name === "create_goal") {
    const cur = (input.currency as string) || base;
    const id = await insertRow("goals", {
      name: String(input.name).trim(),
      target_amount: fromMajor(Number(input.target_amount) || 0, cur).amount,
      currency: cur,
      is_emergency_fund: 0,
      priority: 0,
      target_date: (input.by_date as string) || null,
    });
    return `Created goal "${input.name}" (id ${id}).`;
  }

  if (name === "create_budget") {
    const cur = (input.currency as string) || base;
    const id = await insertRow("budgets", {
      name: String(input.name).trim(),
      period: String(input.period),
      limit_amount: fromMajor(Number(input.limit_amount) || 0, cur).amount,
      currency: cur,
      threshold_pct: 80,
      rollover: 0,
    });
    return `Created budget "${input.name}" (id ${id}).`;
  }

  if (name === "reserve_to_goal") {
    const goal = await db.getOptional<{ id: string; currency: string }>(
      "SELECT id, currency FROM goals WHERE deleted_at IS NULL AND lower(name) = lower(?) LIMIT 1",
      [String(input.goal_name).trim()],
    );
    if (!goal) return `No goal named "${input.goal_name}" was found. Create it first.`;
    const src = await db.getOptional<{ id: string }>(
      "SELECT id FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND type IN ('savings','current','cash') ORDER BY created_at LIMIT 1",
    );
    if (!src) return "No savings/current/cash account to reserve from.";
    await insertRow("goal_allocations", {
      goal_id: goal.id,
      source_account_id: src.id,
      amount_blocked: fromMajor(Number(input.amount) || 0, goal.currency).amount,
    });
    return `Reserved ${goal.currency} ${input.amount} toward "${input.goal_name}".`;
  }

  if (name === "record_transaction") {
    const type = input.type === "income" ? "income" : "expense";
    let acct = input.account
      ? await db.getOptional<{ id: string; currency: string }>(
          "SELECT id, currency FROM accounts WHERE deleted_at IS NULL AND IFNULL(kind,'real')='real' AND lower(name) = lower(?) LIMIT 1",
          [String(input.account).trim()],
        )
      : null;
    if (!acct) acct = await db.getOptional<{ id: string; currency: string }>(
      "SELECT id, currency FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real' ORDER BY created_at LIMIT 1",
    );
    if (!acct) return "No account to record into — add an account first.";
    let categoryId: string | null = null;
    if (input.category) {
      const c = await db.getOptional<{ id: string }>("SELECT id FROM categories WHERE deleted_at IS NULL AND lower(name) = lower(?) LIMIT 1", [String(input.category).trim()]);
      categoryId = c?.id ?? null;
    }
    await getRepositories().transactions.create({
      account_id: acct.id, type, amount: fromMajor(Number(input.amount) || 0, acct.currency),
      category_id: categoryId, description: (input.description as string)?.trim() || null, occurred_at: nowIso(),
    });
    return `Recorded ${type} of ${acct.currency} ${input.amount}.`;
  }

  if (name === "create_subscription") {
    const id = await insertRow("subscriptions", {
      name: String(input.name).trim(),
      amount: fromMajor(Number(input.amount) || 0, base).amount,
      currency: base,
      billing_cycle: String(input.billing_cycle),
      purchased_on: null,
      next_renewal: null,
      is_active: 1,
    });
    return `Added subscription "${input.name}" (id ${id}).`;
  }

  if (name === "create_group") {
    const kind = input.kind === "trip" ? "trip" : "group";
    const start = (input.start_date as string) || null;
    const end = (input.end_date as string) || null;
    const id = await createGroup({
      name: String(input.name).trim(), kind, currency: base,
      startDate: start, endDate: end, autoSplit: Boolean(input.auto_split) && !!start && !!end,
    });
    return `Created ${kind} "${input.name}"${start ? ` (${start}${end ? `–${end}` : ""})` : ""} (id ${id}). Invite people from Groups & trips.`;
  }

  if (name === "remember") {
    const fact = String(input.fact || "").trim().slice(0, 200);
    if (!fact) return "Nothing to remember.";
    const existing = await db.getOptional<{ id: string; notes: string }>("SELECT id, notes FROM assistant_memory LIMIT 1");
    if (existing) {
      const notes = (existing.notes ? existing.notes + "\n" : "") + `- ${fact}`;
      await db.execute("UPDATE assistant_memory SET notes = ?, updated_at = ? WHERE id = ?", [notes.slice(-4000), nowIso(), existing.id]);
    } else {
      await insertRow("assistant_memory", { notes: `- ${fact}` });
    }
    return "Saved to memory.";
  }

  return `Unknown tool: ${name}`;
}

/** Load durable per-user memory (for the system prompt). */
export async function loadMemory(): Promise<string> {
  const db = getDb();
  if (!db) return "";
  const row = await db.getOptional<{ notes: string }>("SELECT notes FROM assistant_memory LIMIT 1");
  return (row?.notes ?? "").trim();
}
