// :data — Android library module for the data layer.
// Depends on PowerSync Kotlin SDK (KMP, includes Android) and supabase-kt.
// These are from plan §0's approved irreducible dependency set.
// Unlike :domain, this module CAN have Android SDK imports — it's the boundary
// between pure domain logic and OS/network concerns.
//
// P2.2a: SupabaseConnector (PowerSync backend connector) + Quarantine (dead-letter)
// P2.4a: Auth helpers (guest sign-in, in-place upgrade, offline marker)
plugins {
    alias(libs.plugins.android.library)
    // AGP 9.0+ built-in Kotlin handles Kotlin compilation for Android libs too.
    // No separate kotlin.android plugin needed (it's a hard error alongside AGP 9.x).
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.sanvya.app.data"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    // Internal dependency on the pure-Kotlin domain layer (sync-policy, diagnostics).
    implementation(project(":domain"))

    // P2.2a / P2.4a: approved irreducible third-party set (plan §0).
    implementation(libs.powersync.core)

    // supabase-kt BOM manages all supabase-kt module versions.
    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.postgrest)
    implementation(libs.supabase.auth)
    implementation(libs.supabase.functions)

    // Ktor OkHttp engine — required by supabase-kt on Android.
    implementation(libs.ktor.client.okhttp)

    // kotlinx.serialization JSON — needed for encodePayload/buildJsonObject
    // in Quarantine.kt and SupabaseConnector.kt (JsonObject payloads for
    // supabase-kt's Serializable PostgREST API). Already approved for :domain
    // in test scope (P0.4a); here it ships in production.
    implementation(libs.kotlinx.serialization.json)

    // Unit tests for pure-logic parts (opKey, AuthState, encodePayload).
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlin.test.junit)

    implementation(libs.koin.android)
}
