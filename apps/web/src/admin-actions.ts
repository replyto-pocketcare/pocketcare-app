"use server";

import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

// Service-role client: bypasses RLS. Scoped to the `pocketcare` schema so
// .from("profiles" | "transactions" | "subscriptions" | "bug_reports") resolve
// to the real app tables (they live in pocketcare, not public).
export const getAdminClient = () => {
  return createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
      persistSession: false,
    },
    db: { schema: "pocketcare" },
  });
};

// Admin Server Actions

export async function getAdminDashboardStats() {
  const supabase = getAdminClient();

  const [usersRes, incomeRes, subsRes] = await Promise.all([
    supabase.from("profiles").select("*", { count: "exact", head: true }),
    supabase.from("transactions").select("amount").eq("type", "income").is("deleted_at", null),
    // subscriptions has `is_active` (boolean) + soft-delete — there is no `status` column.
    supabase.from("subscriptions").select("*", { count: "exact", head: true }).eq("is_active", true).is("deleted_at", null),
  ]);

  const firstError = usersRes.error || incomeRes.error || subsRes.error;
  if (firstError) throw new Error(firstError.message);

  return {
    totalUsers: usersRes.count ?? 0,
    activeSubscriptions: subsRes.count ?? 0,
    totalIncome: (incomeRes.data ?? []).reduce((acc, tx) => acc + (tx.amount ?? 0), 0),
    incomeByMonth: [] as { month: string; income: number }[],
  };
}

export async function getAdminUsers() {
  const supabase = getAdminClient();
  const { data: users, error } = await supabase.from("profiles").select("id, display_name, email, rate_mode, base_currency");
  if (error) throw new Error(error.message);
  return users;
}

export async function getAdminFeedback() {
  const supabase = getAdminClient();
  const { data: feedback, error } = await supabase.from("bug_reports").select("*").order("created_at", { ascending: false });
  if (error) throw new Error(error.message);
  return feedback;
}
