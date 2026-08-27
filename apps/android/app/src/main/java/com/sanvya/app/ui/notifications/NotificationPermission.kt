package com.sanvya.app.ui.notifications

import androidx.compose.runtime.compositionLocalOf

/**
 * Asks the OS for POST_NOTIFICATIONS and reports the answer.
 *
 * A CompositionLocal because an `ActivityResultLauncher` has to be registered
 * on the Activity BEFORE it starts, so no composable can own one — and the
 * screen that needs the answer (Settings) is several levels down the tree from
 * the Activity that can ask.
 *
 * The default throws rather than silently answering "no". A Settings screen
 * whose push switch quietly refuses to turn on, with no prompt and no error, is
 * far harder to diagnose than a crash in a preview.
 */
val LocalNotificationPermissionRequester = compositionLocalOf<(onResult: (Boolean) -> Unit) -> Unit> {
    error("No LocalNotificationPermissionRequester provided — MainActivity must supply one.")
}
