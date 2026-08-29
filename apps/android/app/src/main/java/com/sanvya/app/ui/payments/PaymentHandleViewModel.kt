package com.sanvya.app.ui.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.HandleDisclosure
import com.sanvya.app.data.repository.SettingsRepository
import com.sanvya.app.data.repository.UpiRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * "Your UPI ID" -- the Settings card's state.
 *
 * Ports `apps/web/src/payments/PaymentHandlePanel.tsx`. Every call belongs to
 * [UpiRepository]; what is here is web's four pieces of component state (the
 * saved hint, the busy flag, the error and the expanded log) plus the one
 * effect that loads the hint.
 *
 * Self-contained rather than fed from `SettingsViewModel`, matching
 * `SecurityViewModel`: web's panel calls `useSession()` itself, and reading the
 * session here keeps the card droppable into any screen the way web's is.
 *
 * The error string is the SERVER's, verbatim, and deliberately not an i18n key.
 * Every message this can surface comes from the `payment-handle` Edge Function
 * ("Create an account before saving a UPI ID.", "Couldn't save that: ..."), and
 * web renders `e.message` for exactly the same reason. Translating them would
 * mean maintaining a native copy of the function's error vocabulary that goes
 * stale silently. The strings the PANEL owns are all catalogued.
 *
 * Mirrors iOS's PaymentHandleViewModel.
 */
class PaymentHandleViewModel : ViewModel(), KoinComponent {

    private val upiRepository: UpiRepository by inject()
    private val settingsRepository: SettingsRepository by inject()

    /**
     * True until BOTH the session and the saved hint are known.
     *
     * Web's panel starts `loading = true` and its `useSession()` hydrates from a
     * localStorage cache, so it effectively never renders the guest message at
     * someone who is signed in. Native has no such cache, so the session read is
     * folded into the same loading flag -- otherwise every open of Settings
     * would flash "Create an account to add a UPI ID" at an account holder,
     * which is the same lie as flashing the empty form at someone who already
     * saved a handle (web's own comment on that effect).
     */
    private val _loading = MutableStateFlow(true)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()

    /** Web's `useCanSavePaymentHandle()` -- signed in, and not a guest. */
    private val _canSave = MutableStateFlow(false)
    val canSave: StateFlow<Boolean> = _canSave.asStateFlow()

    /** The masked hint for the saved handle, or null when there isn't one. */
    private val _hint = MutableStateFlow<String?>(null)
    val hint: StateFlow<String?> = _hint.asStateFlow()

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    /**
     * Who has fetched your UPI ID. Synced, so it reads from local SQLite and
     * works offline -- see [UpiRepository.watchDisclosures].
     */
    val disclosures: StateFlow<List<HandleDisclosure>> = upiRepository.watchDisclosures()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /**
     * The display name sent with a save, so the payer's UPI app has something
     * to show. Web passes `session?.username`.
     */
    private var username: String = ""

    private var started = false

    /**
     * Web's `useEffect(..., [canSave])`. Guarded so returning to Settings does
     * not refetch: the hint is a masked string that only changes when this
     * panel itself changes it.
     */
    fun start() {
        if (started) return
        started = true
        viewModelScope.launch {
            val session = try {
                settingsRepository.currentSession()
            } catch (_: Exception) {
                null
            }
            username = session?.username.orEmpty()
            // Bound through a safe call rather than smart-cast: `isGuest` is a
            // public property on a `:data` class, and Kotlin refuses to
            // smart-cast one declared in another module (PARITY_AUDIT trap 3,
            // the same one that bit Loans and Insights). Web's
            // `useCanSavePaymentHandle()` is `!!session && !session.isGuest`,
            // and no session means no save either way.
            val isGuest = session?.isGuest ?: true
            val allowed = session != null && !isGuest
            _canSave.value = allowed
            if (!allowed) {
                _loading.value = false
                return@launch
            }
            _hint.value = try {
                upiRepository.getMyPaymentHandle()
            } catch (_: Exception) {
                // The repository already degrades to the cached hint on a failed
                // read; anything that still throws is not worth an error banner
                // over a field the user has not touched yet.
                upiRepository.getCachedHint()
            }
            _loading.value = false
        }
    }

    /**
     * Web's `save()`. [normalizedVpa] is already trimmed and lower-cased.
     *
     * [onSaved] clears the input, which web does with `setValue("")` inside the
     * same `try`. The field lives in the composable, so the signal travels back
     * rather than the state moving up: the panel is otherwise stateless and a
     * `TextFieldValue` in a view model would fight `rememberSaveable` on
     * rotation.
     */
    fun save(normalizedVpa: String, onSaved: () -> Unit) {
        if (_busy.value) return
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                _hint.value = upiRepository.savePaymentHandle(normalizedVpa, username)
                onSaved()
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _busy.value = false
            }
        }
    }

    /** Web's `forget()`. */
    fun forget() {
        if (_busy.value) return
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                upiRepository.forgetPaymentHandle()
                _hint.value = null
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _busy.value = false
            }
        }
    }
}
