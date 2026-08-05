package com.sanvya.app

import android.app.Application
import com.sanvya.app.data.di.dataModule
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin

/**
 * App entry point — DI bootstrap. `AndroidManifest.xml`'s `<application
 * android:name>` was already pointing at a class (`.android.SanvyaApp`) that
 * never existed (verified 2026-08-05, another dangling reference alongside
 * SanvyaTheme/SanvyaNavHost/Prefs — Koin was never started anywhere in the
 * app, so every `by inject()` call would have crashed at runtime even if the
 * rest of the app compiled). Corrected the manifest to point here.
 */
class SanvyaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        startKoin {
            androidLogger()
            androidContext(this@SanvyaApplication)
            modules(dataModule)
        }
    }
}
