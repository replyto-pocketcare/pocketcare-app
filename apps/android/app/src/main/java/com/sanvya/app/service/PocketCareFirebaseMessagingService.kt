package com.sanvya.app.service

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.data.repository.nowIso
import com.sanvya.app.domain.notifications.shouldRegisterAtLaunch
import com.sanvya.app.domain.repository.PushRepository
import com.sanvya.app.ui.notifications.PushController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.koin.android.ext.android.inject

/**
 * FCM's side of push: token rotation, and the channel every alert lands on.
 *
 * `onNewToken` used to register unconditionally, which meant a user who had
 * never turned push on — or had turned it off — was silently re-added to
 * `push_subscriptions` the next time Android rotated their token. The gate is
 * the same `shouldRegisterAtLaunch` the app itself uses.
 */
class PocketCareFirebaseMessagingService : FirebaseMessagingService() {

    private val pushRepository: PushRepository by inject()
    private val authRepository: AuthRepository by inject()
    private val prefsRepository: PrefsRepository by inject()

    // SupervisorJob so one failed registration cannot cancel the scope and take
    // every later token rotation with it. The old scope had no job at all,
    // which is the same shape of bug with a longer fuse.
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        // A message can arrive before any screen has run, and a notification
        // posted to a channel that does not exist is dropped silently on
        // Android 8+.
        PushController(applicationContext).ensureChannel()
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        serviceScope.launch {
            val userId = authRepository.currentUserId.value ?: return@launch
            val prefs = runCatching { prefsRepository.getNotificationPrefs(userId) }.getOrNull()
            val controller = PushController(applicationContext)
            if (!shouldRegisterAtLaunch(controller.permission(), prefs?.push_enabled == 1L)) return@launch
            runCatching { pushRepository.registerToken(token, PushController.PLATFORM, userId, nowIso()) }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        // Deliberately empty. A payload carrying a `notification` block is
        // rendered by FCM itself, including in the background, which is the
        // only case the dispatcher sends today. Building a second, hand-rolled
        // notification here would double every foreground alert.
    }
}
