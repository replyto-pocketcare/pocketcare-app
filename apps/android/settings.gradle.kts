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

rootProject.name = "pocketcare-android"

// :domain is pure Kotlin (no Android SDK dependency) — this is what makes it
// vector-testable with plain `kotlin.test` and keeps the domain logic honest
// (see docs/plans/native-mobile-apps.md §4, P0.2 and §0 golden rules).
include(":app")
include(":domain")
// :data is an Android library module — it depends on the PowerSync Kotlin SDK
// and supabase-kt and therefore CAN have Android SDK deps (unlike :domain).
// It holds the connector, quarantine logic, and auth helpers (P2.2a, P2.4a).
include(":data")
