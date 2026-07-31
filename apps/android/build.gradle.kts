// Root build file — declares plugin versions once (via the version catalog)
// so every module applies them without re-specifying a version.
//
// No kotlin.android here: AGP 9.0+ built-in Kotlin replaces it for Android
// modules (see gradle/libs.versions.toml). kotlin.jvm remains for :domain
// (plain JVM module, not Android).
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.compose.compiler) apply false
}
