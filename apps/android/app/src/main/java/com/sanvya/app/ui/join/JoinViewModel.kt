package com.sanvya.app.ui.join

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.InvitesRepository
import com.sanvya.app.ui.Prefs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Accepting a split-group invite.
 *
 * Ported from `apps/web/app/join/page.tsx`. The page is one effect and three
 * outcomes, and the shape here is the same three:
 *
 * * no token → say so, stop.
 * * no session → stash the token and ask them to sign in. The stash is what
 *   makes the invite survive the trip out to the auth provider and back.
 * * session → clear the stash FIRST, then accept, then navigate into the group.
 *
 * Clearing before accepting is web's own ordering and it matters: the token is
 * being consumed, so leaving it in the stash would send the user back to this
 * screen on the next launch to accept an invite that is already spent.
 *
 * Mirrors iOS's JoinView.
 */
class JoinViewModel : ViewModel(), KoinComponent {
    private val invitesRepository: InvitesRepository by inject()
    private val authRepository: AuthRepository by inject()

    /** The message under the title — web's single `msg` state. */
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    /** Show the "sign in / create account" button. */
    private val _needsAuth = MutableStateFlow(false)
    val needsAuth: StateFlow<Boolean> = _needsAuth.asStateFlow()

    /** The joined group's id, once accepted — the caller navigates. */
    private val _joinedGroupId = MutableStateFlow<String?>(null)
    val joinedGroupId: StateFlow<String?> = _joinedGroupId.asStateFlow()

    private var started = false

    /**
     * Labels are passed in for the usual reason: `sRes()` is `@Composable` and a
     * view model has no business holding the localisation surface.
     */
    fun start(token: String?, openingLabel: String, missingTokenLabel: String, needAuthLabel: String) {
        if (started) return
        started = true

        if (token.isNullOrEmpty()) {
            _message.value = missingTokenLabel
            return
        }
        if (authRepository.currentUserId.value == null) {
            Prefs.setPendingInvite(token)
            _needsAuth.value = true
            _message.value = needAuthLabel
            return
        }

        _message.value = openingLabel
        viewModelScope.launch {
            // Cleared UP FRONT: there is a session and the token is being
            // consumed, so it must not trigger another /join on the next launch.
            Prefs.setPendingInvite(null)
            try {
                _joinedGroupId.value = invitesRepository.acceptInvite(token)
            } catch (e: Exception) {
                _message.value = e.message ?: missingTokenLabel
            }
        }
    }
}
