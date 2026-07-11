/**
 * PocketCare — admin coupon / promo / segment tooling (service role).
 *
 * Run:  node --experimental-strip-types scripts/admin-coupons.ts <command> [args]
 * Env:  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 *
 * Commands:
 *   promo <CODE> <lite|pro> <months> ["note"]         create/activate a shared promo code
 *   segment <name> [--gender X] [--country Y] ["desc"] save a named audience segment
 *   issue <lite|pro> <months> <expiresDays> [--gender X] [--country Y] [--dry]
 *                                                     bulk-issue per-user coupons to matching users
 *
 * Examples:
 *   promo BETA_TESTER pro 1 "Beta 1 month Pro"
 *   issue lite 1 30 --gender female --country IN
 */
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) { console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY."); process.exit(1); }
const db = createClient(url, serviceKey, { db: { schema: "pocketcare" } });

function flag(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}
const randCode = () => "PC-" + Math.random().toString(36).slice(2, 10).toUpperCase();

async function cmdPromo(code: string, tier: string, months: string, note?: string) {
  if (!["lite", "pro"].includes(tier)) throw new Error("tier must be lite|pro");
  const { error } = await db.from("promo_codes").upsert(
    { code: code.toUpperCase(), tier, months: Number(months) || 1, active: true, note: note ?? null },
    { onConflict: "code" },
  );
  if (error) throw new Error(error.message);
  console.log(`✓ Promo ${code.toUpperCase()} → ${tier} for ${months} month(s), active.`);
}

async function cmdSegment(name: string, desc?: string) {
  const rule: Record<string, string> = {};
  const g = flag("gender"), c = flag("country");
  if (g) rule.gender = g;
  if (c) rule.country = c;
  const { error } = await db.from("segments").insert({ name, description: desc ?? null, rule });
  if (error) throw new Error(error.message);
  console.log(`✓ Segment "${name}" saved with rule ${JSON.stringify(rule)}.`);
}

async function matchingUsers(): Promise<string[]> {
  let q = db.from("profiles").select("id, gender, country");
  const g = flag("gender"), c = flag("country");
  if (g) q = q.eq("gender", g);
  if (c) q = q.eq("country", c);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return (data ?? []).map((r) => (r as { id: string }).id);
}

async function cmdIssue(tier: string, months: string, expiresDays: string) {
  if (!["lite", "pro"].includes(tier)) throw new Error("tier must be lite|pro");
  const users = await matchingUsers();
  const dry = process.argv.includes("--dry");
  console.log(`Matched ${users.length} user(s)${dry ? " (dry run — nothing issued)" : ""}.`);
  if (dry || users.length === 0) return;
  const expiresAt = new Date(Date.now() + Number(expiresDays) * 86_400_000).toISOString();
  const rows = users.map((uid) => ({ code: randCode(), user_id: uid, tier, months: Number(months) || 1, reason: null, expires_at: expiresAt }));
  const { error } = await db.from("coupons").insert(rows);
  if (error) throw new Error(error.message);
  console.log(`✓ Issued ${rows.length} ${tier} coupon(s), redeem-by ${expiresAt.slice(0, 10)}.`);
}

const [cmd, ...a] = process.argv.slice(2);
try {
  if (cmd === "promo") await cmdPromo(a[0]!, a[1]!, a[2]!, a[3]);
  else if (cmd === "segment") await cmdSegment(a[0]!, a[1]);
  else if (cmd === "issue") await cmdIssue(a[0]!, a[1]!, a[2]!);
  else { console.error("Commands: promo | segment | issue"); process.exit(1); }
} catch (e) {
  console.error(`✗ ${(e as Error).message}`);
  process.exit(1);
}
