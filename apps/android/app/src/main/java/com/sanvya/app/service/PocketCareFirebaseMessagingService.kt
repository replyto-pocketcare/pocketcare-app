package com.sanvya.app.service

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.domain.repository.PushRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.koin.android.ext.android.inject

class PocketCareFirebaseMessagingService : FirebaseMessagingService() {

    private val pushRepository: PushRepository by inject()
    private val authRepository: AuthRepository by inject()
    private val serviceScope = CoroutineScope(Dispatchers.IO)

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        serviceScope.launch {
            val userId = authRepository.currentUserId.value
            if (userId != null) {
                try {
                    pushRepository.registerToken(token, "android", userId)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        // Foreground notifications are typically handled here if we want custom UI,
        // but FCM handles background notification tray generation automatically 
        // if the payload has a 'notification' block.
    }
}
