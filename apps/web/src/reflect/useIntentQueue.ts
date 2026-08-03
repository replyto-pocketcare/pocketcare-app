import { useQuery } from "@powersync/react";

export function useIntentQueue() {
  // Select untagged expenses, newest first
  // Excluding internal transfers, opening balances, adjustments
  const { data, isLoading } = useQuery(`
    SELECT * FROM transactions 
    WHERE type = 'expense' 
      AND intent IS NULL 
      AND deleted_at IS NULL
    ORDER BY occurred_at DESC
    LIMIT 50
  `);

  return { queue: data || [], isLoading };
}
