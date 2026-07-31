// Pure Kotlin — deliberately NO com.android.library plugin and no Android
// SDK dependency. This is what makes the domain layer fast to test
// (plain JVM, no emulator) and honest (it cannot reach for an Android API
// as a shortcut). See docs/plans/native-mobile-apps.md §4 (P0.2) and §0
// golden rule 8 ("web is the spec").
plugins {
    alias(libs.plugins.kotlin.jvm)
    // P0.4a: test-only, for parsing tools/golden-vectors/vectors/*.json.
    // Human-approved 2026-07-31 (a real dependency decision, since :domain
    // has no Android SDK and thus no free JSON parser) — see
    // gradle/libs.versions.toml's kotlinxSerializationJson comment.
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(17)
}

// The golden vectors live in tools/golden-vectors/vectors/ at the repo
// root — the single fixture source shared with the iOS runner (plan §3).
// Pointing the test resources source set at it directly (rather than
// copying) means there's nothing here to fall out of sync; Gradle
// resolves relative paths against this module's own directory
// (apps/android/domain/) — three levels up (domain -> android -> apps)
// reaches the repo root.
sourceSets {
    test {
        resources.srcDir("../../../tools/golden-vectors/vectors")
    }
}

dependencies {
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlin.test.junit)
    testImplementation(libs.kotlinx.serialization.json)
}
