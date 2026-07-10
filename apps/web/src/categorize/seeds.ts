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

  // Food & Dining (merchants + common items)
  "swiggy": "Food & Dining",
  "zomato": "Food & Dining",
  "ubereats": "Food & Dining",
  "doordash": "Food & Dining",
  "starbucks": "Food & Dining",
  "mcdonalds": "Food & Dining",
  "kfc": "Food & Dining",
  "dominos": "Food & Dining",
  "restaurant": "Food & Dining",
  "cafe": "Food & Dining",
  "coffee": "Food & Dining",
  "tea": "Food & Dining",
  "lunch": "Food & Dining",
  "dinner": "Food & Dining",
  "breakfast": "Food & Dining",
  "pizza": "Food & Dining",
  "burger": "Food & Dining",
  "meal": "Food & Dining",
  "snacks": "Food & Dining",
  "chocolate": "Food & Dining",
  "icecream": "Food & Dining",

  // Groceries
  "blinkit": "Groceries",
  "zepto": "Groceries",
  "instamart": "Groceries",
  "bigbasket": "Groceries",
  "dmart": "Groceries",
  "whole foods": "Groceries",
  "walmart": "Groceries",
  "target": "Groceries",
  "grocery": "Groceries",
  "groceries": "Groceries",
  "milk": "Groceries",
  "bread": "Groceries",
  "eggs": "Groceries",
  "vegetables": "Groceries",
  "veggies": "Groceries",
  "fruits": "Groceries",
  "rice": "Groceries",
  "oil": "Groceries",
  "sugar": "Groceries",

  // Shopping (merchants + common items)
  "amazon": "Shopping",
  "flipkart": "Shopping",
  "myntra": "Shopping",
  "ajio": "Shopping",
  "zara": "Shopping",
  "h&m": "Shopping",
  "shoes": "Shopping",
  "shirt": "Shopping",
  "tshirt": "Shopping",
  "clothes": "Shopping",
  "dress": "Shopping",
  "jeans": "Shopping",
  "jacket": "Shopping",
  "bag": "Shopping",
  "watch": "Shopping",

  // Health
  "medicine": "Health",
  "pharmacy": "Health",
  "chemist": "Health",
  "doctor": "Health",
  "hospital": "Health",
  "clinic": "Health",
  "gym": "Health",

  // Personal Care
  "salon": "Personal Care",
  "haircut": "Personal Care",
  "spa": "Personal Care",

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
  "salary": "Salary",
  "paycheck": "Salary",
  "bonus": "Bonus",
  "dividend": "Dividends",
  "refund": "Refunds",
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
  const nameToId = new Map<string, string>();
  for (const c of categories) nameToId.set(c.name.toLowerCase(), c.id);

  // Resolve a seed's target name to a real category id — exact first, then a
  // tolerant contains-match so "Food" still resolves to "Food & Dining", etc.
  const resolve = (categoryName: string): string | undefined => {
    const lower = categoryName.toLowerCase();
    const exact = nameToId.get(lower);
    if (exact) return exact;
    for (const c of categories) {
      const cn = c.name.toLowerCase();
      if (cn === lower || cn.includes(lower) || lower.includes(cn)) return c.id;
    }
    return undefined;
  };

  for (const [keyword, categoryName] of Object.entries(SEED_RULES)) {
    const id = resolve(categoryName);
    if (id) map.set(keyword, id);
  }
  return map;
}
