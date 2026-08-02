# Sanvya — Android (native, rev 3)

Pure Kotlin + Jetpack Compose. No cross-platform layer — see
`docs/plans/native-mobile-apps.md` for the why and the full plan.

## First-time setup (one command, then commit the result)

This scaffold was written by an agent in a sandbox with no Gradle/JDK
compiler available, so it could not generate a trustworthy
`gradle/wrapper/gradle-wrapper.jar` — that's a compiled binary, not
something safe to hand-write. **Before anything else will build:**

```bash
cd apps/android
gradle wrapper --gradle-version 9.4.1
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

## Run on a device

**Physical device (fastest to set up if you already have one):**
1. Settings → About phone → tap "Build number" 7 times to unlock Developer
   options.
2. Settings → System → Developer options → enable **USB debugging**.
3. Plug the phone in via USB, accept the "Allow USB debugging?" prompt on
   the phone.
4. From `apps/android`:
   ```bash
   ./gradlew installDebug
   adb shell am start -n com.sanvya.app/.MainActivity
   ```
   (or just tap the app icon — "Sanvya" — on the device.)

**Emulator (no physical device needed):** open the project in Android
Studio (`apps/android`), Tools → Device Manager → create a virtual device
(any recent phone profile, API 34+), then hit ▶ Run. Android Studio handles
the emulator boot + install + launch. There's no CLI-only emulator path set
up in this repo yet (no `avdmanager`/`emulator` invocations scripted) —
Android Studio is the easiest route for now.

**Wireless debugging** (no cable): Settings → Developer options → Wireless
debugging → pair with the code shown, then `adb pair <ip>:<port>` and
`adb connect <ip>:<port>` before `./gradlew installDebug`.

Right now the app is P0.2's placeholder Compose screen (wired to
`DomainSkeleton` from `:domain`) — real UI starts in Phase 3 (plan §7)
after the domain ports (Phase 1) and data layer (Phase 2) land.

## Structure

```
app/      Compose UI shell, application id com.sanvya.app (placeholder — plan §10)
domain/   Pure Kotlin, vector-tested against tools/golden-vectors/vectors/*.json (P1.x)
```

## Golden-vector runner (P0.4a)

`domain/src/test/kotlin/care/pocket/domain/vectors/` loads every JSON file
under `tools/golden-vectors/vectors/` (via a Gradle test-resources
`srcDir` pointed at the repo root — nothing is copied, so it can't drift)
and reports pass/skip/fail counts per domain. Right now every vector is
skipped, because `FunctionRegistry` (in the same directory) starts empty
— each Phase 1 porting task (plan §5) registers its own `domain`/`fn`
pair there to un-skip its vectors. A registered function whose output
doesn't match its vector fails the build; an unregistered one just
counts as skipped. Uses `kotlinx.serialization` for JSON (human-approved
2026-07-31 — see the version catalog comment — since `:domain` has no
Android SDK and thus no built-in JSON parser).

`:data`, `:widgets`, `:baselineprofile` are added in later phases (plan §3
target layout) — not created yet, to keep this task's diff reviewable.

## Open items (plan §10 — need a human "yes")

- `applicationId "com.sanvya.app"` and `minSdk 26` are proposals, not
  decisions.
- Kotlin/AGP/Compose BOM versions in `gradle/libs.versions.toml` were
  verified against developer.android.com's AGP/Gradle compatibility table
  and migration guide on 2026-07-31 (AGP 9.2.0, Kotlin 2.4.10, Compose BOM
  2026.06.00, Gradle 9.4.1 — the exact documented minimum for AGP 9.2.0) —
  check for newer stable releases before shipping, they will drift again.
  AGP 9.3 existed at audit time too but developer.android.com's own
  compatibility table hadn't published its minimum Gradle version yet, so
  9.2.0 (fully documented) was used instead of guessing.
- **Gradle/AGP version pairing matters.** AGP versions don't move in
  lockstep with their minimum required Gradle version — always check
  developer.android.com/build/releases/about-agp before bumping `agp` in
  the version catalog. History here: AGP 8.6.0 required Gradle >= 8.7, then
  8.13.0/Gradle 8.13, then (this round) AGP 9.2.0/Gradle 9.4.1 — three real
  version bumps in one build-fix session, each caught by an actual local
  build rather than guessed.
- **On AGP 9.x now — built-in Kotlin is live.** AGP 9.0+ compiles Kotlin
  without the separate `kotlin-android` plugin (applying it alongside AGP
  9.x is a hard error: "no longer required for Kotlin support since AGP
  9.0"). `app/build.gradle.kts` no longer applies `kotlin.android` or sets
  `kotlinOptions{}`/`compilerOptions{}` — `jvmTarget` now defaults from
  `android.compileOptions.targetCompatibility` (17) per
  developer.android.com/build/migrate-to-built-in-kotlin. `:domain` is
  unaffected (plain `kotlin.jvm` module, not an Android one, so built-in
  Kotlin doesn't apply to it). This was deliberately deferred during the
  first scaffold pass (couldn't verify a structural migration blind in a
  sandbox with no JDK/Gradle) and only done once a human had a real,
  iterating build to catch mistakes against.
