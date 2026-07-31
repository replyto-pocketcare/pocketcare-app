# PocketCare — Android (native, rev 3)

Pure Kotlin + Jetpack Compose. No cross-platform layer — see
`docs/plans/native-mobile-apps.md` for the why and the full plan.

## First-time setup (one command, then commit the result)

This scaffold was written by an agent in a sandbox with no Gradle/JDK
compiler available, so it could not generate a trustworthy
`gradle/wrapper/gradle-wrapper.jar` — that's a compiled binary, not
something safe to hand-write. **Before anything else will build:**

```bash
cd apps/android
gradle wrapper --gradle-version 8.13
git add gradlew gradlew.bat gradle/wrapper/
git commit -m "mobile(P0.2): add Gradle wrapper"
```

(Any local Gradle install works for this — Android Studio bundles one, or
`brew install gradle` / `sdk install gradle`. This step only needs to run
once; everyone after you uses the committed wrapper.)

## Build & test

```bash
./gradlew build test
```

`:domain` is a pure-Kotlin module (no Android SDK dependency) so its tests
run as plain JVM tests — fast, no emulator. `:app` is the Compose shell that
depends on it.

## Structure

```
app/      Compose UI shell, application id care.pocket.android (placeholder — plan §10)
domain/   Pure Kotlin, vector-tested against tools/golden-vectors/vectors/*.json (P1.x)
```

`:data`, `:widgets`, `:baselineprofile` are added in later phases (plan §3
target layout) — not created yet, to keep this task's diff reviewable.

## Open items (plan §10 — need a human "yes")

- `applicationId "care.pocket.android"` and `minSdk 26` are proposals, not
  decisions.
- Kotlin/AGP/Compose BOM versions in `gradle/libs.versions.toml` were
  verified against developer.android.com's AGP/Gradle compatibility table
  and web search on 2026-07-31 (AGP 8.13.0, Kotlin 2.4.10, Compose BOM
  2026.06.00, Gradle 8.13) — check for newer stable releases before
  shipping, they will drift again.
- **Gradle/AGP version pairing matters.** AGP versions don't move in
  lockstep with their minimum required Gradle version — always check
  developer.android.com/build/releases/about-agp before bumping `agp` in
  the version catalog. History here: AGP 8.6.0 required Gradle >= 8.7 (an
  earlier draft shipped 8.6 and failed with "Minimum supported Gradle
  version is 8.7"); the wrapper and `agp` were then bumped together to
  8.13.0 / Gradle 8.13 (exact minimum match).
- **Deliberately stayed on AGP 8.x, not 9.x.** AGP 9.0+ ships "built-in
  Kotlin" and drops the separate `kotlin-android` plugin — a real DSL
  migration (see developer.android.com/build/migrate-to-built-in-kotlin)
  that this sandbox has no way to verify (no JDK/Gradle to actually build
  with). 8.13.0 is current within the 8.x line and keeps the
  already-working `kotlin-android` + `kotlinOptions{}` shape. Treat the 9.x
  jump as its own, separately-verified task once a human can run a real
  build.
