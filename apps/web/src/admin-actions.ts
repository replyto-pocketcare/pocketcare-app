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
