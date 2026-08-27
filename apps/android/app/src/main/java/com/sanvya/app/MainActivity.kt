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
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.domain.notifications.shouldRegisterAtLaunch
import com.sanvya.app.ui.notifications.LocalNotificationPermissionRequester
import com.sanvya.app.ui.notifications.PushController
import com.sanvya.app.theme.SanvyaTheme
import androidx.compose.runtime.CompositionLocalProvider
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
    private val authRepository: AuthRepository by inject()
    private val prefsRepository: PrefsRepository by inject()
    private val pushController by lazy { PushController(applicationContext) }

    /**
     * The runtime prompt, fired from Settings rather than from launch.
     *
     * `pendingPermissionResult` is how the Compose side hears the answer: a
     * result launcher must be registered on the Activity before it starts, so
     * the screen cannot own one, and a callback that only ever calls
     * `fetchAndRegisterToken()` (as this did) leaves the switch it was tapped
     * from still showing "off".
     */
    private var pendingPermissionResult: ((Boolean) -> Unit)? = null

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { isGranted: Boolean ->
        pushController.markAsked()
        pendingPermissionResult?.invoke(isGranted)
        pendingPermissionResult = null
    }

    /**
     * Ask for POST_NOTIFICATIONS, or answer immediately when there is nothing
     * to ask -- below API 33 the permission does not exist, and an already
     * granted one must not re-prompt.
     */
    private fun requestNotificationPermission(onResult: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            onResult(pushController.permission() == "granted")
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            onResult(true)
            return
        }
        pendingPermissionResult = onResult
        requestPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
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

        // NOT a permission request. This used to be `askNotificationPermission()`,
        // which put the system prompt in the first frame of the first launch --
        // before the user had seen a single screen, and with nothing on screen
        // to explain what they were agreeing to. Permission is asked from
        // Settings now, when the switch is turned on.
        //
        // What is left is the half that asks for nothing: a token can be
        // rotated by the OS at any time, so a user who opted in last week and
        // has a new token today would silently stop receiving anything.
        reRegisterIfAlreadyOptedIn()
        
        setContent {
            SanvyaTheme {
                // Publishes the window class and device type, and applies the
                // orientation policy (phones portrait; tablets and foldables
                // free). Wraps everything, including the nav host, because a
                // width-class change must reach every screen -- not just the
                // shell's own chrome.
                CompositionLocalProvider(
                    LocalNotificationPermissionRequester provides ::requestNotificationPermission,
                ) {
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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        authRepository.handleAuthCallback(intent)
    }

    /**
     * Refresh this device's token, but only when permission is ALREADY granted
     * and the user has ALREADY opted in. The rule is
     * [shouldRegisterAtLaunch], shared with iOS and vector-pinned.
     */
    private fun reRegisterIfAlreadyOptedIn() {
        lifecycleScope.launch {
            // currentUserId is a StateFlow<String?>, not a plain property --
            // the missing `.value` was a real compile error here once.
            val userId = authRepository.currentUserId.value ?: return@launch
            val prefs = runCatching { prefsRepository.getNotificationPrefs(userId) }.getOrNull()
            if (!shouldRegisterAtLaunch(pushController.permission(), prefs?.push_enabled == 1L)) return@launch
            // Swallowed on purpose, and ONLY here: this is a background refresh
            // the user did not ask for, and it retries on the next launch. The
            // repository itself no longer swallows anything, so the path the
            // user DID ask for reports its failures.
            runCatching { pushController.register(userId) }
        }
    }
}
