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

  // --- Extra Indian merchants (substring-matched against mangled UPI names) ---
  // Food & delivery
  "swiggyinstamart": "Groceries",
  "eatfit": "Food & Dining",
  "faasos": "Food & Dining",
  "behrouz": "Food & Dining",
  "chaayos": "Food & Dining",
  "haldiram": "Food & Dining",
  "barbeque": "Food & Dining",
  "biryani": "Food & Dining",
  // Transport / mobility
  "rapido": "Transport",
  "irctc": "Transport",
  "redbus": "Transport",
  "makemytrip": "Transport",
  "goibibo": "Transport",
  "ixigo": "Transport",
  "fastag": "Transport",
  "hpcl": "Transport",
  "bpcl": "Transport",
  "ioc": "Transport",
  "indianoil": "Transport",
  "uberride": "Transport",
  "parking": "Transport",
  "toll": "Transport",
  // Groceries / quick-commerce
  "bbnow": "Groceries",
  "jiomart": "Groceries",
  "reliancefresh": "Groceries",
  "moreretail": "Groceries",
  "naturebasket": "Groceries",
  "licious": "Groceries",
  // Shopping / marketplaces
  "meesho": "Shopping",
  "nykaa": "Shopping",
  "tatacliq": "Shopping",
  "snapdeal": "Shopping",
  "croma": "Shopping",
  "reliancedigital": "Shopping",
  "decathlon": "Shopping",
  "ikea": "Shopping",
  "lenskart": "Shopping",
  "firstcry": "Shopping",
  "pharmeasy": "Health",
  "netmeds": "Health",
  "apollo": "Health",
  "onemg": "Health",
  "tata1mg": "Health",
  "practo": "Health",
  "cultfit": "Health",
  // Subscriptions / entertainment
  "hotstar": "Subscriptions",
  "sonyliv": "Subscriptions",
  "zee5": "Subscriptions",
  "jiocinema": "Subscriptions",
  "audible": "Subscriptions",
  "youtubepremium": "Subscriptions",
  "googleone": "Subscriptions",
  "icloud": "Subscriptions",
  "openai": "Subscriptions",
  "chatgpt": "Subscriptions",
  "bookmyshow": "Entertainment",
  "pvr": "Entertainment",
  "inox": "Entertainment",
  // Bills / utilities / telecom
  "vodafone": "Utilities",
  "vi": "Utilities",
  "bsnl": "Utilities",
  "tataplay": "Utilities",
  "actfibernet": "Utilities",
  "adani": "Utilities",
  "tatapower": "Utilities",
  "bescom": "Utilities",
  "mseb": "Utilities",
  "gas": "Utilities",
  "recharge": "Utilities",
  "broadband": "Utilities",
  // Finance / investing
  "zerodha": "Investments",
  "groww": "Investments",
  "upstox": "Investments",
  "coin": "Investments",
  "kuvera": "Investments",
  "indmoney": "Investments",
  "lic": "Insurance",
  "policybazaar": "Insurance",
  "insurance": "Insurance",
  "premium": "Insurance",
  // Education
  "udemy": "Education",
  "coursera": "Education",
  "unacademy": "Education",
  "byjus": "Education",
  "tuition": "Education",
  "school": "Education",
  "college": "Education",
  "course": "Education",

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

/**
 * Same resolution as buildSeedMap, but as a flat list for substring matching
 * against a merchant blob (e.g. "swiggylimited" contains "swiggy"). Longest
 * keywords first so the most specific merchant wins ties.
 */
export function buildSeedList(categories: CategoryData[]): { keyword: string; categoryId: string }[] {
  const map = buildSeedMap(categories);
  return Array.from(map.entries())
    .map(([keyword, categoryId]) => ({ keyword, categoryId }))
    .sort((a, b) => b.keyword.length - a.keyword.length);
}
