import type { AbstractPowerSyncDatabase } from "@powersync/common";

/** Default category tree (parent → children) seeded for new users. */
const CATEGORIES: { name: string; kind: "expense" | "income"; children?: string[] }[] = [
  { name: "Food & Dining", kind: "expense", children: ["Restaurants", "Coffee & Snacks", "Takeout & Delivery"] },
  { name: "Groceries", kind: "expense" },
  { name: "Transport", kind: "expense", children: ["Fuel", "Public Transit", "Taxi & Rideshare", "Parking"] },
  { name: "Housing", kind: "expense", children: ["Rent", "Mortgage", "Maintenance"] },
  { name: "Utilities", kind: "expense", children: ["Electricity", "Water", "Gas", "Internet", "Mobile"] },
  { name: "Health", kind: "expense", children: ["Doctor", "Pharmacy", "Fitness"] },
  { name: "Shopping", kind: "expense", children: ["Clothing", "Electronics", "Home"] },
  { name: "Entertainment", kind: "expense", children: ["Streaming", "Movies", "Games", "Events"] },
  { name: "Education", kind: "expense", children: ["Courses", "Books", "Tuition"] },
  { name: "Travel", kind: "expense", children: ["Flights", "Hotels", "Activities"] },
  { name: "Personal Care", kind: "expense" },
  { name: "Gifts & Donations", kind: "expense" },
  { name: "Fees & Charges", kind: "expense", children: ["Bank Fees", "Interest Charges"] },
  { name: "Insurance", kind: "expense" },
  { name: "Kids", kind: "expense" },
  { name: "Pets", kind: "expense" },
  { name: "Subscriptions", kind: "expense" },
  { name: "Taxes", kind: "expense" },
  { name: "Miscellaneous", kind: "expense" },
  { name: "Salary", kind: "income" },
  { name: "Business", kind: "income" },
  { name: "Freelance", kind: "income" },
  { name: "Bonus", kind: "income" },
  { name: "Interest", kind: "income" },
  { name: "Dividends", kind: "income" },
  { name: "Rental Income", kind: "income" },
  { name: "Refunds", kind: "income" },
  { name: "Gifts Received", kind: "income" },
  { name: "Other Income", kind: "income" },
];

const LABELS: { name: string; color: string }[] = [
  { name: "Essential", color: "#5f7a52" }, { name: "Wants", color: "#c08a3e" },
  { name: "Work", color: "#3e4a38" }, { name: "Family", color: "#b06a4f" },
  { name: "Trip", color: "#9cae8e" }, { name: "Emergency", color: "#a8503a" },
  { name: "Recurring", color: "#5f6647" }, { name: "One-off", color: "#c98a72" },
];

/**
 * Fallback seed: if the user has no categories after first sync (e.g. the server
 * trigger didn't run or download sync hasn't delivered), create the defaults
 * locally so they're immediately usable. Uploads to the server on sync.
 */
export async function seedDefaultsIfEmpty(db: AbstractPowerSyncDatabase, userId: string): Promise<void> {
  try { await db.waitForFirstSync({ signal: AbortSignal.timeout(6000) }); } catch { /* proceed anyway */ }

  const existing = await db.get<{ c: number }>("SELECT COUNT(*) as c FROM categories WHERE deleted_at IS NULL").catch(() => ({ c: 0 }));
  if ((existing?.c ?? 0) > 0) return;

  const uuid = () => globalThis.crypto.randomUUID();
  const ts = new Date().toISOString();

  await db.writeTransaction(async (tx) => {
    for (const cat of CATEGORIES) {
      const parentId = uuid();
      await tx.execute(
        "INSERT INTO categories (id,user_id,name,kind,is_system,parent_id,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)",
        [parentId, userId, cat.name, cat.kind, 1, null, ts, ts],
      );
      for (const child of cat.children ?? []) {
        await tx.execute(
          "INSERT INTO categories (id,user_id,name,kind,is_system,parent_id,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)",
          [uuid(), userId, child, cat.kind, 1, parentId, ts, ts],
        );
      }
    }
    for (const l of LABELS) {
      await tx.execute(
        "INSERT INTO labels (id,user_id,name,color,created_at,updated_at) VALUES (?,?,?,?,?,?)",
        [uuid(), userId, l.name, l.color, ts, ts],
      );
    }
  });
}
