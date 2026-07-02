"use client";

import { useSyncExternalStore } from "react";

export type Theme = "light" | "dark";
const KEY = "theme";
const listeners = new Set<() => void>();

export function getTheme(): Theme {
  if (typeof window === "undefined") return "light";
  return (localStorage.getItem(KEY) as Theme) || "light";
}

/** Apply + persist + notify subscribers. */
export function setTheme(theme: Theme): void {
  localStorage.setItem(KEY, theme);
  document.documentElement.dataset.theme = theme;
  listeners.forEach((l) => l());
}

/** Apply the saved theme to <html> (call once on mount). */
export function applySavedTheme(): void {
  if (typeof document !== "undefined") document.documentElement.dataset.theme = getTheme();
}

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

export function useTheme(): Theme {
  return useSyncExternalStore(subscribe, getTheme, () => "light");
}
