package com.sanvya.app

import android.app.Application
import com.sanvya.app.data.di.dataModule
import com.sanvya.app.data.sync.SyncBootstrap
import com.sanvya.app.di.appModule
import org.koin.android.ext.android.get
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin

/**
 * App entry point — DI bootstrap, then sync.
 *
 * `AndroidManifest.xml`'s `<application android:name>` was already pointing at
 * a class (`.android.SanvyaApp`) that never existed (verified 2026-08-05,
 * another dangling reference alongside SanvyaTheme/SanvyaNavHost/Prefs — Koin
 * was never started anywhere in the app, so every `by inject()` call would have
 * crashed at runtime even if the rest of the app compiled). Corrected the
 * manifest to point here.
 */
class SanvyaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        startKoin {
            androidLogger()
            androidContext(this@SanvyaApplication)
            modules(dataModule, appModule)
        }
        // Connect PowerSync to the server, and keep that connection matched to
        // whoever is signed in. Web does this in `initSystem()`; until this line
        // existed the app never called `connect()` at all and was a purely local
        // database -- see SyncBootstrap.kt for the full story.
        //
        // Started here rather than from a screen because it must outlive
        // navigation: a sync connection that exists only while one screen is
        // mounted is a sync connection that stops when the user changes tab.
        //
        // `start()` returns immediately; everything it does is on its own IO
        // scope, so this does not delay `onCreate`.
        get<SyncBootstrap>().start()
    }
}
