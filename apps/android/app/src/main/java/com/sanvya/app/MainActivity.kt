package com.sanvya.app

import android.content.Intent
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.data.auth.AuthState
import com.sanvya.app.ui.auth.AuthViewModel
import com.sanvya.app.ui.Prefs
import com.sanvya.app.ui.auth.LoginScreen
import com.sanvya.app.ui.onboarding.OnboardingDeckScreen
import com.sanvya.app.ui.navigation.SanvyaNavHost
import com.sanvya.app.ui.shell.ProvideWindowClass
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

        // Google (and any future provider) returns the browser to
        // `<scheme>://<host>` -- the intent filter in AndroidManifest.xml
        // routes it here, and this is what turns that URI into a session.
        //
        // Both entry points are needed. A cold start arrives through onCreate's
        // intent; a warm one -- the far more common case, since the app is
        // still in the background behind the Custom Tab -- arrives through
        // onNewIntent. Wiring only onCreate produces the flow that works
        // exactly once, on the first launch after install, and then silently
        // stops working, which is a miserable thing to debug.
        authRepository.handleAuthCallback(intent)

        askNotificationPermission()
        
        setContent {
            SanvyaTheme {
                // Publishes the window class and device type, and applies the
                // orientation policy (phones portrait; tablets and foldables
                // free). Wraps everything, including the nav host, because a
                // width-class change must reach every screen -- not just the
                // shell's own chrome.
                ProvideWindowClass {
                    // The auth gate web has had all along: no session, no app.
                    // Android went straight to the dashboard and silently
                    // created a guest, so there was no way to sign in as
                    // yourself and no way to know you had not.
                    val authViewModel: AuthViewModel = viewModel()
                    val authState by authViewModel.authState.collectAsState()
                    // Web's gate replaces to `/onboarding` before `/login`, and
                    // this app skipped that step entirely -- the seven-slide
                    // deck existed on the web client only. Read once, not
                    // observed: it changes exactly once in a lifetime.
                    var onboardingSeen by rememberSaveable { mutableStateOf(Prefs.onboardingSeen()) }
                    if (authState == AuthState.SIGNED_OUT) {
                        if (onboardingSeen) {
                            LoginScreen()
                        } else {
                            // The deck's "try as guest" exit creates the session
                            // itself, so `authState` moves the app on and this
                            // branch is never reached again. The other two
                            // exits fall through to LoginScreen.
                            OnboardingDeckScreen(onDone = {
                                Prefs.setOnboardingSeen()
                                onboardingSeen = true
                            })
                        }
                    } else {
                        SanvyaNavHost()
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        authRepository.handleAuthCallback(intent)
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
