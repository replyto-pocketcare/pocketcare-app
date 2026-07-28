"use server";

import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

// Service-role client: bypasses RLS. Scoped to the `pocketcare` schema so
// .from("profiles" | "transactions" | "subscriptions" | "bug_reports") resolve
// to the real app tables (they live in pocketcare, not public).
const getAdminClient = () => {
  if (!supabaseUrl) throw new Error("NEXT_PUBLIC_SUPABASE_URL is not set in this deployment.");
  if (!supabaseServiceKey) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not set in this deployment (add it in Vercel → Settings → Environment Variables).");
  return createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false },
    db: { schema: "pocketcare" },
  });
};

// Never throw across the server-action boundary — return the error as data so
// the page can render it instead of producing an opaque 500.
export type AdminResult<T> = { ok: true; data: T } | { ok: false; error: string };
const fail = (e: unknown): { ok: false; error: string } => ({
  ok: false,
  error: e instanceof Error ? e.message : String(e),
});

export interface AdminStats {
  totalUsers: number;
  activeSubscriptions: number;
  totalIncome: number;
  incomeByMonth: { month: string; income: number }[];
}

export async function getAdminDashboardStats(): Promise<AdminResult<AdminStats>> {
  try {
    const supabase = getAdminClient();
    const [usersRes, incomeRes, subsRes] = await Promise.all([
      supabase.from("profiles").select("*", { count: "exact", head: true }),
      supabase.from("transactions").select("amount").eq("type", "income").is("deleted_at", null),
      // subscriptions uses `is_active` (boolean) + soft delete — no `status` column.
      supabase.from("subscriptions").select("*", { count: "exact", head: true }).eq("is_active", true).is("deleted_at", null),
    ]);
    const err = usersRes.error || incomeRes.error || subsRes.error;
    if (err) throw new Error(err.message);
    return {
      ok: true,
      data: {
        totalUsers: usersRes.count ?? 0,
        activeSubscriptions: subsRes.count ?? 0,
        totalIncome: (incomeRes.data ?? []).reduce((acc, tx) => acc + (Number(tx.amount) || 0), 0),
        incomeByMonth: [],
      },
    };
  } catch (e) {
    return fail(e);
  }
}

export async function getAdminUsers(): Promise<AdminResult<Record<string, unknown>[]>> {
  try {
    const supabase = getAdminClient();
    const { data, error } = await supabase
      .from("profiles")
      .select("id, display_name, email, rate_mode, base_currency");
    if (error) throw new Error(error.message);
    return { ok: true, data: data ?? [] };
  } catch (e) {
    return fail(e);
  }
}

export async function getAdminFeedback(): Promise<AdminResult<Record<string, unknown>[]>> {
  try {
    const supabase = getAdminClient();
    const { data: reports, error } = await supabase
      .from("bug_reports")
      .select("*")
      .order("created_at", { ascending: false });
    if (error) throw new Error(error.message);

    const rows = reports ?? [];
    // Resolve reporter name/email — bug_reports.user_id references auth.users,
    // so there's no automatic PostgREST embed; look the profiles up separately.
    const ids = [...new Set(rows.map((r) => r.user_id).filter(Boolean))];
    const byId = new Map<string, { display_name?: string; email?: string }>();
    if (ids.length) {
      const { data: profs } = await supabase
        .from("profiles")
        .select("id, display_name, email")
        .in("id", ids);
      for (const p of profs ?? []) byId.set(p.id as string, p);
    }

    const enriched = rows.map((r) => {
      const p = byId.get(r.user_id as string);
      return {
        ...r,
        reporter_name: p?.display_name ?? null,
        reporter_email: p?.email ?? null,
      };
    });
    return { ok: true, data: enriched };
  } catch (e) {
    return fail(e);
  }
}

export interface AdminClientError {
  id: string;
  fingerprint: string;
  level: string;
  scope: string | null;
  message: string;
  detail: Record<string, unknown> | null;
  route: string | null;
  app_version: string | null;
  platform: string | null;
  count: number;
  first_seen: string;
  last_seen: string;
  resolved_at: string | null;
  /** How many distinct users hit this — the number that says "how bad is it". */
  affected_users: number;
}

/**
 * Auto-reported client errors, grouped by fingerprint.
 *
 * Rows are per (fingerprint, user); this collapses them so one bug is one line
 * with a total count and an affected-user count, which is what you triage on.
 */
