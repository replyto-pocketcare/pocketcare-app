// Cancel the signed-in user's Razorpay subscription at the end of the current
// cycle (they keep access until then). The webhook flips them to Free when it
// actually cancels.
// Secrets: RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET
// Deploy: supabase functions deploy razorpay-cancel
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { ...CORS, "content-type": "application/json" } });

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

  const supabase = createClient(supabaseUrl, serviceKey);
  const { data: { user }, error: authErr } = await supabase.auth.getUser(auth.replace("Bearer ", ""));
  if (authErr || !user) return json({ error: "Unauthorized" });

  const { data: ent } = await supabase
    .from("entitlements").select("razorpay_subscription_id").eq("user_id", user.id).single();
  const subId = ent?.razorpay_subscription_id;
  if (!subId) return json({ error: "No active subscription to cancel." });

  const rzpRes = await fetch(`https://api.razorpay.com/v1/subscriptions/${subId}/cancel`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: "Basic " + btoa(`${keyId}:${keySecret}`) },
    body: JSON.stringify({ cancel_at_cycle_end: 1 }),
  });
  const sub = await rzpRes.json();
  if (!rzpRes.ok || sub.error) return json({ error: sub?.error?.description || `Razorpay error (${rzpRes.status}).` });

  // Mark as cancelling; access continues until current_period_end, then the
  // subscription.cancelled webhook downgrades to Free.
  await supabase.from("entitlements").update({ subscription_status: "cancelling" }).eq("user_id", user.id);

  return json({ ok: true, ends_at: sub.current_end ? new Date(sub.current_end * 1000).toISOString() : null });
});
