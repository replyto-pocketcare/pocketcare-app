// No kotlin.android plugin: AGP 9.0+ built-in Kotlin compiles :app's Kotlin
// sources without it (see gradle/libs.versions.toml). Applying kotlin.android
// alongside AGP 9.x is now a hard error.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.google.services)
}

// Same resolution order as :data's copy (extra ← local.properties, then
// gradle.properties, then -P). :app needs two of the keys at manifest-merge
// time, which is why the lookup exists in both places rather than only in the
// module that owns SanvyaConfig.
fun sanvyaConfig(key: String): String =
    findProperty("sanvya.$key") as String?
        ?: error("Missing configuration 'sanvya.$key'. Add it to gradle.properties, local.properties, or pass -Psanvya.$key=…")

android {
    namespace = "com.sanvya.app"
    // PLACEHOLDER — confirm the real reverse-DNS applicationId before any
    // store submission (plan §10; same open item as the RN scaffold hit).
    // compileSdk/targetSdk 36: Google Play requires new apps/updates to
    // target API 36 by 2026-08-31 (verified via search 2026-07-31) — this
    // app is new, so target it from the start rather than bumping later.
    compileSdk = 36

    defaultConfig {
        applicationId = "com.sanvya.app"
        // PLACEHOLDER — proposal only, needs a human "yes" (plan §10).
        // 26 = Android 8.0 (Oreo). Covers the vast majority of active
        // devices while giving access to modern Compose/notification APIs
        // without extra compat shims.
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.0.1"

        // Feeds the OAuth callback intent filter in AndroidManifest.xml from
        // the same two Gradle properties that produce SanvyaConfig's
        // authRedirectUri. Hand-writing the scheme into the manifest would
        // make it possible for the URI the app asks the provider to return to
        // and the URI the app is registered to receive to disagree -- a
        // failure that shows up as the browser simply never coming back, with
        // nothing in logcat to say why.
        manifestPlaceholders["authRedirectScheme"] = sanvyaConfig("authRedirectScheme")
        manifestPlaceholders["authRedirectHost"] = sanvyaConfig("authRedirectHost")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // No explicit kotlin.compilerOptions.jvmTarget block: under built-in
    // Kotlin (AGP 9.0+) it defaults from compileOptions.targetCompatibility
    // above (17), per developer.android.com/build/migrate-to-built-in-kotlin
    // step 3. Setting it separately would just be a second place to keep in
    // sync — and the old kotlinOptions{} setter it used to need is now a
    // hard compile error anyway.
    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(project(":domain"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.core)
    implementation(libs.compose.material.icons.extended)
    debugImplementation(libs.compose.ui.tooling)
    
    implementation(project(":data"))
    
    implementation(libs.koin.android)
    implementation(libs.koin.androidx.compose)
    implementation(libs.androidx.navigation.compose)

    // Task #62 (Receipt Scan capture): camera preview + in-memory frame
    // capture, on-device OCR. See docs/mobile/screen-specs/receipt-scan.md.
    implementation(libs.camerax.core)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    implementation(libs.mlkit.text.recognition)

    // Firebase
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    // W1.5: :app had no test source set at all. Added for the device-type and
    // window-class mapping -- both are small pure functions, and both decide
    // things (portrait lock, sidebar vs bottom bar) whose failure mode is
    // "wrong on a device nobody has to hand".
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlin.test.junit)
}
