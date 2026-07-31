// Pure Kotlin — deliberately NO com.android.library plugin and no Android
// SDK dependency. This is what makes the domain layer fast to test
// (plain JVM, no emulator) and honest (it cannot reach for an Android API
// as a shortcut). See docs/plans/native-mobile-apps.md §4 (P0.2) and §0
// golden rule 8 ("web is the spec").
plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlin.test.junit)
}
