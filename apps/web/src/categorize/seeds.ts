/**
 * Seed rules for the auto-categorization engine.
 * Provides a cold-start heuristic mapping common keywords to standard category names.
 */

// A mapping of raw keyword -> Category Name (case-insensitive)
export const SEED_RULES: Record<string, string> = {
  // Transport
  "uber": "Transport",
  "ola": "Transport",
  "lyft": "Transport",
  "metro": "Transport",
  "train": "Transport",
  "bus": "Transport",
  "flight": "Transport",
  "indigo": "Transport",
  "airasia": "Transport",
  "fuel": "Transport",
  "petrol": "Transport",
  "shell": "Transport",

  // Food
  "swiggy": "Food",
  "zomato": "Food",
  "ubereats": "Food",
  "doordash": "Food",
  "starbucks": "Food",
  "mcdonalds": "Food",
  "kfc": "Food",
  "dominos": "Food",
  "restaurant": "Food",
  "cafe": "Food",

  // Groceries
  "blinkit": "Groceries",
  "zepto": "Groceries",
  "instamart": "Groceries",
  "bigbasket": "Groceries",
  "dmart": "Groceries",
  "whole foods": "Groceries",
  "walmart": "Groceries",
  "target": "Groceries",

  // Shopping
  "amazon": "Shopping",
  "flipkart": "Shopping",
  "myntra": "Shopping",
  "ajio": "Shopping",
  "zara": "Shopping",
  "h&m": "Shopping",

  // Subscriptions / Entertainment
  "netflix": "Subscriptions",
  "spotify": "Subscriptions",
  "youtube": "Subscriptions",
  "prime video": "Subscriptions",
  "disney": "Subscriptions",
  "apple": "Subscriptions",
  "google": "Subscriptions",
  "steam": "Entertainment",
  "movie": "Entertainment",

  // Bills / Housing
  "rent": "Housing",
  "electricity": "Utilities",
  "water": "Utilities",
  "wifi": "Utilities",
  "internet": "Utilities",
  "airtel": "Utilities",
  "jio": "Utilities",

  // Income
  "salary": "Income",
  "paycheck": "Income",
  "bonus": "Income",
  "dividend": "Income",
  "refund": "Income",
};

export interface CategoryData {
  id: string;
  name: string;
}

/**
 * Builds a fast lookup map from token -> actual user category ID.
 * Resolves standard names to the user's category UUIDs.
 */
export function buildSeedMap(categories: CategoryData[]): Map<string, string> {
  const map = new Map<string, string>();
  
  // Build a lowercased name -> id lookup for the user's categories
  const nameToId = new Map<string, string>();
  for (const c of categories) {
    nameToId.set(c.name.toLowerCase(), c.id);
  }

  for (const [keyword, categoryName] of Object.entries(SEED_RULES)) {
    const id = nameToId.get(categoryName.toLowerCase());
    if (id) {
      map.set(keyword, id);
    }
  }

  return map;
}
