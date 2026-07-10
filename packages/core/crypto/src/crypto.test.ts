import { test } from "node:test";
import assert from "node:assert/strict";
import {
  deriveKek, newSalt, generateDek, wrapDek, unwrapDek, encryptField, decryptField, isEncrypted,
  generateRecoveryCode, generateSupportKeypair, wrapDekForSupport, unwrapDekFromSupport,
  generateSigningKeypair, signGrant, verifyGrant, toBase64, fromBase64,
} from "./index.ts";
import { split, combine } from "./shamir.ts";

test("field encryption round-trips and hides plaintext", async () => {
  const dek = generateDek();
  const secret = "Dinner at Taj — ₹4,200";
  const env = await encryptField(secret, dek);
  assert.ok(isEncrypted(env));
  assert.ok(!env.includes("Taj"));
  assert.equal(await decryptField(env, dek), secret);
});

test("a different DEK cannot decrypt (confidentiality)", async () => {
  const env = await encryptField("HDFC Salary Account", generateDek());
  await assert.rejects(() => decryptField(env, generateDek()));
});

test("tampered ciphertext fails authentication (GCM integrity)", async () => {
  const dek = generateDek();
  const env = await encryptField("balance 1000000", dek);
  const parts = env.split(".");
  const ct = fromBase64(parts[2]!); ct[0] = ct[0]! ^ 0xff; // flip a byte
  const tampered = `${parts[0]}.${parts[1]}.${toBase64(ct)}`;
  await assert.rejects(() => decryptField(tampered, dek));
});

test("DEK wrap/unwrap under a passphrase-derived KEK", async () => {
  const dek = generateDek();
  const salt = newSalt();
  const kek = await deriveKek("correct horse battery staple", salt, 50_000);
  const wrapped = await wrapDek(dek, kek);
  const back = await unwrapDek(wrapped, await deriveKek("correct horse battery staple", salt, 50_000));
  assert.deepEqual([...back], [...dek]);
});

test("wrong passphrase cannot unwrap the DEK", async () => {
  const salt = newSalt();
  const wrapped = await wrapDek(generateDek(), await deriveKek("right", salt, 50_000));
  const wrongKek = await deriveKek("wrong", salt, 50_000);
  await assert.rejects(() => unwrapDek(wrapped, wrongKek));
});

test("recovery code unwraps the same DEK (offline backup path)", async () => {
  const dek = generateDek();
  const code = generateRecoveryCode();
  const salt = newSalt();
  const wrapped = await wrapDek(dek, await deriveKek(code, salt, 50_000));
  const back = await unwrapDek(wrapped, await deriveKek(code, salt, 50_000));
  assert.deepEqual([...back], [...dek]);
  assert.match(code, /^[A-Z2-9]{4}(-[A-Z2-9]{4})+$/);
});

test("support grant: only the support private key opens the re-wrapped DEK", async () => {
  const dek = generateDek();
  const support = await generateSupportKeypair();
  const grant = await wrapDekForSupport(dek, support.publicJwk);
  const recovered = await unwrapDekFromSupport(grant, support.privateJwk);
  assert.deepEqual([...recovered], [...dek]);
  const other = await generateSupportKeypair();
  await assert.rejects(() => unwrapDekFromSupport(grant, other.privateJwk));
});

test("consent token signature proves user authorization and detects tampering", async () => {
  const kp = await generateSigningKeypair();
  const payload = { userId: "u1", grantId: "g1", exp: Date.now() + 7200_000 };
  const sig = await signGrant(payload, kp.privateJwk);
  assert.equal(await verifyGrant(payload, sig, kp.publicJwk), true);
  assert.equal(await verifyGrant({ ...payload, userId: "attacker" }, sig, kp.publicJwk), false);
});

test("Shamir 2-of-3: any two shares reconstruct the support key, one cannot", async () => {
  const secret = generateDek(); // stand-in for support private key material
  const shares = split(secret, 3, 2);
  assert.equal(shares.length, 3);
  const pairs: [number, number][] = [[0, 1], [0, 2], [1, 2]];
  for (const [a, b] of pairs) {
    assert.deepEqual([...combine([shares[a]!, shares[b]!])], [...secret]);
  }
  // A single share reveals nothing (combine requires >= 2 and one share ≠ secret).
  assert.notDeepEqual([...shares[0]!.slice(1)], [...secret]);
});

test("Shamir 3-of-5 reconstructs from exactly threshold shares", async () => {
  const secret = new Uint8Array([1, 2, 3, 4, 5, 250, 255, 0]);
  const shares = split(secret, 5, 3);
  assert.deepEqual([...combine([shares[0]!, shares[2]!, shares[4]!])], [...secret]);
});
