package com.sanvya.app.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.auth.AuthState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Sign-in state for `LoginScreen`.
 *
 * **Every one of these used to end in `catch (e: Exception) { // Handle error }`.**
 * A failed OTP send did nothing at all: no message, and the success callback
 * never fired, so the screen simply did not advance and the user had no idea
 * why. Errors are surfaced now — a swallowed error is the same failure as a
 * dead button, one layer down.
 */
class AuthViewModel : ViewModel(), KoinComponent {
    // `by inject()` rather than constructor injection: no view model in this app
    // is registered with Koin, and `viewModel()` needs a no-arg constructor.
    // Matching AccountsViewModel and the rest rather than introducing a second
    // wiring style for one screen.
    private val authRepository: AuthRepository by inject()

    val authState: StateFlow<AuthState> = authRepository.authState.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AuthState.SIGNED_OUT
    )

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    /** True once a code has been sent, so the screen shows the code step. */
    private val _otpSent = MutableStateFlow(false)
    val otpSent: StateFlow<Boolean> = _otpSent.asStateFlow()

    fun clearError() { _error.value = null }

    fun backToEmail() {
        _otpSent.value = false
        _error.value = null
    }

    /**
     * Runs one auth call, reporting failure rather than hiding it.
     *
     * `onSuccess` fires ONLY on success. The old code called its callback
     * inside the `try` after the await, which was right, but the empty `catch`
     * meant a failure was indistinguishable from a call that never happened.
     */
    private fun run(onSuccess: () -> Unit = {}, block: suspend () -> Unit) {
        viewModelScope.launch {
            _busy.value = true
            _error.value = null
            try {
                block()
                onSuccess()
            } catch (e: Exception) {
                _error.value = e.message ?: "Something went wrong. Please try again."
            } finally {
                _busy.value = false
            }
        }
    }

    fun ensureGuest(onComplete: () -> Unit = {}) = run(onComplete) { authRepository.ensureGuest() }

    fun sendOtp(email: String) = run({ _otpSent.value = true }) { authRepository.sendOtp(email) }

    fun verifyOtp(email: String, token: String, onVerified: () -> Unit = {}) =
        run(onVerified) { authRepository.verifyOtp(email, token) }

    fun signUp(email: String, password: String, username: String, onComplete: () -> Unit = {}) =
        run(onComplete) { authRepository.signUp(email, password, username) }

    fun signInWithPassword(email: String, password: String, onComplete: () -> Unit = {}) =
        run(onComplete) { authRepository.signInWithPassword(email, password) }

    /**
     * Continue with Google.
     *
     * Deliberately takes no success callback. Everything else here finishes
     * when the suspend call returns; this one only *launches a browser*, and
     * the session appears later when the OS routes the callback URI back into
     * MainActivity. A callback would fire the moment the Custom Tab opened,
     * which is precisely the kind of control that looks like it worked and did
     * not.
     *
     * `busy` is not cleared on success either: the app is going to the
     * background, and a spinner that keeps spinning until the callback lands is
     * the honest state. It clears on failure, which is when the user is still
     * looking at this screen.
     */
    fun continueWithGoogle() = run { authRepository.continueWithGoogle() }
}
