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
import { AppSchema, SupabaseConnector, createSupabaseClient } from "@pocketcare/db";
import {
  PowerSyncAccountRepository,
  PowerSyncTransactionRepository,
  PowerSyncBalanceRepository,
  PowerSyncBudgetRepository,
  PowerSyncCreditCardRepository,
} from "@pocketcare/data";

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
    // NOTE: filename bumped to -v2 to discard local databases poisoned by the
    // old client-side seeding (duplicate default labels that blocked the upload
    // queue with a labels_user_id_name_key violation). A fresh local DB re-syncs
    // cleanly from the server, which is now the sole seeder.
    _db = new PowerSyncDatabase({
      schema: AppSchema,
      database: { dbFilename: "pocketcare-v2.db" },
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
    const connector = new SupabaseConnector(
      supabase,
      requireEnv("NEXT_PUBLIC_POWERSYNC_URL", POWERSYNC_URL),
    );
    await db.init();

    // Do NOT auto-create a guest. Only connect if the user already has a
    // session (registered OR an explicit guest they chose earlier). A brand-new
    // visitor stays unauthenticated and is routed to onboarding to pick a path:
    // create account, sign in, or explicitly "try as guest".
    const { data: { session } } = await supabase.auth.getSession();
    currentUserId = session?.user?.id ?? "";
    // Connect in the BACKGROUND — never block first paint on it. If the network
    // or PowerSync is slow/unreachable (or, in an installed PWA, the DB worker is
    // still warming up), the UI must still load from local SQLite instead of
    // hanging on the loading spinner forever.
    if (currentUserId) {
      void db.connect(connector).catch((err) => console.error("[PocketCare] connect failed:", err));
    }

    // Re-key the local DB whenever the signed-in identity changes.
    // Critical for multi-device: the app boots as an anonymous guest, so after
    // signing in (a client-side nav, not a reload) we must switch PowerSync to
    // the real user, clear the guest's local data, and reconnect so the account
    // downloads under the new JWT. Same-UID guest→register (updateUser) keeps the
    // id, so we do NOT clear then (preserving not-yet-synced local writes).
    let rekeying: Promise<void> = Promise.resolve();
    supabase.auth.onAuthStateChange((event, sess) => {
      const newId = sess?.user?.id ?? "";
      if (event === "SIGNED_OUT") {
        rekeying = rekeying.then(async () => {
          currentUserId = "";
          await db.disconnectAndClear().catch(() => {});
        });
        return;
      }
      if (newId && newId !== currentUserId) {
        rekeying = rekeying.then(async () => {
          currentUserId = newId;
          await db.disconnectAndClear().catch(() => {});
          await db.connect(connector);
        });
      }
    });

    return db;
  })();
  return started;
}

/** Forces a sync by disconnecting and reconnecting with a fresh connector. */
export async function forceSync(): Promise<void> {
  const db = getDb();
  if (!db || !currentUserId || !_supabase) return;
  const connector = new SupabaseConnector(
    _supabase,
    process.env.NEXT_PUBLIC_POWERSYNC_URL || POWERSYNC_URL!
  );
  try { await db.disconnect(); } catch {}
  try { await db.connect(connector); } catch (err) {
    console.error("[PocketCare] Force connect failed:", err);
  }
}
