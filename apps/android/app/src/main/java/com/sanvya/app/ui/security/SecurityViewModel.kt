package com.sanvya.app.ui.security

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.SecurityActionException
import com.sanvya.app.data.repository.SecurityRepository
import com.sanvya.app.data.repository.SupportGrant
import com.sanvya.app.domain.security.SecurityStatus
import com.sanvya.app.domain.security.passphraseSetupErrorKey
import com.sanvya.app.domain.security.securityStatus
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/** A grant that was just issued, so the panel can say until when. */
data class GrantIssuedNotice(val scope: String, val expiresAtIso: String)

/**
 * The Security & encryption panel's state.
 *
 * Ports `apps/web/src/crypto/SecurityPanel.tsx` — the component, not the
 * crypto: every key operation belongs to [SecurityRepository], and everything
 * here is the four-state machine web renders (`loading` / `unset` / `locked` /
 * `unlocked`) plus the two forms that drive it.
 *
 * Every message this exposes is an i18n KEY, never a sentence. Web can throw
 * `new Error("Wrong passphrase.")` and render `e.message` because its copy is
 * English in the source; a translated app cannot, so the key travels and the
 * composable resolves it against the `security` catalogue.
 */
class SecurityViewModel : ViewModel(), KoinComponent {

    private val securityRepository: SecurityRepository by inject()

    /** Web's `useCryptoStatus()`. */
    val status: StateFlow<String> =
        combine(securityRepository.hasKeys, securityRepository.unlocked) { hasKeys, unlocked ->
            securityStatus(hasKeys, unlocked)
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), SecurityStatus.LOADING)

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    /** i18n key in the `security` namespace, or null. */
    private val _errorKey = MutableStateFlow<String?>(null)
    val errorKey: StateFlow<String?> = _errorKey.asStateFlow()

    /**
     * The one-time recovery code, held only until the user acknowledges it.
     *
     * Non-null is its own screen on web — the setup form is replaced by the
     * code and the "there is no other way back in" warning, and there is no
     * way past it except the acknowledge button.
     */
    private val _recoveryCode = MutableStateFlow<String?>(null)
    val recoveryCode: StateFlow<String?> = _recoveryCode.asStateFlow()

    private val _grants = MutableStateFlow<List<SupportGrant>>(emptyList())
    val grants: StateFlow<List<SupportGrant>> = _grants.asStateFlow()

    private val _grantIssued = MutableStateFlow<GrantIssuedNotice?>(null)
    val grantIssued: StateFlow<GrantIssuedNotice?> = _grantIssued.asStateFlow()

    private val _grantErrorKey = MutableStateFlow<String?>(null)
    val grantErrorKey: StateFlow<String?> = _grantErrorKey.asStateFlow()

    private var grantPoll: Job? = null

    /**
     * Web's `useEffect(() => { void refreshKeyState(); }, [])`, plus the grant
     * poll its `SupportAccess` runs on a 30-second interval so a grant that
     * has expired stops being offered for revocation.
     *
     * `refreshKeyState()` is INSIDE the loop and INSIDE a runCatching, and both
     * halves of that matter. Unguarded, a throw from the local `user_keys`
     * read on a cold start is an unhandled coroutine exception -- a crash --
     * and even if it were survivable, the poll below would never start and
     * `status` would sit at `loading` for the life of the screen. Inside the
     * loop, a first attempt that failed because the device was offline is
     * retried every thirty seconds instead of leaving the panel stuck on
     * "Checking…" until the user navigates away and back. The repository does
     * the network probe only while the answer is still unknown, so the retry
     * costs one local query once it has settled.
     */
    fun start() {
        if (grantPoll?.isActive == true) return
        grantPoll = viewModelScope.launch {
            while (true) {
                runCatching { securityRepository.refreshKeyState() }
                _grants.value = runCatching { securityRepository.activeGrants() }.getOrDefault(emptyList())
                delay(GRANT_POLL_MILLIS)
            }
        }
    }

    // ---- setup ----------------------------------------------------------

    fun setup(passphrase: String, confirm: String) {
        _errorKey.value = passphraseSetupErrorKey(passphrase, confirm)
        if (_errorKey.value != null) return
        _busy.value = true
        viewModelScope.launch {
            try {
                _recoveryCode.value = securityRepository.setupEncryption(passphrase)
            } catch (e: SecurityActionException) {
                _errorKey.value = e.messageKey
            } catch (_: Exception) {
                _errorKey.value = SecurityRepository.KEY_SETUP_FAILED
            } finally {
                _busy.value = false
            }
        }
    }

    /** Web's "I understand — I've saved it": drops the code from memory. */
    fun acknowledgeRecoveryCode() {
        _recoveryCode.value = null
    }

    // ---- unlock / lock --------------------------------------------------

    fun unlock(secret: String, useRecovery: Boolean) {
        _errorKey.value = null
        _busy.value = true
        viewModelScope.launch {
            try {
                if (useRecovery) {
                    securityRepository.unlockWithRecovery(secret)
                } else {
                    securityRepository.unlock(secret)
                }
            } catch (e: SecurityActionException) {
                _errorKey.value = e.messageKey
            } catch (_: Exception) {
                // Web collapses every unlock failure into one message per mode,
                // and so does this: the useful distinction is "the thing you
                // typed is wrong", not which layer noticed.
                _errorKey.value = if (useRecovery) {
                    SecurityRepository.KEY_INVALID_RECOVERY
                } else {
                    SecurityRepository.KEY_WRONG_PASSPHRASE
                }
            } finally {
                _busy.value = false
            }
        }
    }

    fun lock() {
        securityRepository.lock()
        _grants.value = emptyList()
        _grantIssued.value = null
        _grantErrorKey.value = null
    }

    /** Clearing the field also clears the error, as retyping does on web. */
    fun clearError() {
        _errorKey.value = null
    }

    // ---- support grants --------------------------------------------------

    fun issueGrant(scope: String) {
        _busy.value = true
        _grantIssued.value = null
        _grantErrorKey.value = null
        viewModelScope.launch {
            try {
                val issued = securityRepository.issueSupportGrant(scope)
                _grantIssued.value = GrantIssuedNotice(scope = scope, expiresAtIso = issued.expiresAtIso)
                _grants.value = securityRepository.activeGrants()
            } catch (e: SecurityActionException) {
                _grantErrorKey.value = e.messageKey
            } catch (_: Exception) {
                _grantErrorKey.value = SecurityRepository.KEY_GRANT_FAILED
            } finally {
                _busy.value = false
            }
        }
    }

    fun revokeGrant(grantId: String) {
        viewModelScope.launch {
            runCatching { securityRepository.revokeGrant(grantId) }
            _grants.value = runCatching { securityRepository.activeGrants() }.getOrDefault(emptyList())
        }
    }

    private companion object {
        /** Web's `setInterval(refresh, 30_000)`. */
        const val GRANT_POLL_MILLIS = 30_000L
    }
}
