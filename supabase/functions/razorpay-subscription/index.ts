// Create a Razorpay recurring SUBSCRIPTION for the signed-in user.
// The webhook (razorpay-webhook) is authoritative for activating the plan.
//
// Secrets required:
//   RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET
//   RZP_PLAN_LITE_MONTHLY, RZP_PLAN_LITE_YEARLY, RZP_PLAN_PRO_MONTHLY, RZP_PLAN_PRO_YEARLY
// Deploy: supabase functions deploy razorpay-subscription
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { ...CORS, "content-type": "application/json" } });

const planEnv = (tier: string, cycle: string) => Deno.env.get(`RZP_PLAN_${tier.toUpperCase()}_${cycle.toUpperCase()}`);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" });

  const auth = req.headers.get("Authorization");
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!auth) return json({ error: "Missing Authorization header" });
  {
    const missing = [!keyId && "RAZORPAY_KEY_ID", !keySecret && "RAZORPAY_KEY_SECRET"].filter(Boolean);
    if (missing.length) return json({ error: `Razorpay not configured — this function can't see: ${missing.join(", ")}. Set via 'supabase secrets set', then redeploy this function.` });
  }
  if (!supabaseUrl || !serviceKey) return json({ error: "Supabase environment not configured." });

  const supabase = createClient(supabaseUrl, serviceKey, { db: { schema: "pocketcare" } });
  const { data: { user }, error: authErr } = await supabase.auth.getUser(auth.replace("Bearer ", ""));
  if (authErr || !user) return json({ error: "Unauthorized" });

  let body: { tier?: string; cycle?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body." }); }
  const tier = body.tier === "pro" ? "pro" : body.tier === "lite" ? "lite" : "";
  const cycle = body.cycle === "yearly" ? "yearly" : body.cycle === "monthly" ? "monthly" : "";
  if (!tier || !cycle) return json({ error: "tier (lite|pro) and cycle (monthly|yearly) are required." });

  const planId = planEnv(tier, cycle);
  if (!planId) return json({ error: `No Razorpay Plan ID configured for ${tier}/${cycle}.` });

  const totalCount = cycle === "yearly" ? 10 : 120; // ~10y horizon; Razorpay requires a count
  const rzpRes = await fetch("https://api.razorpay.com/v1/subscriptions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: "Basic " + btoa(`${keyId}:${keySecret}`) },
    body: JSON.stringify({
      plan_id: planId,
      total_count: totalCount,
      quantity: 1,
      customer_notify: 1,
      notes: { user_id: user.id, tier, cycle },
    }),
  });
  const sub = await rzpRes.json();
  if (!rzpRes.ok || sub.error) return json({ error: sub?.error?.description || `Razorpay error (${rzpRes.status}).` });

  // Record the pending subscription (webhook flips it to active on payment).
  // Upsert so a missing entitlements row is created rather than silently skipped.
  await supabase.from("entitlements").upsert({
    user_id: user.id, razorpay_subscription_id: sub.id, plan_id: planId, billing_cycle: cycle, subscription_status: "created",
  }, { onConflict: "user_id" });

  return json({ subscription_id: sub.id, key_id: keyId });
});
