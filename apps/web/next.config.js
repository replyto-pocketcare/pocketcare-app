// Load the shared monorepo-root .env so NEXT_PUBLIC_* vars are available here.
// (Next only auto-loads .env from this app folder; we keep one root .env.)
// Dependency-free parser so it works under pnpm's strict node_modules.
const fs = require("fs");
const path = require("path");
for (const file of [".env", ".env.local"]) {
  const p = path.resolve(__dirname, "../..", file);
  if (!fs.existsSync(p)) continue;
  for (const raw of fs.readFileSync(p, "utf8").split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let val = line.slice(eq + 1).trim().replace(/^['"]|['"]$/g, "");
    if (process.env[key] === undefined) process.env[key] = val;
  }
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Transpile the shared workspace packages (they ship raw TS).
  transpilePackages: [
    "@pocketcare/types",
    "@pocketcare/money",
    "@pocketcare/finance",
    "@pocketcare/entitlements",
    "@pocketcare/i18n",
    "@pocketcare/ui-tokens",
    "@pocketcare/db",
    "@pocketcare/data",
  ],
  webpack: (config) => {
    // PowerSync runs SQLite as WebAssembly in the browser (no SSR for the DB).
    config.experiments = { ...config.experiments, asyncWebAssembly: true, topLevelAwait: true };
    return config;
  },
};

module.exports = nextConfig;
