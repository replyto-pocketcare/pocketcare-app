package com.sanvya.app.ui.goals

import android.content.Context
import android.content.SharedPreferences
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Which goals have already had their celebration.
 *
 * Web keeps this in `localStorage` under `pc_goals_celebrated`; the key is the
 * same here so the two platforms describe the same thing, even though the
 * storage is a `SharedPreferences` string set rather than a JSON array. Not
 * synced -- it is a note about what this device has already shown someone, not
 * ledger data, and syncing it would silence the moment on a second device that
 * has never seen it.
 *
 * Deliberately NOT part of `ui/Prefs.kt`. That object is the mirror of web's
 * `prefs.ts` -- settings the user chose. This is feature-local bookkeeping with
 * no settings screen behind it, and putting it there would make `Prefs` the
 * place any screen dumps a flag.
 */
object GoalCelebrationStore : KoinComponent {
    private const val PREFS_NAME = "sanvya_prefs"
    private const val CELEBRATED_KEY = "pc_goals_celebrated"

    private val context: Context by inject()

    // `by lazy`, not a field initializer: Koin's Context is not available until
    // the app has actually started -- same reason Prefs.kt defers its own.
    private val sharedPrefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /** A COPY: SharedPreferences documents the returned set as one that must
     *  not be mutated, and the domain decision hands back a new set anyway. */
    fun celebrated(): Set<String> =
        sharedPrefs.getStringSet(CELEBRATED_KEY, emptySet())?.toSet() ?: emptySet()

    fun save(ids: Set<String>) {
        sharedPrefs.edit().putStringSet(CELEBRATED_KEY, ids).apply()
    }
}
