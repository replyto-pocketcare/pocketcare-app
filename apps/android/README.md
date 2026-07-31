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
gradle wrapper --gradle-version 8.7
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
- Kotlin/AGP/Compose BOM versions in `gradle/libs.versions.toml` were the
  latest known-good at authoring time (2026-07) — check for newer stable
  releases before shipping.
- **Gradle/AGP version pairing matters.** AGP 8.6.0 requires Gradle >= 8.7
  (the wrapper is pinned to 8.7 in `gradle/wrapper/gradle-wrapper.properties`
  for exactly this reason — an earlier draft of this scaffold shipped 8.6
  and failed with "Minimum supported Gradle version is 8.7"). If you bump
  `agp` in the version catalog, check its minimum Gradle requirement too;
  they don't move in lockstep.
