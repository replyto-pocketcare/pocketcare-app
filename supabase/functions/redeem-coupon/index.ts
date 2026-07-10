// Redeem a reward coupon → grant a time-bound complimentary Lite/Pro plan.
// Coupons are strictly per-user and expire; redemption is one-time. No charge.
// Deploy: supabase functions deploy redeem-coupon
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });
const RANK: Record<string, number> = { free: 0, lite: 1, pro: 2 };

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!auth) return json({ error: "Missing Authorization header" }, 401);
  if (!url || !serviceKey) return json({ error: "Supabase environment not configured." }, 500);

  const db = createClient(url, serviceKey, { db: { schema: "pocketcare" } });
  const { data: { user }, error: authErr } = await db.auth.getUser(auth.replace("Bearer ", ""));
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

  let body: { code?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body." }, 400); }
  const code = (body.code ?? "").trim().toUpperCase();
  if (!code) return json({ error: "Enter a coupon code." }, 400);

  const { data: coupon } = await db.from("coupons").select("*").eq("code", code).eq("user_id", user.id).maybeSingle();
  const c = coupon as null | { id: string; tier: string; months: number; expires_at: string; redeemed_at: string | null };
  if (!c) return json({ error: "That coupon isn't valid for your account." }, 400);
  if (c.redeemed_at) return json({ error: "This coupon has already been redeemed." }, 400);
  if (new Date(c.expires_at).getTime() < Date.now()) return json({ error: "This coupon has expired." }, 400);

  // Extend from the later of now / any active comp; pick the higher tier.
  const { data: ent } = await db.from("entitlements").select("comp_tier, comp_until").eq("user_id", user.id).maybeSingle();
  const e = ent as null | { comp_tier: string | null; comp_until: string | null };
  const activeUntil = e?.comp_until && new Date(e.comp_until).getTime() > Date.now() ? new Date(e.comp_until).getTime() : Date.now();
  const until = new Date(activeUntil + c.months * 30 * 86_400_000).toISOString();
  const currentComp = e?.comp_tier && new Date(e?.comp_until ?? 0).getTime() > Date.now() ? e.comp_tier : "free";
  const tier = (RANK[c.tier] ?? 0) >= (RANK[currentComp] ?? 0) ? c.tier : currentComp;

  const { error: upErr } = await db.from("entitlements").upsert(
    { user_id: user.id, comp_tier: tier, comp_until: until, updated_at: new Date().toISOString() },
    { onConflict: "user_id" },
  );
  if (upErr) return json({ error: upErr.message }, 500);

  await db.from("coupons").update({ redeemed_at: new Date().toISOString(), applied_until: until }).eq("id", c.id);
  return json({ ok: true, tier, until });
});
