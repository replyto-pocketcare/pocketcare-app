/**
 * Representative example phrases per default category — the "training set" that
 * defines each category's meaning for the semantic classifier. The classifier
 * embeds these into a centroid, so any input word is matched to the nearest
 * category by meaning (not by keyword equality). Custom/renamed categories fall
 * back to their name; user corrections are added on top over time.
 */
export const CATEGORY_ANCHORS: Record<string, string[]> = {
  // ---- expense ----
  "food & dining": ["restaurant", "lunch", "dinner", "breakfast", "coffee", "cafe", "pizza", "burger", "chocolate", "snacks", "ice cream", "swiggy", "zomato", "takeaway", "biryani"],
  "groceries": ["milk", "bread", "eggs", "vegetables", "fruits", "rice", "flour", "cooking oil", "sugar", "supermarket", "bigbasket", "blinkit", "dmart", "provisions"],
  "transport": ["uber", "ola", "taxi", "cab", "auto rickshaw", "bus fare", "train ticket", "metro", "fuel", "petrol", "diesel", "parking", "toll"],
  "housing": ["rent", "house rent", "maintenance", "society charges", "mortgage", "property tax"],
  "utilities": ["electricity bill", "water bill", "gas cylinder", "internet", "wifi", "broadband", "mobile recharge", "phone bill"],
  "health": ["medicine", "pharmacy", "chemist", "doctor", "hospital", "clinic", "lab test", "dentist", "gym", "supplements"],
  "shopping": ["shoes", "shirt", "t-shirt", "clothes", "dress", "jeans", "jacket", "bag", "watch", "electronics", "amazon", "flipkart", "myntra"],
  "entertainment": ["movie", "cinema", "concert", "game", "video game", "amusement park", "bowling", "netflix", "streaming"],
  "education": ["tuition", "course fee", "school fee", "college", "books", "stationery", "online course", "exam fee"],
  "travel": ["flight", "hotel", "airbnb", "vacation", "holiday", "trip", "resort", "visa", "travel booking"],
  "personal care": ["salon", "haircut", "spa", "cosmetics", "skincare", "grooming", "makeup"],
  "gifts & donations": ["gift", "present", "donation", "charity", "temple", "fundraiser"],
  "fees & charges": ["bank charges", "atm fee", "late fee", "penalty", "service charge", "processing fee", "convenience fee"],
  "insurance": ["insurance premium", "life insurance", "health insurance", "car insurance", "policy"],
  "kids": ["toys", "diapers", "baby food", "school supplies", "daycare", "kids clothes"],
  "pets": ["pet food", "dog food", "cat food", "vet", "grooming", "pet supplies"],
  "subscriptions": ["netflix", "spotify", "youtube premium", "prime", "icloud", "software subscription", "membership"],
  "taxes": ["income tax", "gst", "tds", "advance tax", "tax payment"],
  "miscellaneous": ["misc", "other", "sundry", "unknown"],
  // ---- income ----
  "salary": ["salary", "paycheck", "monthly pay", "wages", "payroll"],
  "business": ["business income", "sales revenue", "client payment", "profit"],
  "freelance": ["freelance", "consulting", "gig", "contract work", "project payment"],
  "bonus": ["bonus", "incentive", "performance bonus", "diwali bonus"],
  "interest": ["interest", "savings interest", "fd interest", "bank interest"],
  "dividends": ["dividend", "stock dividend", "mutual fund payout"],
  "rental income": ["rent received", "rental income", "tenant payment"],
  "refunds": ["refund", "cashback", "reimbursement", "return"],
  "gifts received": ["gift received", "money gift", "cash gift"],
  "other income": ["other income", "misc income", "windfall"],
};

/** Resolve a (possibly renamed) category name to its best anchor example set. */
export function anchorsFor(categoryName: string): string[] {
  const lower = categoryName.trim().toLowerCase();
  if (CATEGORY_ANCHORS[lower]) return CATEGORY_ANCHORS[lower]!;
  for (const [name, examples] of Object.entries(CATEGORY_ANCHORS)) {
    if (name.includes(lower) || lower.includes(name)) return examples;
  }
  return [];
}
