/**
 * Web PowerSync system — SQLite compiled to WASM in the browser.
 *
 * IMPORTANT: PowerSync web must NEVER be instantiated during SSR (it has no
 * WASM/Worker environment on the server, and initialize() crashes). Everything
 * here is created lazily and only in the browser. The DB-bound UI is gated
 * behind the client provider until `initSystem()` resolves.
 */
import type { AbstractPowerSyncDatabase } from "@powersync/common";
import { PowerSyncDatabase } from "@powersync/web";
import type { SupabaseClient } from "@supabase/supabase-js";
import { AppSchema, SupabaseConnector, createSupabaseClient, ensureUser } from "@pocketcare/db";
import {
  PowerSyncAccountRepository,
  PowerSyncTransactionRepository,
  PowerSyncBalanceRepository,
  PowerSyncBudgetRepository,
  PowerSyncCreditCardRepository,
} from "@pocketcare/data";
import { seedDefaultsIfEmpty } from "./defaults";

const isBrowser = typeof window !== "undefined";

// These MUST be static `process.env.NEXT_PUBLIC_*` references so Next inlines
// them into the browser bundle. Dynamic access (process.env[key]) is NOT inlined.
// Prefer the new publishable key; fall back to the legacy anon key.
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const POWERSYNC_URL = process.env.NEXT_PUBLIC_POWERSYNC_URL;

function requireEnv(name: string, value: string | undefined): string {
  if (!value) throw new Error(`Missing env ${name}`);
  return value;
}

let _db: AbstractPowerSyncDatabase | null = null;
let _supabase: SupabaseClient | null = null;
let currentUserId = "";
export const getUserId = () => currentUserId;

/** The Supabase client (available after initSystem). Used by auth screens. */
export function getSupabase(): SupabaseClient {
  if (!_supabase) throw new Error("Supabase not initialized yet");
  return _supabase;
}

/** Lazily create the browser-only DB. Returns null on the server. */
export function getDb(): AbstractPowerSyncDatabase | null {
  if (!isBrowser) return null;
  if (!_db) {
    _db = new PowerSyncDatabase({
      schema: AppSchema,
      database: { dbFilename: "pocketcare.db" },
    });
  }
  return _db;
}

type Repos = {
  accounts: PowerSyncAccountRepository;
  transactions: PowerSyncTransactionRepository;
  balances: PowerSyncBalanceRepository;
  budgets: PowerSyncBudgetRepository;
  creditCards: PowerSyncCreditCardRepository;
};

let _repos: Repos | null = null;
function buildRepos(db: AbstractPowerSyncDatabase): Repos {
  const transactionRepo = new PowerSyncTransactionRepository(db, getUserId);
  return {
    accounts: new PowerSyncAccountRepository(db, getUserId),
    transactions: transactionRepo,
    balances: new PowerSyncBalanceRepository(db),
    budgets: new PowerSyncBudgetRepository(db),
    creditCards: new PowerSyncCreditCardRepository(db, getUserId, transactionRepo),
  };
}

/** Repositories, lazily built in the browser after the DB exists. */
export function getRepositories(): Repos {
  const db = getDb();
  if (!db) throw new Error("Repositories are only available in the browser");
  if (!_repos) _repos = buildRepos(db);
  return _repos;
}

let started: Promise<AbstractPowerSyncDatabase> | null = null;
/** Idempotent client-side boot: anonymous session + connect sync. */
export function initSystem(): Promise<AbstractPowerSyncDatabase> {
  if (started) return started;
  started = (async () => {
    const db = getDb();
    if (!db) throw new Error("initSystem must run in the browser");
    const supabase = createSupabaseClient({
      url: requireEnv("NEXT_PUBLIC_SUPABASE_URL", SUPABASE_URL),
      anonKey: requireEnv("NEXT_PUBLIC_SUPABASE_(PUBLISHABLE|ANON)_KEY", SUPABASE_KEY),
    });
    _supabase = supabase;
    currentUserId = await ensureUser(supabase);
    const connector = new SupabaseConnector(
      supabase,
      requireEnv("NEXT_PUBLIC_POWERSYNC_URL", POWERSYNC_URL),
    );
    await db.init();
    await db.connect(connector);
    // Fallback: ensure default categories/labels exist (non-blocking).
    void seedDefaultsIfEmpty(db, currentUserId).catch(() => {});
    return db;
  })();
  return started;
}
