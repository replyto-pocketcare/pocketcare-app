# Deploying PocketCare to Vercel

PocketCare is a **pnpm + Turborepo monorepo**; the deployable app is `apps/web`
(Next.js). The shared `packages/*` are consumed as source (via `transpilePackages`),
so there's no separate build step for them.

## 1. Push to GitHub
```bash
git push -u origin main
```

## 2. Create the Vercel project
1. Vercel → **Add New… → Project** → import `replyto-pocketcare/pocketcare-app`.
2. **Root Directory:** set to `apps/web`.
   Vercel is pnpm-workspace aware — it installs the whole workspace and builds the
   app from this directory. No `vercel.json` is needed.
3. **Framework Preset:** Next.js (auto-detected).
4. **Install / Build / Output:** leave defaults. Vercel uses `pnpm` from the
   committed `pnpm-lock.yaml` (and the `packageManager` field) automatically.
   Node is pinned to 22.x via `apps/web/package.json` engines.

## 3. Environment Variables (Project → Settings → Environment Variables)
Add these for **Production** (and Preview if you want PR deploys to work):

| Key | Value |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://YOUR-PROJECT.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_...` |
| `NEXT_PUBLIC_POWERSYNC_URL` | `https://YOUR-INSTANCE.powersync.journeyapps.com` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | *(optional legacy fallback)* |

> These are `NEXT_PUBLIC_*`, so they're inlined into the browser bundle **at build
> time** — after changing them, trigger a redeploy. There is no server secret here;
> the anon/publishable key is safe to expose (RLS protects the data).

## 4. Point Supabase at the deployed URL
In Supabase → **Authentication → URL Configuration**:
- **Site URL:** your Vercel URL (e.g. `https://pocketcare.vercel.app`).
- **Redirect URLs:** add the same URL (and any custom domain). Needed so email
  confirmation / OTP magic links redirect back into the app.

Also make sure (one-time, on the Supabase project):
- **Anonymous sign-ins** enabled, **"Secure email change"** disabled, and the
  *Change Email Address* template includes `{{ .Token }}` (for the 6-digit OTP).
- The `powersync` publication exists and PowerSync **Sync Streams**
  (`packages/db/sync-streams.yaml`) are deployed, pointing at this Supabase DB.

## 5. Deploy & verify
- Deploy. Open the URL → you should see onboarding, then the dashboard.
- Create an account, add a transaction — confirm it appears (and, if you check
  Supabase, the row is there).
- The app is a PWA: Chrome shows an install icon in the address bar.

## 6. PowerSync auth (JWT verification) — required for sync
PowerSync verifies the Supabase login JWT before syncing. If this is misconfigured
you'll see, in the app's sync status: **`PSYNC_S2101 … no key matched the token KID`**
— PowerSync got the token but has no matching key, so nothing syncs (up or down).

Configure it in the **PowerSync Dashboard → your instance → Edit → Client Auth**:

- **Supabase now uses asymmetric JWT signing keys** (tokens carry a `kid`). Point
  PowerSync at Supabase's JWKS so it fetches the right public key:
  - **JWKS URI:** `https://YOUR-PROJECT.supabase.co/auth/v1/.well-known/jwks.json`
  - **Audience:** `authenticated`
  - (PowerSync caches and auto-refreshes keys, so rotations keep working.)
- **Legacy (HS256 shared secret) projects only:** instead enable "Use Supabase
  Auth" and paste the **JWT Secret** from Supabase → Settings → API → JWT Settings.

Check which one you're on in Supabase → **Settings → API → JWT Keys**. If asymmetric
"Signing Keys" are active (the current default), use the **JWKS URI** path above.

After changing PowerSync auth, reload the app — the Settings sync line should read
"Synced …" with no warning banner.

## Notes
- CI-style build safety: `next.config.js` sets `eslint.ignoreDuringBuilds` and
  `typescript.ignoreBuildErrors` so a stray lint/type warning won't block a deploy.
  Tighten these once you add a CI lint/type gate.
- `.env` is git-ignored; production config lives in Vercel env vars.
- This JWT step is auth config, not code — nothing in `apps/web` changes it.
