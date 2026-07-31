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
