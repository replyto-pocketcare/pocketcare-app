pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "sanvya-android"

// :domain is pure Kotlin (no Android SDK dependency) — this is what makes it
// vector-testable with plain `kotlin.test` and keeps the domain logic honest
// (see docs/plans/native-mobile-apps.md §4, P0.2 and §0 golden rules).
include(":app")
include(":domain")
// :data is an Android library module — it depends on the PowerSync Kotlin SDK
// and supabase-kt and therefore CAN have Android SDK deps (unlike :domain).
// It holds the connector, quarantine logic, and auth helpers (P2.2a, P2.4a).
include(":data")

// ---------------------------------------------------------------------------
// local.properties overrides for the `sanvya.*` configuration keys.
//
// gradle.properties holds the committed defaults. A developer (or a release
// pipeline) pointing the build at a different Supabase project drops the same
// keys into local.properties, which git ignores, and gets them without editing
// a tracked file.
//
// Folding them into each project's extra properties — rather than reading the
// file in every build script — means the build scripts only ever call
// findProperty(), which already searches extra, gradle.properties and -P in
// that order. One lookup, three sources, no per-module file parsing.
// ---------------------------------------------------------------------------
val localProperties = java.util.Properties().apply {
    val f = rootDir.resolve("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
gradle.beforeProject {
    localProperties
        .filterKeys { it.toString().startsWith("sanvya.") }
        .forEach { (key, value) -> extra[key.toString()] = value.toString() }
}
