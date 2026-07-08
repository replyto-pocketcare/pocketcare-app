"use client";

import { getSupabase } from "./powersync";
import type { PaidTier, Cycle, CreditPackId } from "./billing/plans";

const SCRIPT = "https://checkout.razorpay.com/v1/checkout.js";
let scriptPromise: Promise<void> | null = null;

/** Load Razorpay Checkout once. */
export function loadRazorpay(): Promise<void> {
  if (typeof window === "undefined") return Promise.reject(new Error("no window"));
  if ((window as unknown as { Razorpay?: unknown }).Razorpay) return Promise.resolve();
  if (scriptPromise) return scriptPromise;
  scriptPromise = new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = SCRIPT;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error("Failed to load the payment window. Check your connection and try again."));
    document.body.appendChild(s);
  });
  return scriptPromise;
}

async function invoke<T>(fn: string, body: Record<string, unknown>): Promise<T> {
  const { data, error } = await getSupabase().functions.invoke(fn, { body });
  if (error) throw new Error(error.message);
  if ((data as { error?: string })?.error) throw new Error((data as { error: string }).error);
  return data as T;
}

async function prefill(): Promise<{ email?: string }> {
  try {
    const { data } = await getSupabase().auth.getUser();
    return data.user?.email ? { email: data.user.email } : {};
  } catch { return {}; }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function openCheckout(options: Record<string, unknown>): Promise<{ ok: boolean }> {
  return new Promise((resolve) => {
    const Razorpay = (window as unknown as { Razorpay: new (o: unknown) => { open: () => void } }).Razorpay;
    const rzp = new Razorpay({
      name: "PocketCare",
      theme: { color: "#b06a4f" },
      handler: () => resolve({ ok: true }),
      modal: { ondismiss: () => resolve({ ok: false }) },
      ...options,
    });
    rzp.open();
  });
}

/** Start a recurring subscription; the webhook activates the plan shortly after. */
export async function startSubscription(tier: PaidTier, cycle: Cycle): Promise<{ ok: boolean }> {
  await loadRazorpay();
  const { subscription_id, key_id } = await invoke<{ subscription_id: string; key_id: string }>(
    "razorpay-subscription", { tier, cycle },
  );
  return openCheckout({ key: key_id, subscription_id, description: `PocketCare ${tier} (${cycle})`, prefill: await prefill() });
}

/** Cancel the current subscription at cycle end (access continues until then). */
export async function cancelSubscription(): Promise<{ ok: boolean; ends_at: string | null }> {
  return invoke<{ ok: boolean; ends_at: string | null }>("razorpay-cancel", {});
}

/** Buy a one-time AI credit pack; the webhook adds the credits shortly after. */
export async function buyCredits(pack: CreditPackId): Promise<{ ok: boolean }> {
  await loadRazorpay();
  const { order_id, amount, key_id, credits } = await invoke<{ order_id: string; amount: number; key_id: string; credits: number }>(
    "razorpay-credits", { pack },
  );
  return openCheckout({ key: key_id, order_id, amount, currency: "INR", description: `${credits} AI credits`, prefill: await prefill() });
}
