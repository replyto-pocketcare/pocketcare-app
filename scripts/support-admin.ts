/**
 * PocketCare — headless Support Admin.
 *
 * Sealed support tooling: it can (1) check/repair SYNC DRIFT without ever seeing
 * plaintext, and (2) decrypt a user's fields ONLY under a live, user-signed,
 * unexpired consent grant, with the SUPPORT private key reassembled from Shamir
 * shares. Every action is appended to the hash-chained `security_audit` table.
 *
 * Run:  node --experimental-strip-types scripts/support-admin.ts <command> [args]
 * Env:  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPPORT_OFFICER (your id)
 *
 * Commands:
 *   verify   <userId> <grantId>            — validate a consent grant (sig + expiry)
 *   drift    <userId> <localExport.json>   — compare local vs remote transactions (no plaintext)
 *   decrypt  <userId> <grantId> <sharesDir> [field] — decrypt notes under a content grant
 */
import { createClient } from "@supabase/supabase-js";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { verifyGrant, unwrapDekFromSupport, decryptField, isEncrypted, fromBase64 } from "@pocketcare/crypto";
import { combine } from "@pocketcare/crypto/shamir";
import { reconcile, type Row } from "@pocketcare/reconcile";

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const officer = process.env.SUPPORT_OFFICER ?? "unknown";
if (!url || !serviceKey) { console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY."); process.exit(1); }
const db = createClient(url, serviceKey, { db: { schema: "pocketcare" } });

async function audit(action: string, subjectUser: string, grantId: string | null, detail: string) {
  await db.from("security_audit").insert({ actor: `support:${officer}`, action, subject_user: subjectUser, grant_id: grantId, detail });
}

async function loadGrant(userId: string, grantId: string) {
  const { data } = await db.from("support_grants").select("*").eq("id", grantId).eq("user_id", userId).maybeSingle();
  return data as null | { id: string; user_id: string; scope: string; wrapped_dek_for_support: string | null; signature: string; expires_at: string; revoked_at: string | null };
}

async function validate(userId: string, grantId: string) {
  const grant = await loadGrant(userId, grantId);
  if (!grant) throw new Error("Grant not found.");
  if (grant.revoked_at) throw new Error("Grant was revoked.");
  const exp = new Date(grant.expires_at).getTime();
  if (Date.now() > exp) throw new Error("Grant expired.");
  const { data: keys } = await db.from("user_keys").select("signing_public_jwk").eq("user_id", userId).maybeSingle();
  const pub = (keys as { signing_public_jwk: unknown } | null)?.signing_public_jwk;
  if (!pub) throw new Error("No signing key on file for user.");
  const ok = await verifyGrant({ userId, grantId, exp, scope: grant.scope }, grant.signature, pub as JsonWebKey);
  if (!ok) throw new Error("Grant signature invalid (not authorized by the user).");
  return grant;
}

async function cmdVerify(userId: string, grantId: string) {
  const g = await validate(userId, grantId);
  console.log(`✓ Valid ${g.scope} grant for ${userId}, expires ${g.expires_at}`);
}

async function cmdDrift(userId: string, localPath: string) {
  const local = JSON.parse(readFileSync(localPath, "utf8")) as Row[];
  const { data } = await db.from("transactions").select("*").eq("user_id", userId).is("deleted_at", null);
  const remote = (data ?? []) as Row[];
  const report = reconcile(local, remote, { ignore: ["updated_at"] });
  console.log(JSON.stringify(report, null, 2));
  await audit("drift_checked", userId, null,
    `inSync=${report.inSync} missingRemote=${report.missingRemote.length} missingLocal=${report.missingLocal.length} mismatched=${report.mismatched.length}`);
}

async function cmdDecrypt(userId: string, grantId: string, sharesDir: string, field = "note") {
  const grant = await validate(userId, grantId);
  if (grant.scope !== "content" || !grant.wrapped_dek_for_support) throw new Error("This grant does not authorize content access.");

  // Reassemble the SUPPORT private key from the officers' Shamir shares.
  const shareFiles = readdirSync(sharesDir).filter((f) => f.endsWith(".share"));
  if (shareFiles.length < 2) throw new Error("Need >= threshold Shamir shares in the directory.");
  const shares = shareFiles.map((f) => fromBase64(readFileSync(join(sharesDir, f), "utf8").trim()));
  const privJwk = JSON.parse(new TextDecoder().decode(combine(shares))) as JsonWebKey;

  const dek = await unwrapDekFromSupport(grant.wrapped_dek_for_support, privJwk);
  const { data } = await db.from("transactions").select(`id, ${field}`).eq("user_id", userId).is("deleted_at", null);
  let shown = 0;
  for (const r of (data ?? []) as Array<Record<string, string | null>>) {
    const v = r[field];
    if (!v) continue;
    const plain = isEncrypted(v) ? await decryptField(v, dek).catch(() => "⚠︎ unreadable") : v;
    console.log(`${r.id}: ${plain}`);
    shown++;
  }
  await audit("content_decrypted", userId, grantId, `field=${field} rows=${shown}`);
  console.log(`\nDecrypted ${shown} ${field} value(s). Logged to security_audit.`);
}

const [cmd, ...args] = process.argv.slice(2);
try {
  if (cmd === "verify") await cmdVerify(args[0]!, args[1]!);
  else if (cmd === "drift") await cmdDrift(args[0]!, args[1]!);
  else if (cmd === "decrypt") await cmdDecrypt(args[0]!, args[1]!, args[2]!, args[3]);
  else { console.error("Commands: verify | drift | decrypt"); process.exit(1); }
} catch (e) {
  console.error(`✗ ${(e as Error).message}`);
  process.exit(1);
}
