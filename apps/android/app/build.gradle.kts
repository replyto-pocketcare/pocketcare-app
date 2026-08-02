// No kotlin.android plugin: AGP 9.0+ built-in Kotlin compiles :app's Kotlin
// sources without it (see gradle/libs.versions.toml). Applying kotlin.android
// alongside AGP 9.x is now a hard error.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
    id("com.google.gms.google-services")
}

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
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation(libs.compose.ui.tooling)
    
    implementation(project(":data"))
    
    implementation(libs.koin.android)
    implementation(libs.koin.androidx.compose)
    
    // Firebase
    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-messaging")
}
