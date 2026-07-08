// Razorpay webhook — the AUTHORITATIVE source for plan/credit changes.
// Verifies the signature, then updates entitlements/payments with the service role.
//
// Secrets: RAZORPAY_WEBHOOK_SECRET, and the RZP_PLAN_* ids (to map plan → tier).
// Deploy WITHOUT jwt: supabase functions deploy razorpay-webhook --no-verify-jwt
// Configure the same URL + secret in the Razorpay dashboard (subscription.* and
// order.paid / payment.captured events).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const QUOTA: Record<string, number> = { lite: 50, pro: 200 };

function planToTier(): Record<string, string> {
  const map: Record<string, string> = {};
  for (const tier of ["lite", "pro"]) {
    for (const cycle of ["MONTHLY", "YEARLY"]) {
      const id = Deno.env.get(`RZP_PLAN_${tier.toUpperCase()}_${cycle}`);
      if (id) map[id] = tier;
    }
  }
  return map;
}

async function hmacHex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const iso = (unixSec?: number) => (unixSec ? new Date(unixSec * 1000).toISOString() : null);

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });

  const secret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secret || !supabaseUrl || !serviceKey) {
    console.error("[razorpay-webhook] not configured:", { secret: !!secret, url: !!supabaseUrl, service: !!serviceKey });
    return new Response("not configured", { status: 500 });
  }

  const raw = await req.text();
  const signature = req.headers.get("x-razorpay-signature") || "";
  const expected = await hmacHex(secret, raw);
  if (signature !== expected) {
    console.error("[razorpay-webhook] SIGNATURE MISMATCH — RAZORPAY_WEBHOOK_SECRET does not match the dashboard webhook secret.", { hasHeader: !!signature });
    return new Response("bad signature", { status: 401 });
  }

  const supabase = createClient(supabaseUrl, serviceKey, { db: { schema: "pocketcare" } });
  let evt: any;
  try { evt = JSON.parse(raw); } catch { return new Response("bad json", { status: 400 }); }
  const event: string = evt.event;
  const planMap = planToTier();
  console.log("[razorpay-webhook] received event:", event);

  try {
    if (event === "subscription.activated" || event === "subscription.charged" || event === "subscription.updated") {
      const sub = evt.payload?.subscription?.entity;
      const payment = evt.payload?.payment?.entity;
      const userId = sub?.notes?.user_id;
      const tier = planMap[sub?.plan_id] || sub?.notes?.tier || "lite";
      if (userId) {
        await supabase.from("entitlements").update({
          tier,
          subscription_status: "active",
          razorpay_subscription_id: sub.id,
          plan_id: sub.plan_id,
          billing_cycle: sub?.notes?.cycle ?? null,
          current_period_end: iso(sub.current_end),
          monthly_quota_total: QUOTA[tier] ?? 50,
          monthly_quota_used: 0,
          quota_reset_date: iso(sub.current_end),
        }).eq("user_id", userId);

        // Record the charge for billing history / invoices (idempotent by payment id).
        if (payment?.id) {
          await supabase.from("payments").insert({
            user_id: userId, kind: "subscription",
            razorpay_subscription_id: sub.id, razorpay_payment_id: payment.id, razorpay_order_id: payment.order_id ?? null,
            amount: payment.amount ?? null, currency: payment.currency ?? "INR", status: "captured", credits_added: 0,
          });
        }
      }
    } else if (["subscription.halted", "subscription.cancelled", "subscription.completed", "subscription.paused"].includes(event)) {
      const sub = evt.payload?.subscription?.entity;
      const userId = sub?.notes?.user_id;
      const status = event.split(".")[1];
      const downgrade = status !== "paused";
      if (userId) {
        await supabase.from("entitlements").update({
          subscription_status: status,
          ...(downgrade ? { tier: "free", monthly_quota_total: 0 } : {}),
        }).eq("user_id", userId);
      }
    } else if (event === "order.paid" || event === "payment.captured") {
      // Credit packs. razorpay-credits pre-records a PENDING row keyed by order
      // id, so we don't depend on notes reaching the payment entity (Razorpay
      // does not copy order notes onto payments). Works on either event.
      const order = evt.payload?.order?.entity;
      const payment = evt.payload?.payment?.entity;
      const orderId = order?.id || payment?.order_id;
      const paymentId = payment?.id ?? null;
      if (orderId) {
        // Flip pending → captured atomically. Only the event that wins the
        // status guard gets rows back, so credits are applied exactly once.
        const { data: captured, error: capErr } = await supabase.from("payments")
          .update({ status: "captured", razorpay_payment_id: paymentId })
          .eq("razorpay_order_id", orderId).eq("kind", "credits").eq("status", "created")
          .select("user_id, credits_added");
        console.log("[razorpay-webhook] credits:", { orderId, matched: captured?.length ?? 0, capErr: capErr?.message ?? null });
        for (const row of captured ?? []) {
          const credits = row.credits_added ?? 0;
          if (credits > 0) {
            const { data: ent } = await supabase.from("entitlements")
              .select("purchased_quota_remaining").eq("user_id", row.user_id).single();
            const current = ent?.purchased_quota_remaining ?? 0;
            const { error: updErr } = await supabase.from("entitlements")
              .update({ purchased_quota_remaining: current + credits }).eq("user_id", row.user_id);
            console.log("[razorpay-webhook] credits applied:", { user: row.user_id, added: credits, newTotal: current + credits, updErr: updErr?.message ?? null });
          }
        }
      } else {
        console.log("[razorpay-webhook] order/payment event with no order id:", event);
      }
    }
  } catch (e) {
    // Log but still 200 so Razorpay doesn't hammer retries on a transient issue.
    console.error("[razorpay-webhook]", event, (e as Error).message);
  }

  return new Response("ok", { status: 200 });
});
