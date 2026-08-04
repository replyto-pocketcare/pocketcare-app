import { useQuery } from "@powersync/react";

export function useIntentQueue() {
  // Select untagged expenses, newest first
  // Excluding internal transfers, opening balances, adjustments
  const { data, isLoading } = useQuery(`
    SELECT t.*, c.name as category_name, a.name as account_name 
    FROM transactions t
    LEFT JOIN categories c ON t.category_id = c.id
    LEFT JOIN accounts a ON t.account_id = a.id
    WHERE t.type = 'expense' 
      AND t.intent IS NULL 
      AND t.deleted_at IS NULL
    ORDER BY t.occurred_at DESC
    LIMIT 50
  `);

  return { queue: data || [], isLoading };
}
