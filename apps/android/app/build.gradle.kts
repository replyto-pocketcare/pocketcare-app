import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.compose.compiler)
}

android {
    namespace = "care.pocket.android"
    // PLACEHOLDER — confirm the real reverse-DNS applicationId before any
    // store submission (plan §10; same open item as the RN scaffold hit).
    // compileSdk/targetSdk 36: Google Play requires new apps/updates to
    // target API 36 by 2026-08-31 (verified via search 2026-07-31) — this
    // app is new, so target it from the start rather than bumping later.
    compileSdk = 36

    defaultConfig {
        applicationId = "care.pocket.android"
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

    buildFeatures {
        compose = true
    }
}

// kotlinOptions { jvmTarget = "17" } is a hard error as of this Kotlin
// Gradle plugin version ("Using 'jvmTarget: String' is an error. Please
// migrate to the compilerOptions DSL") — this is the replacement.
kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
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
    debugImplementation(libs.compose.ui.tooling)
}
