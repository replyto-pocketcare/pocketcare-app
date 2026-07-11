// Redeem a reward coupon OR a shared promo code → time-bound complimentary
// Lite/Pro plan. Per-user coupons (from bug-report rewards) are one-time and
// user-bound; shared promos (e.g. BETA_TESTER) are redeemable once per user
// within their window. No charge either way.
// Deploy: supabase functions deploy redeem-coupon
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });
const RANK: Record<string, number> = { free: 0, lite: 1, pro: 2 };

/** Grant/extend a time-bound complimentary tier from the apply date. */
async function applyComp(db: SupabaseClient, userId: string, tier: string, months: number) {
  const { data: ent } = await db.from("entitlements").select("comp_tier, comp_until").eq("user_id", userId).maybeSingle();
  const e = ent as null | { comp_tier: string | null; comp_until: string | null };
  const activeUntil = e?.comp_until && new Date(e.comp_until).getTime() > Date.now() ? new Date(e.comp_until).getTime() : Date.now();
  const until = new Date(activeUntil + months * 30 * 86_400_000).toISOString();
  const currentComp = e?.comp_tier && new Date(e?.comp_until ?? 0).getTime() > Date.now() ? e.comp_tier : "free";
  const finalTier = (RANK[tier] ?? 0) >= (RANK[currentComp] ?? 0) ? tier : currentComp;
  await db.from("entitlements").upsert({ user_id: userId, comp_tier: finalTier, comp_until: until, updated_at: new Date().toISOString() }, { onConflict: "user_id" });
  return { tier: finalTier, until };
}

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

  // 1) Per-user reward coupon.
  const { data: coupon } = await db.from("coupons").select("*").eq("code", code).eq("user_id", user.id).maybeSingle();
  const c = coupon as null | { id: string; tier: string; months: number; expires_at: string; redeemed_at: string | null };
  if (c) {
    if (c.redeemed_at) return json({ error: "This coupon has already been redeemed." }, 400);
    if (new Date(c.expires_at).getTime() < Date.now()) return json({ error: "This coupon has expired." }, 400);
    const r = await applyComp(db, user.id, c.tier, c.months);
    await db.from("coupons").update({ redeemed_at: new Date().toISOString(), applied_until: r.until }).eq("id", c.id);
    return json({ ok: true, ...r });
  }

  // 2) Shared promo code (e.g. BETA_TESTER).
  const { data: promo } = await db.from("promo_codes").select("*").eq("code", code).maybeSingle();
  const p = promo as null | { code: string; tier: string; months: number; active: boolean; starts_at: string | null; ends_at: string | null; max_redemptions: number | null; redeemed_count: number };
  if (!p) return json({ error: "That code isn't valid." }, 400);
  const now = Date.now();
  if (!p.active) return json({ error: "This code is no longer active." }, 400);
  if (p.starts_at && new Date(p.starts_at).getTime() > now) return json({ error: "This code isn't active yet." }, 400);
  if (p.ends_at && new Date(p.ends_at).getTime() < now) return json({ error: "This code has expired." }, 400);
  if (p.max_redemptions != null && p.redeemed_count >= p.max_redemptions) return json({ error: "This code has reached its redemption limit." }, 400);

  const { data: existing } = await db.from("promo_redemptions").select("id").eq("code", code).eq("user_id", user.id).maybeSingle();
  if (existing) return json({ error: "You've already used this code." }, 400);

  const r = await applyComp(db, user.id, p.tier, p.months);
  const { error: insErr } = await db.from("promo_redemptions").insert({ code, user_id: user.id, applied_until: r.until });
  if (insErr) return json({ error: insErr.message }, 500);
  await db.from("promo_codes").update({ redeemed_count: p.redeemed_count + 1 }).eq("code", code);
  return json({ ok: true, ...r });
});
