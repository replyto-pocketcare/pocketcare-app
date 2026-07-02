"use client";

import { useEffect, useState } from "react";
import { getSupabase } from "./powersync";

export interface SessionInfo {
  email: string | null;
  isGuest: boolean;
  username: string;
  /** Days until a guest's data is deleted (created_at + 3 days). Null if registered. */
  daysLeft: number | null;
}

const GUEST_DAYS = 3;

export function useSession(): SessionInfo | null {
  const [info, setInfo] = useState<SessionInfo | null>(null);

  useEffect(() => {
    let active = true;
    void getSupabase()
      .auth.getUser()
      .then(({ data }) => {
        if (!active) return;
        const u = data.user;
        const isGuest = Boolean((u as { is_anonymous?: boolean } | null)?.is_anonymous);
        const created = u?.created_at ? new Date(u.created_at).getTime() : Date.now();
        const remainMs = created + GUEST_DAYS * 86_400_000 - Date.now();
        const daysLeft = isGuest ? Math.max(0, Math.ceil(remainMs / 86_400_000)) : null;
        const username =
          (u?.user_metadata?.username as string | undefined) ??
          (typeof window !== "undefined" ? localStorage.getItem("username") ?? "" : "");
        setInfo({ email: u?.email ?? null, isGuest, username, daysLeft });
      })
      .catch(() => active && setInfo({ email: null, isGuest: true, username: "", daysLeft: GUEST_DAYS }));
    return () => {
      active = false;
    };
  }, []);

  return info;
}

export async function updateUsername(name: string): Promise<void> {
  localStorage.setItem("username", name);
  try {
    await getSupabase().auth.updateUser({ data: { username: name } });
  } catch {
    /* offline — kept locally, syncs on next auth call */
  }
}

export async function signOut(): Promise<void> {
  try {
    await getSupabase().auth.signOut();
  } finally {
    // Reload so the app re-initialises with a fresh session.
    window.location.href = "/onboarding";
  }
}
