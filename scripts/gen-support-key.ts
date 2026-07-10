/**
 * PocketCare — generate the SUPPORT keypair for sealed support access.
 *
 * Produces:
 *   1. the PUBLIC JWK → paste into NEXT_PUBLIC_SUPPORT_PUBLIC_JWK (Vercel/client)
 *   2. the PRIVATE key, Shamir-split into N shares (threshold M) → one file per
 *      support officer. Hand each `.share` to a DIFFERENT person. Any M of them
 *      can reconstruct the key to open a user's consent grant; fewer cannot.
 *
 * SECURITY: run this on a trusted, offline machine. NEVER commit the shares or
 * the private key, and NEVER store them on a server. Delete the output dir after
 * distributing the shares.
 *
 * Run:  node --experimental-strip-types scripts/gen-support-key.ts [--shares N] [--threshold M] [--out DIR]
 * e.g.  node --experimental-strip-types scripts/gen-support-key.ts --shares 3 --threshold 2 --out ./support-key
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { generateSupportKeypair, toBase64 } from "@pocketcare/crypto";
import { split } from "@pocketcare/crypto/shamir";

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1]! : fallback;
}

const shares = Number(arg("shares", "3"));
const threshold = Number(arg("threshold", "2"));
const outDir = arg("out", "./support-key");

if (!(threshold >= 2 && threshold <= shares && shares <= 255)) {
  console.error("Require 2 <= threshold <= shares <= 255.");
  process.exit(1);
}

const { publicJwk, privateJwk } = await generateSupportKeypair();

// Split the private key (as UTF-8 JSON bytes) into N shares.
const privBytes = new TextEncoder().encode(JSON.stringify(privateJwk));
const pieces = split(privBytes, shares, threshold);

mkdirSync(outDir, { recursive: true });
pieces.forEach((p, i) => {
  const file = join(outDir, `officer-${i + 1}.share`);
  writeFileSync(file, toBase64(p), "utf8");
});

console.log("\n=== SUPPORT PUBLIC KEY (safe to expose) ===");
console.log("Set this as NEXT_PUBLIC_SUPPORT_PUBLIC_JWK (single line):\n");
console.log(JSON.stringify(publicJwk));

console.log(`\n=== PRIVATE KEY SHARES (SECRET) ===`);
console.log(`Wrote ${shares} shares to ${outDir}/ — any ${threshold} reconstruct the key.`);
console.log("Distribute one share to each support officer over a secure channel,");
console.log("then DELETE this directory. Point scripts/support-admin.ts at >= threshold shares.\n");
