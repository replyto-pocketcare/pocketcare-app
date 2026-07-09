import { useEffect, useState, useRef } from "react";
import { getDb, getUserId } from "../powersync";
import { suggestCategory, learnFromSave } from "./engine";
import type { CategoryData } from "./seeds";

/**
 * Hook to automatically suggest a category based on debounced input text.
 */
export function useAutoCategorize(
  text: string,
  categories: CategoryData[],
  enabled: boolean
) {
  const [suggestedCategory, setSuggestedCategory] = useState<string | null>(null);
  const [isAutoApplied, setIsAutoApplied] = useState(false);
  const debounceRef = useRef<NodeJS.Timeout>();

  useEffect(() => {
    if (!enabled) return;

    // Debounce the suggestion engine
    clearTimeout(debounceRef.current);
    
    // Clear suggestion immediately if text is empty
    if (!text.trim()) {
      setSuggestedCategory(null);
      setIsAutoApplied(false);
      return;
    }

    debounceRef.current = setTimeout(async () => {
      const db = getDb();
      const userId = getUserId();
      if (!db || !userId) return;

      const suggestion = await suggestCategory(text, db, userId, categories);
      setSuggestedCategory(suggestion);
    }, 250);

    return () => clearTimeout(debounceRef.current);
  }, [text, categories, enabled]);

  return {
    suggestedCategory,
    isAutoApplied,
    setIsAutoApplied,
  };
}

/**
 * Helper to trigger the learning routine upon saving a transaction.
 */
export function useLearnCategory() {
  return async (text: string, chosenCategoryId: string | null, suggestedCategoryId: string | null) => {
    const db = getDb();
    const userId = getUserId();
    if (!db || !userId) return;

    await learnFromSave(text, chosenCategoryId, suggestedCategoryId, db, userId);
  };
}
