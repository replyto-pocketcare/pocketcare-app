"use client";

import { useQuery } from "@powersync/react";

export interface Contact {
  id: string;
  name: string;
  email: string | null;
  avatar_color: string | null;
}

/** Active (non-archived) contacts you split with. */
export function useContacts(): Contact[] {
  const { data = [] } = useQuery<Contact>(
    "SELECT id, name, email, avatar_color FROM contacts WHERE deleted_at IS NULL AND IFNULL(archived,0) = 0 ORDER BY name",
  );
  return data;
}

export interface FriendBalance {
  contactId: string;
  name: string;
  avatarColor: string | null;
  /** Minor units. Positive = they owe you. */
  net: number;
}

/**
 * Per-contact running balance. Phase 1: you are always the payer, so a contact
 * simply owes you the sum of their shares. (Settlements and contact-paid splits
 * arrive in Phase 2 and subtract here.)
 */
export function useFriendBalances(): FriendBalance[] {
  const { data = [] } = useQuery<{ contact_id: string; name: string; color: string | null; owed: number }>(
    `SELECT s.contact_id AS contact_id, c.name AS name, c.avatar_color AS color, SUM(s.share_amount) AS owed
     FROM shared_expense_shares s
     JOIN contacts c ON c.id = s.contact_id
     JOIN shared_expenses e ON e.id = s.expense_id
     WHERE s.deleted_at IS NULL AND e.deleted_at IS NULL AND s.contact_id IS NOT NULL
     GROUP BY s.contact_id, c.name, c.avatar_color
     ORDER BY owed DESC`,
  );
  return data.map((r) => ({ contactId: r.contact_id, name: r.name, avatarColor: r.color, net: r.owed }));
}
