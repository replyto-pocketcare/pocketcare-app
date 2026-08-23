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

  const supabase = createClient(supabaseUrl, serviceKey, { db: { schema: "pocketcare" } });
  const { data: { user }, error: authErr } = await supabase.auth.getUser(auth.replace("Bearer ", ""));
  if (authErr || !user) return json({ error: "Unauthorized" });

  const { data: ent } = await supabase
    .from("entitlements")
    .select("razorpay_subscription_id, purchased_quota_remaining, additional_purchased_quota")
    .eq("user_id", user.id).single();
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

  const endsAt = sub.current_end ? new Date(sub.current_end * 1000).toISOString() : null;

  // Reassure, rather than alarm, if they still hold unspent purchased credits.
  //
  // Raised HERE rather than in the client so it survives the tab being closed
  // the moment after cancelling, and so it is written with the service role
  // (the client cannot insert notifications for itself).
  //
  // Wording is deliberately precise. The downgrade sets tier=free and
  // monthly_quota_total=0; it does NOT clear purchased_quota_remaining, and the
  // assistant/receipt-scan functions spend against quota, not tier. The credits
  // therefore survive — what disappears is the ability to reach the assistant,
  // which is gated to paid plans. Telling someone their pre-paid credits are
  // destroyed, at the moment they cancel, would be a false statement about
  // their own money.
  //
  // Wrapped in try/catch on purpose: by this point Razorpay has ALREADY
  // cancelled the subscription. Letting a failed notification throw would
  // return an error for an operation that actually succeeded, and the user
  // would try again against a subscription that no longer exists. The dedupe
  // index is also partial (0037: `where dedupe_key is not null and deleted_at
  // is null`), which PostgREST's onConflict inference may not match — one more
  // reason this must not be load-bearing.
  const credits = (ent?.purchased_quota_remaining ?? 0) + (ent?.additional_purchased_quota ?? 0);
  if (credits > 0) {
    try {
      const plural = credits === 1 ? "" : "s";
      const when = endsAt
        ? new Date(endsAt).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })
        : "your plan ends";
      await supabase.from("notifications").upsert({
        user_id: user.id,
        kind: "system",
        severity: "warn",
        title: `Your ${credits} AI credit${plural} ${credits === 1 ? "is" : "are"} safe`,
        subtitle: `Kept for whenever you upgrade`,
        body:
          `Your plan ends ${when}. Your ${credits} purchased AI credit${plural} don't expire and stay on your ` +
          `account — nothing is lost. AI features need a paid plan, so you won't be able to spend them while ` +
          `you're on Free, but they'll be waiting exactly as they are whenever you upgrade again.`,
        href: "/settings",
        // Keyed to this subscription + end date so a cancel/resubscribe/cancel
        // cycle notifies once per actual ending, not once per button press.
        dedupe_key: `plan-cancel:${subId}:${endsAt ?? "unknown"}`,
      }, { onConflict: "user_id,dedupe_key", ignoreDuplicates: true });
    } catch (e) {
      console.error("cancel notification failed (cancellation itself succeeded):", e);
    }
  }

  return json({ ok: true, ends_at: endsAt, credits_at_risk: credits });
});
