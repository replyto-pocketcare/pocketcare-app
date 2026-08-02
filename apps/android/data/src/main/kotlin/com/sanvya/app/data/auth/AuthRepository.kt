package com.sanvya.app.data.auth

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

interface AuthRepository {
    val currentUserId: StateFlow<String?>
    val authState: Flow<AuthState>
    
    suspend fun ensureGuest(): String
    suspend fun signInWithGoogle(idToken: String)
    suspend fun sendOtp(email: String)
    suspend fun verifyOtp(email: String, token: String)
    suspend fun signUp(email: String, password: String, username: String)
    suspend fun signInWithPassword(email: String, password: String)
    suspend fun signOut()
}

class AuthRepositoryImpl(
    private val client: SupabaseClient
) : AuthRepository {

    private val _currentUserId = MutableStateFlow<String?>(null)
    override val currentUserId: StateFlow<String?> = _currentUserId.asStateFlow()

    override val authState: Flow<AuthState> = client.auth.sessionStatus.map { status ->
        when (status) {
            is SessionStatus.Authenticated -> AuthState.SIGNED_IN_ONLINE // Simplified for now
            else -> AuthState.SIGNED_OUT
        }
    }

    init {
        // Collect session status from Supabase to update currentUserId
        kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            client.auth.sessionStatus.collect { status ->
                _currentUserId.value = when (status) {
                    is SessionStatus.Authenticated -> status.session.user?.id
                    else -> null
                }
            }
        }
    }

    override suspend fun ensureGuest(): String {
        return ensureUser(client)
    }

    override suspend fun signInWithGoogle(idToken: String) {
        com.sanvya.app.data.auth.signInWithGoogle(client, idToken)
    }

    override suspend fun sendOtp(email: String) {
        com.sanvya.app.data.auth.sendOtp(client, email)
    }

    override suspend fun verifyOtp(email: String, token: String) {
        com.sanvya.app.data.auth.verifyOtp(client, email, token)
    }

    override suspend fun signUp(email: String, password: String, username: String) {
        client.auth.signUpWith(io.github.jan.supabase.auth.providers.builtin.Email) {
            this.email = email
            this.password = password
            // Note: username could be sent in data if needed
        }
    }

    override suspend fun signInWithPassword(email: String, password: String) {
        client.auth.signInWith(io.github.jan.supabase.auth.providers.builtin.Email) {
            this.email = email
            this.password = password
        }
    }

    override suspend fun signOut() {
        com.sanvya.app.data.auth.signOut(client)
    }
}
