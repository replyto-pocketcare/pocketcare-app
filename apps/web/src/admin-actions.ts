"use server";

import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

// This client bypasses RLS and can query any schema
export const getAdminClient = () => {
  return createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
      persistSession: false,
    },
  });
};

// Admin Server Actions

export async function getAdminDashboardStats() {
  const supabase = getAdminClient();
  
  // Example stats: we can query the public schema tables for total users, subscriptions, etc.
  const [{ count: totalUsers }, { data: incomeData }, { data: activeSubs }] = await Promise.all([
    supabase.from("profiles").select("*", { count: "exact", head: true }),
    supabase.from("transactions").select("amount, occurred_at").eq("type", "income"), // Just a basic aggregate
    supabase.from("subscriptions").select("*").in("status", ["active", "trialing"]),
  ]);

  return {
    totalUsers: totalUsers || 0,
    activeSubscriptions: activeSubs?.length || 0,
    totalIncome: incomeData?.reduce((acc, tx) => acc + tx.amount, 0) || 0,
    // Add logic to group income by month for charts
    incomeByMonth: [] // Placeholder
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
