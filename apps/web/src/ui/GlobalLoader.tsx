"use client";

import { useEffect, useState } from "react";
import { Spinner } from "./Spinner";

const listeners = new Set<(loading: boolean) => void>();
let count = 0;

export const startLoading = () => {
  count++;
  listeners.forEach((l) => l(true));
};

export const stopLoading = () => {
  count = Math.max(0, count - 1);
  if (count === 0) listeners.forEach((l) => l(false));
};

export function withLoading<T>(promise: Promise<T>): Promise<T> {
  startLoading();
  return promise.finally(() => stopLoading());
}

export function GlobalLoader() {
  const [loading, setLoading] = useState(count > 0);
  useEffect(() => {
    listeners.add(setLoading);
    return () => {
      listeners.delete(setLoading);
    };
  }, []);

  if (!loading) return null;
  return (
    <div style={{ position: "fixed", top: 16, right: 16, zIndex: 9999, background: "var(--surface)", padding: 6, borderRadius: "50%", boxShadow: "var(--shadow)" }}>
      <Spinner size={24} />
    </div>
  );
}
