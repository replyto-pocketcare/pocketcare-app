/**
 * Shamir Secret Sharing over GF(2^8). Used to split the SUPPORT private key into
 * M-of-N shares held by different support officers, so no single insider can
 * decrypt a user's consent grant alone. Pure, dependency-free, byte-wise.
 *
 * Each share is `Uint8Array` of the form [x, y0, y1, ...] where x is the unique
 * (1..255) evaluation point and y_i are the secret bytes evaluated at x.
 */

// GF(256) exp/log tables (generator 0x03, AES polynomial 0x11b).
const EXP = new Uint8Array(512);
const LOG = new Uint8Array(256);
(() => {
  let x = 1;
  for (let i = 0; i < 255; i++) {
    EXP[i] = x;
    LOG[x] = i;
    x = gfMulNoTable(x, 3); // multiply by the generator (3)
  }
  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255]!;
})();

function gfMulNoTable(a: number, b: number): number {
  let p = 0;
  for (let i = 0; i < 8; i++) {
    if (b & 1) p ^= a;
    const hi = a & 0x80;
    a = (a << 1) & 0xff;
    if (hi) a ^= 0x1b;
    b >>= 1;
  }
  return p;
}
function mul(a: number, b: number): number {
  if (a === 0 || b === 0) return 0;
  return EXP[LOG[a]! + LOG[b]!]!;
}
function div(a: number, b: number): number {
  if (b === 0) throw new Error("division by zero");
  if (a === 0) return 0;
  return EXP[(LOG[a]! - LOG[b]! + 255) % 255]!;
}

function randomBytes(n: number): Uint8Array {
  const b = new Uint8Array(n);
  globalThis.crypto.getRandomValues(b);
  return b;
}

/** Split `secret` into `n` shares, any `threshold` of which reconstruct it. */
export function split(secret: Uint8Array, n: number, threshold: number): Uint8Array[] {
  if (threshold < 2 || threshold > n || n > 255) throw new Error("require 2 <= threshold <= n <= 255");
  const shares: Uint8Array[] = [];
  for (let x = 1; x <= n; x++) shares.push(new Uint8Array(secret.length + 1));
  for (let i = 0; i < n; i++) shares[i]![0] = i + 1;

  for (let byteIdx = 0; byteIdx < secret.length; byteIdx++) {
    // Random polynomial of degree threshold-1 with constant term = secret byte.
    const coeffs = randomBytes(threshold);
    coeffs[0] = secret[byteIdx]!;
    for (let i = 0; i < n; i++) {
      const x = i + 1;
      let y = 0;
      let xPow = 1;
      for (let c = 0; c < threshold; c++) {
        y ^= mul(coeffs[c]!, xPow);
        xPow = mul(xPow, x);
      }
      shares[i]![byteIdx + 1] = y;
    }
  }
  return shares;
}

/** Reconstruct the secret from `threshold`+ shares (Lagrange interpolation at x=0). */
export function combine(shares: Uint8Array[]): Uint8Array {
  if (shares.length < 2) throw new Error("need at least 2 shares");
  const len = shares[0]!.length - 1;
  const xs = shares.map((s) => s[0]!);
  if (new Set(xs).size !== xs.length) throw new Error("duplicate share x-coordinates");
  const secret = new Uint8Array(len);

  for (let byteIdx = 0; byteIdx < len; byteIdx++) {
    let acc = 0;
    for (let i = 0; i < shares.length; i++) {
      const xi = xs[i]!;
      const yi = shares[i]![byteIdx + 1]!;
      // Lagrange basis L_i(0) = Π_{j≠i} x_j / (x_j - x_i)  in GF(256).
      let num = 1, den = 1;
      for (let j = 0; j < shares.length; j++) {
        if (j === i) continue;
        const xj = xs[j]!;
        num = mul(num, xj);
        den = mul(den, xi ^ xj); // subtraction == XOR in GF(2^8)
      }
      acc ^= mul(yi, div(num, den));
    }
    secret[byteIdx] = acc;
  }
  return secret;
}
