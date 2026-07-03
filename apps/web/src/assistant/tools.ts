"use client";

import { fromMajor } from "@pocketcare/money";
import { getDb } from "../powersync";
import { insertRow } from "../write";
import { getBaseCurrency } from "../prefs";

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
] as const;

export type ToolName = (typeof ASSISTANT_TOOLS)[number]["name"];
export const isWriteTool = (name: string): boolean => ASSISTANT_TOOLS.some((t) => t.name === name);

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

  return `Unknown tool: ${name}`;
}
