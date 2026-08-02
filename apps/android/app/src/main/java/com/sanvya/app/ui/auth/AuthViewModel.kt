package com.sanvya.app.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.auth.AuthState
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class AuthViewModel(
    private val authRepository: AuthRepository
) : ViewModel() {

    val authState: StateFlow<AuthState> = authRepository.authState.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = AuthState.SIGNED_OUT
    )

    fun ensureGuest(onComplete: () -> Unit) {
        viewModelScope.launch {
            try {
                authRepository.ensureGuest()
                onComplete()
            } catch (e: Exception) {
                // Handle error
            }
        }
    }

    fun sendOtp(email: String, onSent: () -> Unit) {
        viewModelScope.launch {
            try {
                authRepository.sendOtp(email)
                onSent()
            } catch (e: Exception) {
                // Handle error
            }
        }
    }

    fun verifyOtp(email: String, token: String, onVerified: () -> Unit) {
        viewModelScope.launch {
            try {
                authRepository.verifyOtp(email, token)
                onVerified()
            } catch (e: Exception) {
                // Handle error
            }
        }
    }

    fun signUp(email: String, password: String, username: String, onComplete: () -> Unit, onError: (String) -> Unit) {
        viewModelScope.launch {
            try {
                authRepository.signUp(email, password, username)
                onComplete()
            } catch (e: Exception) {
                onError(e.message ?: "An error occurred")
            }
        }
    }

    fun signInWithPassword(email: String, password: String, onComplete: () -> Unit, onError: (String) -> Unit) {
        viewModelScope.launch {
            try {
                authRepository.signInWithPassword(email, password)
                onComplete()
            } catch (e: Exception) {
                onError(e.message ?: "An error occurred")
            }
        }
    }
}
