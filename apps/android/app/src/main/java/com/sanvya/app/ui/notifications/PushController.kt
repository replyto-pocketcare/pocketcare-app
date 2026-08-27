package com.sanvya.app.ui.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import com.sanvya.app.R
import com.sanvya.app.data.repository.nowIso
import com.sanvya.app.domain.repository.PushRepository
import kotlinx.coroutines.suspendCancellableCoroutine
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Everything the app does with the OS notification system, in one place.
 *
 * Ported from `apps/web/src/notifications/push.ts`, whose four exported
 * functions this mirrors: read the permission, subscribe, send a local test,
 * and unsubscribe. Mirrors iOS's PushController.swift.
 *
 * **Permission is NOT asked at launch any more.** `MainActivity.onCreate` used
 * to call `askNotificationPermission()` in its first frame, before the user had
 * seen a single screen — the classic way to earn a permanent refusal from
 * someone who had no idea what they were being asked about. Web asks only when
 * the toggle is turned on; so does this now.
 */
class PushController(private val context: Context) : KoinComponent {
    private val pushRepository: PushRepository by inject()

    /** "granted" | "denied" | "notDetermined", as `pushState()` expects. */
    fun permission(): String {
        if (!supported()) return "denied"
        // Below API 33 there is no runtime permission at all -- notifications
        // are granted at install time, and the only way to refuse is the
        // system settings screen, which `areNotificationsEnabled()` reflects.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return if (NotificationManagerCompat.from(context).areNotificationsEnabled()) "granted" else "denied"
        }
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return "granted"
        // Android cannot distinguish "never asked" from "refused twice" without
        // remembering that we asked. `asked` is that memory: without it every
        // refusal would read as notDetermined and the row would offer a switch
        // that can no longer do anything.
        return if (asked()) "denied" else "notDetermined"
    }

    fun supported(): Boolean = true

    /**
     * The current device token, or null when Firebase cannot mint one (no Play
     * Services, no network on first run, a stale `google-services.json`).
     *
     * Wrapped rather than callback-style so the caller can `try`/`catch` it
     * like any other failure -- the old code used `addOnCompleteListener` and
     * dropped a failed task on the floor with `return@addOnCompleteListener`.
     */
    suspend fun currentToken(): String = suspendCancellableCoroutine { cont ->
        FirebaseMessaging.getInstance().token
            .addOnSuccessListener { token -> if (cont.isActive) cont.resume(token) }
            .addOnFailureListener { e -> if (cont.isActive) cont.resumeWithException(e) }
    }

    /**
     * Register this device against [userId].
     *
     * Assumes permission is already granted -- the permission request itself is
     * an Activity concern (it needs a result launcher), so the screen asks and
     * then calls this.
     */
    suspend fun register(userId: String): String {
        val token = currentToken()
        pushRepository.registerToken(token, PLATFORM, userId, nowIso())
        return token
    }

    /** Drop this device's token. The OS permission is deliberately left alone. */
    suspend fun unregister() {
        val token = runCatching { currentToken() }.getOrNull() ?: return
        pushRepository.unregisterToken(token)
    }

    /**
     * Fire a notification locally — no server, no FCM.
     *
     * Web's `sendTestNotification` explains why this earns its place: it proves
     * permission and the delivery path work on THIS device, so when it shows
     * and real alerts do not, the gap is the server dispatch and not the phone.
     * That is the single most useful thing a support conversation can
     * establish.
     */
    fun sendTest(): Boolean {
        if (permission() != "granted") return false
        ensureChannel()
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(TEST_TITLE)
            .setContentText(TEST_BODY)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()
        return try {
            NotificationManagerCompat.from(context).notify(TEST_ID, notification)
            true
        } catch (e: SecurityException) {
            // Permission revoked between the check and the post. Rare, but the
            // API is documented to throw and a crash here would be absurd.
            false
        }
    }

    /**
     * The channel every Sanvya notification arrives on.
     *
     * Created on demand rather than at launch: a channel appears in the user's
     * system settings the moment it exists, and listing notification categories
     * for an app that has never asked to notify anyone is noise.
     */
    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = CHANNEL_DESCRIPTION
            },
        )
    }

    /** Remembers that we have shown the runtime prompt at least once. */
    fun markAsked() {
        prefs().edit().putBoolean(ASKED_KEY, true).apply()
    }

    private fun asked(): Boolean = prefs().getBoolean(ASKED_KEY, false)

    private fun prefs() = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    companion object {
        const val PLATFORM = "android"
        const val CHANNEL_ID = "sanvya_alerts"

        private const val CHANNEL_NAME = "Alerts"
        private const val CHANNEL_DESCRIPTION =
            "Bills, budgets, low balances and unusual spend."
        private const val PREFS_NAME = "sanvya_push"
        private const val ASKED_KEY = "postNotificationsAsked"
        private const val TEST_ID = 4242

        // English on all three platforms, because it is English on web --
        // `sendTestNotification` writes these as literals too. See
        // PARITY_AUDIT's i18n row.
        const val TEST_TITLE = "Sanvya"
        const val TEST_BODY = "Test notification — you're all set to receive alerts."
    }
}
