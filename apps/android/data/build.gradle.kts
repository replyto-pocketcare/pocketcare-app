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

// Reads a `sanvya.*` configuration key. findProperty() already searches, in
// order: extra properties (settings.gradle.kts folds local.properties into
// these), gradle.properties, and -P on the command line.
//
// Missing is a hard error rather than an empty default: a build that silently
// produces an app pointed at nothing is far more expensive to diagnose than a
// build that refuses to run.
fun sanvyaConfig(key: String): String =
    findProperty("sanvya.$key") as String?
        ?: error("Missing configuration 'sanvya.$key'. Add it to gradle.properties, local.properties, or pass -Psanvya.$key=…")

android {
    namespace = "com.sanvya.app.data"
    compileSdk = 36

    defaultConfig {
        minSdk = 26

        // Every one of these was a string literal in DataModule.kt. They are
        // build inputs now, so a different Supabase project is a property
        // change, not a source edit. SanvyaConfig (config/SanvyaConfig.kt) is
        // the only thing that reads BuildConfig — nothing outside :data does.
        buildConfigField("String", "SUPABASE_URL", "\"${sanvyaConfig("supabaseUrl")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${sanvyaConfig("supabaseAnonKey")}\"")
        buildConfigField("String", "POWERSYNC_URL", "\"${sanvyaConfig("powerSyncUrl")}\"")
        buildConfigField("String", "AUTH_REDIRECT_SCHEME", "\"${sanvyaConfig("authRedirectScheme")}\"")
        buildConfigField("String", "AUTH_REDIRECT_HOST", "\"${sanvyaConfig("authRedirectHost")}\"")
    }

    buildFeatures {
        buildConfig = true
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

    // Custom Tabs, for the Google sign-in browser flow supabase-kt launches
    // from this module. Declared explicitly rather than relied on transitively:
    // if it is absent the flow falls back to a full browser app-switch that
    // drops the back stack on some OEMs, which is easy to mistake for a
    // Supabase misconfiguration. It lives here, not in :app, because :app never
    // touches the auth flow directly -- that was the whole bug above.
    implementation(libs.androidx.browser)

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
