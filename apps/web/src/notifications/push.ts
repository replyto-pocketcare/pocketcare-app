"use client";

/**
 * Web Push subscription management. The service worker (public/sw.js) shows the
 * OS notification; here we (1) ask the browser for permission, (2) create a
 * PushSubscription bound to our VAPID public key, and (3) persist its endpoint +
 * keys to `pocketcare.push_subscriptions` so the notify-dispatch edge function
 * can deliver to it even when the app/tab is fully closed.
 *
 * The VAPID *public* key is safe to ship to the browser; the private key lives
 * only in the edge function's secrets.
 */
import { getSupabase, getUserId } from "../powersync";

const VAPID_PUBLIC_KEY = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;

export function pushSupported(): boolean {
  return typeof window !== "undefined"
    && "serviceWorker" in navigator
    && "PushManager" in window
    && "Notification" in window;
}

export function pushPermission(): NotificationPermission | "unsupported" {
  if (!pushSupported()) return "unsupported";
  return Notification.permission;
}

function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padding = "=".repeat((4 - (base64.length % 4)) % 4);
  const b64 = (base64 + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(b64);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
}

async function readyRegistration(): Promise<ServiceWorkerRegistration> {
  // AppShell registers /sw.js on load; wait for it to take control.
  const existing = await navigator.serviceWorker.getRegistration();
  if (existing) return navigator.serviceWorker.ready;
  await navigator.serviceWorker.register("/sw.js");
  return navigator.serviceWorker.ready;
}

/**
 * Ask permission (if needed), subscribe, and store the subscription. Returns a
 * short reason string on failure so the UI can explain what to do.
 */
export async function enablePush(): Promise<{ ok: true } | { ok: false; reason: string }> {
  if (!pushSupported()) return { ok: false, reason: "unsupported" };
  if (!VAPID_PUBLIC_KEY) return { ok: false, reason: "missing-vapid-key" };

  const perm = Notification.permission === "granted"
    ? "granted"
    : await Notification.requestPermission();
  if (perm !== "granted") return { ok: false, reason: "denied" };

  try {
    const reg = await readyRegistration();
    const sub = await reg.pushManager.getSubscription()
      ?? await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY) as BufferSource,
      });

    const json = sub.toJSON();
    const keys = json.keys ?? {};
    const { error } = await getSupabase().schema("pocketcare").from("push_subscriptions").upsert(
      {
        user_id: getUserId(),
        endpoint: json.endpoint,
        p256dh: keys.p256dh,
        auth: keys.auth,
        user_agent: navigator.userAgent,
        last_seen: new Date().toISOString(),
      },
      { onConflict: "endpoint" },
    );
    if (error) return { ok: false, reason: error.message };
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: (e as Error).message };
  }
}

/**
 * Fire a notification straight from the service worker — no server, no push
 * service. Proves that permission + the SW registration + showNotification all
 * work on this device. If this shows but real alerts don't, the gap is the
 * server dispatch (function not deployed/scheduled or VAPID secret missing),
 * not the browser.
 */
export async function sendTestNotification(): Promise<{ ok: true } | { ok: false; reason: string }> {
  if (!pushSupported()) return { ok: false, reason: "unsupported" };
  if (Notification.permission !== "granted") {
    const perm = await Notification.requestPermission();
    if (perm !== "granted") return { ok: false, reason: "denied" };
  }
  try {
    const reg = await readyRegistration();
    await reg.showNotification("PocketCare", {
      body: "Test notification — you're all set to receive alerts.",
      icon: "/icon-192.png",
      badge: "/icon-192.png",
      tag: "pocketcare-test",
      data: { href: "/notifications" },
    });
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: (e as Error).message };
  }
}

/** Unsubscribe locally and remove the stored endpoint. */
export async function disablePush(): Promise<void> {
  if (!pushSupported()) return;
  try {
    const reg = await navigator.serviceWorker.getRegistration();
    const sub = await reg?.pushManager.getSubscription();
    if (sub) {
      await getSupabase().schema("pocketcare").from("push_subscriptions").delete().eq("endpoint", sub.endpoint);
      await sub.unsubscribe();
    }
  } catch { /* best effort */ }
}
