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
  const [working, setWorking] = useState(false); // true while a suggestion is being computed
  const debounceRef = useRef<NodeJS.Timeout>();

  useEffect(() => {
    if (!enabled) { setWorking(false); return; }

    clearTimeout(debounceRef.current);

    if (!text.trim()) {
      setSuggestedCategory(null);
      setIsAutoApplied(false);
      setWorking(false);
      return;
    }

    // Show "working" immediately on each keystroke, then resolve after a short debounce.
    setWorking(true);
    debounceRef.current = setTimeout(async () => {
      const db = getDb();
      const userId = getUserId();
      if (!db || !userId) { setWorking(false); return; }
      try {
        const suggestion = await suggestCategory(text, db, userId, categories);
        setSuggestedCategory(suggestion);
      } finally {
        setWorking(false);
      }
    }, 200);

    return () => clearTimeout(debounceRef.current);
  }, [text, categories, enabled]);

  return {
    suggestedCategory,
    isAutoApplied,
    setIsAutoApplied,
    working,
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
