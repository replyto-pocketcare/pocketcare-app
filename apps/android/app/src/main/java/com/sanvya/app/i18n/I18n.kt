package com.sanvya.app.i18n

import android.content.res.Resources
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext

/**
 * The `Resources` a composable should hand to `S`.
 *
 * `S.kt`'s own doc comment has referred to this file since the generator was
 * written; it was never created, and that is the likeliest reason 1,600 typed
 * accessors sat unused while ~700 English literals stayed inline. Reaching for
 * `LocalContext.current.resources` at every call site is enough friction to
 * lose the argument to "just type the string".
 *
 * ```kotlin
 * Text(S.Translation.navHome(sRes()))
 * ```
 *
 * **Reading `LocalConfiguration` is the load-bearing line**, not defensive
 * noise. `LocalContext` does not change when the locale does, so a composable
 * that only read it would keep rendering the language the app started in until
 * something else happened to invalidate it. Touching the configuration
 * subscribes this composable to it, which is exactly what `stringResource()`
 * does internally and why it recomposes correctly.
 *
 * View models and services take a `Resources` directly — they are outside
 * composition, so there is nothing to subscribe to.
 */
@Composable
@ReadOnlyComposable
fun sRes(): Resources {
    LocalConfiguration.current
    return LocalContext.current.resources
}
