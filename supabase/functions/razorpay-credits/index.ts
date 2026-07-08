// Create a one-time Razorpay ORDER to buy an AI credit pack. The webhook adds
// the credits to the user's entitlements once the payment is captured.
// Secrets: RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET
// Deploy: supabase functions deploy razorpay-credits
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { ...CORS, "content-type": "application/json" } });

// Keep in sync with apps/web/src/billing/plans.ts CREDIT_PACKS.
const PACKS: Record<string, { paise: number; credits: number }> = {
  p50: { paise: 2900, credits: 50 },
  p100: { paise: 4900, credits: 100 },
  p250: { paise: 9900, credits: 250 },
};

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

  let body: { pack?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body." }); }
  const pack = body.pack ? PACKS[body.pack] : undefined;
  if (!pack) return json({ error: "Unknown credit pack." });

  const rzpRes = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: "Basic " + btoa(`${keyId}:${keySecret}`) },
    body: JSON.stringify({
      amount: pack.paise,
      currency: "INR",
      notes: { user_id: user.id, kind: "credits", credits: String(pack.credits) },
    }),
  });
  const order = await rzpRes.json();
  if (!rzpRes.ok || order.error) return json({ error: order?.error?.description || `Razorpay error (${rzpRes.status}).` });

  return json({ order_id: order.id, amount: pack.paise, credits: pack.credits, key_id: keyId });
});
