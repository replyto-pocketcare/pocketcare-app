package com.sanvya.app

import android.os.Bundle
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.google.firebase.messaging.FirebaseMessaging
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.domain.repository.PushRepository
import com.sanvya.app.theme.SanvyaTheme
import com.sanvya.app.ui.navigation.SanvyaNavHost
import kotlinx.coroutines.launch
import org.koin.android.ext.android.inject

class MainActivity : ComponentActivity() {
    private val pushRepository: PushRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted: Boolean ->
        if (isGranted) {
            fetchAndRegisterToken()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        askNotificationPermission()
        
        setContent {
            SanvyaTheme {
                SanvyaNavHost()
            }
        }
    }

    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                fetchAndRegisterToken()
            } else {
                requestPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        } else {
            fetchAndRegisterToken()
        }
    }

    private fun fetchAndRegisterToken() {
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) return@addOnCompleteListener
            val token = task.result
            lifecycleScope.launch {
                // authRepository.currentUserId is a StateFlow<String?>, not a
                // plain property -- `val userId = authRepository.currentUserId`
                // (missing `.value`) was a type mismatch that would never have
                // compiled (StateFlow passed where registerToken() wants a
                // String). Found + fixed 2026-08-05 while wiring Accounts,
                // which needs the same currentUserId.value pattern.
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
    }
}
