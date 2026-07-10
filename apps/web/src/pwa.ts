"use client";

import { useSyncExternalStore } from "react";

/**
 * PWA install support. Captures the browser's `beforeinstallprompt` (Android /
 * desktop Chromium) so any component can offer a one-tap install, and exposes
 * platform detection so we can show the right manual steps where a direct
 * prompt isn't available (notably iOS Safari).
 */
type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

let deferred: BeforeInstallPromptEvent | null = null;
const listeners = new Set<() => void>();
const notify = () => listeners.forEach((l) => l());

if (typeof window !== "undefined") {
  window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    deferred = e as BeforeInstallPromptEvent;
    notify();
  });
  window.addEventListener("appinstalled", () => { deferred = null; notify(); });
}

export type Platform = "ios" | "android" | "desktop" | "unknown";

export function detectPlatform(): Platform {
  if (typeof navigator === "undefined") return "unknown";
  const ua = navigator.userAgent || "";
  const iOS = /iPad|iPhone|iPod/.test(ua) ||
    (navigator.platform === "MacIntel" && (navigator as unknown as { maxTouchPoints?: number }).maxTouchPoints! > 1);
  if (iOS) return "ios";
  if (/Android/.test(ua)) return "android";
  return "desktop";
}

/** True when already running as an installed PWA. */
export function isStandalone(): boolean {
  if (typeof window === "undefined") return false;
  return window.matchMedia?.("(display-mode: standalone)").matches
    || (navigator as unknown as { standalone?: boolean }).standalone === true;
}

export function useInstallPrompt(): {
  canInstall: boolean;
  promptInstall: () => Promise<"accepted" | "dismissed" | "unavailable">;
  platform: Platform;
  standalone: boolean;
} {
  const canInstall = useSyncExternalStore(
    (cb) => { listeners.add(cb); return () => listeners.delete(cb); },
    () => !!deferred,
    () => false,
  );
  const promptInstall = async () => {
    if (!deferred) return "unavailable" as const;
    await deferred.prompt();
    const choice = await deferred.userChoice.catch(() => ({ outcome: "dismissed" as const }));
    deferred = null;
    notify();
    return choice.outcome;
  };
  return { canInstall, promptInstall, platform: detectPlatform(), standalone: isStandalone() };
}
