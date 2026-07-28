"use client";

/**
 * Payment hooks. Note the deliberate asymmetry between the two 0041 tables:
 *
 *  - `payment_handles` holds the encrypted UPI ID and is SERVER-ONLY. It never
 *    reaches a device; even the masked hint comes back from the edge function.
 *  - `payment_handle_disclosures` IS synced. It's your own audit trail and
 *    contains no secret — just who looked and when — so it reads from local
 *    SQLite like everything else, and works offline.
 */
import { useQuery } from "@powersync/react";

import { useSession } from "../account";

export interface Disclosure {
  id: string;
  viewer_user_id: string;
  created_at: string;
}

/** Who has fetched your UPI ID, newest first. Your own audit trail. */
export function useHandleDisclosures(): Disclosure[] {
  const { data = [] } = useQuery<Disclosure>(
    "SELECT id, viewer_user_id, created_at FROM payment_handle_disclosures ORDER BY created_at DESC LIMIT 50",
  );
  return data;
}

/** Guests may not save a UPI ID — enforced by a DB trigger; mirrored here for the UI. */
export function useCanSavePaymentHandle(): boolean {
  const session = useSession();
  return !!session && !session.isGuest;
}
