package com.sanvya.app.ui.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.auth.AuthState
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.data.repository.nowIso
import com.sanvya.app.domain.entitlements.entitlementState
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.onboarding.shouldShowWalkthrough
import com.sanvya.app.ui.FormOptions
import com.sanvya.app.ui.components.initialSyncPending
import com.sanvya.app.ui.Prefs
import com.sanvya.app.ui.baseCurrencyNow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Whether the first-run walkthrough is showing, and the two flags that close it.
 *
 * A port of `apps/web/src/onboarding/useWalkthrough.ts`, including its split
 * storage: **done is permanent, skipped is for this launch only.** Web uses
 * `localStorage` for one and `sessionStorage` for the other, and the reason is
 * in the file: skipping is "not now", and someone who taps it while still
 * having no account should meet the walkthrough again next launch. `done` is
 * therefore in [Prefs] (SharedPreferences) and `skipped` is held here, which on
 * a ViewModel is the same lifetime web's sessionStorage has.
 *
 * The decision itself is NOT here. It is `shouldShowWalkthrough()` in Domain,
 * vector-pinned across all 96 combinations of its six inputs, because the
 * guards exist to stop the dialog appearing at the wrong moment and "did not
 * appear" is the failure nobody notices until a returning user is told to set
 * their accounts up from scratch.
 *
 * Split from [WalkthroughViewModel] on purpose — the gate outlives the dialog
 * and is cheap; that one holds a half-typed account name and dies with it.
 * Mirrors iOS's WalkthroughGate / WalkthroughViewModel pair exactly.
 */
class WalkthroughGateViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val skipped = MutableStateFlow(false)

    /**
     * Null until the count has actually been read once. A count we could not
     * take is not a count of zero, and guessing zero shows the walkthrough to
     * someone who has accounts.
     */
    private val realAccountCount = MutableStateFlow<Int?>(null)

    val isOpen: StateFlow<Boolean> = combine(
        Prefs.walkthroughDone,
        skipped,
        // The SHARED gate, not a private copy of the poll. This view model used
        // to run a fourth 400 ms loop over the same `hasSynced` field the three
        // InitialSyncGate callers were already polling; worse, it read the raw
        // flag while they read `online && !hasSynced`, so on a device with no
        // network the walkthrough and the dashboard's own skeleton disagreed
        // about whether the data had arrived. Web has always had ONE
        // `useInitialSyncPending()` and useWalkthrough.ts calls exactly that.
        initialSyncPending(),
        realAccountCount,
        authRepository.authState,
    ) { done, isSkipped, pending, count, authState ->
        shouldShowWalkthrough(
            done = done,
            skipped = isSkipped,
            syncPending = pending,
            accountCountLoaded = count != null,
            realAccountCount = count ?: 0,
            // A guest has a session, so SIGNED_IN_OFFLINE counts: web's gate is
            // `!!session`, not "signed in with an email".
            signedIn = authState != AuthState.SIGNED_OUT,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    init {
        viewModelScope.launch {
            ledgerRepository.watchRealAccountCount().collect { realAccountCount.value = it }
        }
    }

    /** Close for this launch only; it returns next time while there is still no account. */
    fun skip() { skipped.value = true }

    /** Close for good. */
    fun finish() = Prefs.setWalkthroughDone()

}

/**
 * The seven steps' own state: the two forms, and the two writes behind them.
 */
class WalkthroughViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()
    private val prefsRepository: PrefsRepository by inject()

    private val _step = MutableStateFlow(1)
    val step: StateFlow<Int> = _step

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    // Step 2 — account
    private val _accountName = MutableStateFlow("")
    val accountName: StateFlow<String> = _accountName

    private val _accountBalance = MutableStateFlow("")
    val accountBalance: StateFlow<String> = _accountBalance

    private var accountId: String? = null

    // Step 3 — first spend
    private val _spendWhat = MutableStateFlow("")
    val spendWhat: StateFlow<String> = _spendWhat

    private val _spendAmount = MutableStateFlow("")
    val spendAmount: StateFlow<String> = _spendAmount

    private val _isGuest = MutableStateFlow(false)
    val isGuest: StateFlow<Boolean> = _isGuest

    private val _onTrial = MutableStateFlow(false)
    val onTrial: StateFlow<Boolean> = _onTrial

    /**
     * Trimmed, because a name of three spaces is not a name. Web guards the same
     * way inside `saveAccount`; doing it here as well means the button is
     * visibly disabled rather than silently doing nothing when tapped.
     */
    val canSaveAccount: StateFlow<Boolean> = _accountName
        .map { it.trim().isNotEmpty() }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    val canSaveSpend: StateFlow<Boolean> = combine(_spendWhat, _spendAmount) { what, amount ->
        what.trim().isNotEmpty() && (amount.trim().toDoubleOrNull() ?: 0.0) > 0.0
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    init {
        viewModelScope.launch { _isGuest.value = authRepository.isGuest() }
        // Step 7 says one of two different things, and only one of them has a
        // countdown: `isTrial`, not `isPaid`. A paying subscriber is not on
        // trial and must not be told their trial is running.
        viewModelScope.launch {
            prefsRepository.watchEntitlement().collect { row ->
                _onTrial.value = entitlementState(
                    tier = row?.tier,
                    premiumTrialStartDate = row?.premiumTrialStartDate,
                    compTier = row?.compTier,
                    compUntil = row?.compUntil,
                    nowMillis = System.currentTimeMillis(),
                ).isTrial
            }
        }
    }

    fun setStep(value: Int) { _step.value = value }
    fun setAccountName(value: String) { _accountName.value = value }
    fun setAccountBalance(value: String) { _accountBalance.value = value }
    fun setSpendWhat(value: String) { _spendWhat.value = value }
    fun setSpendAmount(value: String) { _spendAmount.value = value }

    /**
     * Create the first account from two fields.
     *
     * Everything else takes a sane default, so a nervous first-timer never meets
     * the type / currency / overdraft form — all of it is editable later from
     * the account's own edit screen. Web makes exactly these choices: `savings`,
     * the base currency, `allow_negative = false`, and a colour derived from the
     * name.
     */
    fun saveAccount() {
        val name = _accountName.value.trim()
        if (name.isEmpty() || _busy.value) return
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                val userId = authRepository.currentUserId.value ?: authRepository.ensureGuest()
                val base = baseCurrencyNow()
                val id = ledgerRepository.createAccount(
                    userId = userId,
                    name = name,
                    type = "savings",
                    currency = base,
                    icon = null,
                    color = FormOptions.colorForId(name),
                    allowNegative = false,
                )
                accountId = id
                // Only a positive opening balance is written. Web checks
                // `Number.isFinite(major) && major > 0` for the same reason: "0"
                // and "" are the same statement — "I have not told you" — and an
                // explicit zero opening balance is a real ledger row that would
                // have to be found and deleted later.
                val major = _accountBalance.value.trim().toDoubleOrNull()
                if (major != null && major.isFinite() && major > 0) {
                    ledgerRepository.setOpeningBalance(
                        userId = userId,
                        accountId = id,
                        balance = fromMajor(major, base),
                        occurredAt = nowIso(),
                    )
                }
                _step.value = 3
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _busy.value = false
            }
        }
    }

    /**
     * Record the first spend against the account we just made.
     *
     * Web computes the minor amount as `Math.round(Number(amount) * 100)` — the
     * hardcoded ×100 the rest of this port has been removing, and wrong for
     * every currency that is not two-decimal: a first spend of ¥500 lands as ¥5.
     * `fromMajor` uses the currency's own minor-unit count. Recorded in
     * docs/mobile/PARITY_AUDIT.md under "Web bugs found while porting".
     */
    fun saveSpend() {
        val desc = _spendWhat.value.trim()
        val major = _spendAmount.value.trim().toDoubleOrNull() ?: 0.0
        if (desc.isEmpty() || major <= 0 || _busy.value) return
        _busy.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                val userId = authRepository.currentUserId.value ?: authRepository.ensureGuest()
                // The account may not exist: step 2 offers "I'll do this later".
                // Web falls back to the first account it can find and, failing
                // that, moves on without recording anything rather than showing
                // an error for a step it told them was optional.
                val target = accountId ?: ledgerRepository.firstRealAccountId()
                if (target == null) {
                    _step.value = 4
                    return@launch
                }
                ledgerRepository.createTransaction(
                    userId = userId,
                    accountId = target,
                    type = "expense",
                    amount = fromMajor(major, baseCurrencyNow()),
                    occurredAt = nowIso(),
                    labels = emptyList(),
                    description = desc,
                )
                _step.value = 4
            } catch (e: Exception) {
                _error.value = e.message
            } finally {
                _busy.value = false
            }
        }
    }
}