export async function getAdminClientErrors(includeResolved = false): Promise<AdminResult<AdminClientError[]>> {
  try {
    const supabase = getAdminClient();
    let q = supabase
      .from("client_errors")
      .select("*")
      .order("last_seen", { ascending: false })
      .limit(500);
    if (!includeResolved) q = q.is("resolved_at", null);
    const { data, error } = await q;
    if (error) throw new Error(error.message);

    const grouped = new Map<string, AdminClientError>();
    for (const r of data ?? []) {
      const row = r as Record<string, unknown>;
      const fp = String(row.fingerprint);
      const existing = grouped.get(fp);
      if (existing) {
        existing.count += Number(row.count) || 0;
        existing.affected_users += 1;
        if (String(row.last_seen) > existing.last_seen) existing.last_seen = String(row.last_seen);
        if (String(row.first_seen) < existing.first_seen) existing.first_seen = String(row.first_seen);
      } else {
        grouped.set(fp, {
          id: String(row.id),
          fingerprint: fp,
          level: String(row.level ?? "error"),
          scope: (row.scope as string) ?? null,
          message: String(row.message ?? ""),
          detail: (row.detail as Record<string, unknown>) ?? null,
          route: (row.route as string) ?? null,
          app_version: (row.app_version as string) ?? null,
          platform: (row.platform as string) ?? null,
          count: Number(row.count) || 0,
          first_seen: String(row.first_seen),
          last_seen: String(row.last_seen),
          resolved_at: (row.resolved_at as string) ?? null,
          affected_users: 1,
        });
      }
    }
    return { ok: true, data: [...grouped.values()].sort((a, b) => (a.last_seen < b.last_seen ? 1 : -1)) };
  } catch (e) {
    return fail(e);
  }
}

/** Mark every row of a fingerprint resolved. It re-opens automatically if it recurs. */
export async function resolveAdminClientError(fingerprint: string, note?: string): Promise<AdminResult<true>> {
  try {
    const supabase = getAdminClient();
    const { error } = await supabase
      .from("client_errors")
      .update({ resolved_at: new Date().toISOString(), resolved_note: note ?? null })
      .eq("fingerprint", fingerprint);
    if (error) throw new Error(error.message);
    return { ok: true, data: true };
  } catch (e) {
    return fail(e);
  }
}

export interface AdminErrorUser {
  user_id: string | null;
  name: string;
  email: string | null;
  count: number;
  first_seen: string;
  last_seen: string;
  platform: string | null;
  route: string | null;
  app_version: string | null;
}

/**
 * Who is hitting one specific error.
 *
 * The grouped list answers "how bad is it"; this answers "who do I contact"
 * and "what do they have in common" — the platform/version columns are usually
 * where the pattern shows up.
 */
export async function getAdminClientErrorUsers(fingerprint: string): Promise<AdminResult<AdminErrorUser[]>> {
  try {
    const supabase = getAdminClient();
    const { data, error } = await supabase
      .from("client_errors")
      .select("user_id, count, first_seen, last_seen, platform, route, app_version")
      .eq("fingerprint", fingerprint)
      .order("last_seen", { ascending: false });
    if (error) throw new Error(error.message);

    const rows = data ?? [];
    const ids = [...new Set(rows.map((r) => r.user_id).filter(Boolean))] as string[];
    const byId = new Map<string, { display_name?: string; email?: string }>();
    if (ids.length) {
      const { data: profs } = await supabase
        .from("profiles")
        .select("id, display_name, email")
        .in("id", ids);
      for (const p of profs ?? []) byId.set(p.id as string, p);
    }

    return {
      ok: true,
      data: rows.map((r) => {
        const prof = r.user_id ? byId.get(r.user_id as string) : undefined;
        return {
          user_id: (r.user_id as string) ?? null,
          // Deleted accounts keep their error rows with a null user_id (0044).
          name: prof?.display_name || prof?.email?.split("@")[0] || (r.user_id ? "Unknown user" : "Deleted account"),
          email: prof?.email ?? null,
          count: Number(r.count) || 0,
          first_seen: String(r.first_seen),
          last_seen: String(r.last_seen),
          platform: (r.platform as string) ?? null,
          route: (r.route as string) ?? null,
          app_version: (r.app_version as string) ?? null,
        };
      }),
    };
  } catch (e) {
    return fail(e);
  }
}
