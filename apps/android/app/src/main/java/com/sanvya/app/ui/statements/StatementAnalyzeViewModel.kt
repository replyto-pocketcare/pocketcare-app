package com.sanvya.app.ui.statements

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.Account
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.RecurringRepository
import com.sanvya.app.data.repository.nowIso
import com.sanvya.app.domain.categorize.BulkClassifier
import com.sanvya.app.domain.categorize.CategoryData
import com.sanvya.app.domain.csv.CanonRow
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.money.toMajor
import com.sanvya.app.domain.statements.ParsedStatement
import com.sanvya.app.domain.statements.RECONCILE_DAY_WINDOW
import com.sanvya.app.domain.statements.Reconciliation
import com.sanvya.app.domain.statements.RecurringCandidate
import com.sanvya.app.domain.statements.StatementTxn
import com.sanvya.app.domain.statements.addDaysIso
import com.sanvya.app.domain.statements.parseStatementCsv
import com.sanvya.app.domain.statements.reconcileStatement
import com.sanvya.app.ui.baseCurrencyNow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import kotlin.math.abs

/**
 * The statement analyzer — parse a bank or card export on the device, analyse
 * it, reconcile it against what is already recorded, and import what is missing.
 *
 * Ported from `apps/web/app/statements/analyze/page.tsx`. Every number on the
 * screen comes from Domain's `StatementCsv`/`StatementAnalysis`/
 * `StatementReconcile`, all vector-pinned; this holds the screen's state and
 * the four repository calls.
 *
 * **Nothing leaves the device**, which is the claim web's header makes and the
 * reason the parse, the categorisation and the reconciliation all happen here
 * rather than behind an endpoint.
 *
 * Mirrors iOS's StatementAnalyzeViewModel.swift.
 */
class StatementAnalyzeViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val recurringRepository: RecurringRepository by inject()
    private val authRepository: AuthRepository by inject()

    // ---- picker state ----

    /** "bank" | "card". */
    private val _kind = MutableStateFlow("bank")
    val kind: StateFlow<String> = _kind.asStateFlow()

    private val _accountId = MutableStateFlow("")
    val accountId: StateFlow<String> = _accountId.asStateFlow()

    private val _accounts = MutableStateFlow<List<Account>>(emptyList())
    val accounts: StateFlow<List<Account>> = _accounts.asStateFlow()

    /** A short label while a file is being read, or null. */
    private val _busy = MutableStateFlow<String?>(null)
    val busy: StateFlow<String?> = _busy.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    // ---- results ----

    private val _parsed = MutableStateFlow<ParsedStatement?>(null)
    val parsed: StateFlow<ParsedStatement?> = _parsed.asStateFlow()

    private val _reconciliation = MutableStateFlow<Reconciliation?>(null)
    val reconciliation: StateFlow<Reconciliation?> = _reconciliation.asStateFlow()

    private val _imported = MutableStateFlow(false)
    val imported: StateFlow<Boolean> = _imported.asStateFlow()

    private val _addedRecurring = MutableStateFlow<Set<String>>(emptySet())
    val addedRecurring: StateFlow<Set<String>> = _addedRecurring.asStateFlow()

    private val _showAllTransactions = MutableStateFlow(false)
    val showAllTransactions: StateFlow<Boolean> = _showAllTransactions.asStateFlow()

    private var started = false

    fun start() {
        if (started) return
        started = true
        // The analyzer works without an account; only reconcile needs one.
        ledgerRepository.watchAccounts().onEach { _accounts.value = it }.launchIn(viewModelScope)
    }

    val accountName: String get() = _accounts.value.find { it.id == _accountId.value }?.name.orEmpty()

    val currency: String get() = _parsed.value?.currency ?: baseCurrencyNow()

    fun setKind(value: String) { _kind.value = value }

    fun setError(message: String) { _error.value = message }

    fun toggleShowAll() { _showAllTransactions.value = !_showAllTransactions.value }

    /** Start over with a new file. */
    fun reset() {
        _parsed.value = null
        _reconciliation.value = null
        _imported.value = false
        _addedRecurring.value = emptySet()
        _showAllTransactions.value = false
        _error.value = null
    }

    // ---- parse ----

    /**
     * Parse a picked CSV, categorise its spends, and reconcile.
     *
     * The labels are passed in rather than read from `S` here for the usual
     * reason: `sRes()` is `@Composable` and a view model has no business holding
     * the localisation surface.
     */
    fun parse(text: String, parsingLabel: String, categorisingLabel: String, readFailMessage: String) {
        _error.value = null
        _parsed.value = null
        _reconciliation.value = null
        _imported.value = false
        _busy.value = parsingLabel

        viewModelScope.launch {
            try {
                val base = baseCurrencyNow()
                var statement = parseStatementCsv(text, currency = base, kind = _kind.value)
                _busy.value = categorisingLabel
                statement = categorise(statement)
                _parsed.value = statement
                reconcileNow(statement)
                if (statement.txns.isEmpty() && statement.warnings.isEmpty()) {
                    _error.value = readFailMessage
                }
            } catch (e: Exception) {
                _error.value = e.message ?: readFailMessage
            } finally {
                _busy.value = null
            }
        }
    }

    /**
     * On-device categorisation of the spends.
     *
     * The classifier is built ONCE and then run over every row in memory, which
     * is the whole reason [BulkClassifier] exists — a per-row query would turn a
     * 400-line statement into 400 round-trips against a database the UI is also
     * reading. Web says the same in its own comment.
     *
     * Failure is swallowed: a statement that could not be categorised is still a
     * statement worth showing, and web treats the categoriser as optional here
     * for exactly that reason.
     */
    private suspend fun categorise(statement: ParsedStatement): ParsedStatement {
        if (statement.txns.isEmpty()) return statement
        val userId = authRepository.currentUserId.value ?: return statement
        val categoryRows = runCatching { ledgerRepository.listCategories() }.getOrNull() ?: return statement
        val rules = runCatching { ledgerRepository.listCategoryRules(userId) }.getOrNull() ?: return statement

        val categories = categoryRows.map { CategoryData(it.id, it.name) }
        val nameById = categories.associate { it.id to it.name }
        val classifier = BulkClassifier(rules, categories)

        val txns = statement.txns.map { txn ->
            // Only spends. A salary credit is not a "Food & Dining" row just
            // because the payer's name happens to contain a seed keyword.
            if (txn.amount >= 0) return@map txn
            val id = classifier.classify(txn.description) ?: return@map txn
            val name = nameById[id] ?: return@map txn
            txn.copy(category = name)
        }
        return statement.copy(txns = txns)
    }

    // ---- reconcile ----

    fun setAccountId(value: String) {
        _accountId.value = value
        val statement = _parsed.value ?: return
        viewModelScope.launch { reconcileNow(statement) }
    }

    private suspend fun reconcileNow(statement: ParsedStatement) {
        val accId = _accountId.value
        val from = statement.period.from
        val to = statement.period.to
        if (accId.isEmpty() || from == null || to == null) {
            _reconciliation.value = null
            return
        }
        // The window is padded on the `to` end by the reconciler's own day
        // window, matching web's `addDays(to, 4)`: a row dated the last day of
        // the statement can legitimately match one recorded four days later.
        val paddedTo = addDaysIso(to, RECONCILE_DAY_WINDOW) ?: to
        val recorded = runCatching {
            ledgerRepository.listRecordedForReconcile(accId, from, paddedTo)
        }.getOrNull() ?: return
        _reconciliation.value = reconcileStatement(statement.txns, recorded)
    }

    // ---- actions ----

    /** Import everything in the statement that is not already recorded. */
    fun importMissing() {
        val rec = _reconciliation.value ?: return
        val name = accountName
        if (name.isEmpty() || rec.missingOnPlatform.isEmpty()) return
        val cur = currency
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: authRepository.ensureGuest()
            val rows = rec.missingOnPlatform.map { t: StatementTxn ->
                CanonRow(
                    // Midday, not midnight: an occurred_at of 00:00 lands on the
                    // previous day for every user west of UTC once SQLite reads
                    // it back. Web picks the same hour for the same reason.
                    date = "${t.date}T12:00:00",
                    type = if (t.amount < 0) "expense" else "income",
                    amount = abs(toMajor(money(t.amount, cur))),
                    currency = cur,
                    account = name,
                    category = t.category,
                    description = t.description,
                )
            }
            // skipDuplicates = false -- the reconciler has ALREADY established
            // that none of these is recorded, and a second, weaker dedupe here
            // would silently drop two genuinely identical coffees on the same
            // day. Web passes the same flag.
            runCatching {
                ledgerRepository.importTransactions(
                    userId = userId, rows = rows, baseCurrency = baseCurrencyNow(),
                    nowIso = nowIso(), skipDuplicates = false,
                )
            }
            _imported.value = true
        }
    }

    /** Turn a detected pattern into a real recurring commitment. */
    fun addRecurring(candidate: RecurringCandidate) {
        if (_addedRecurring.value.contains(candidate.key)) return
        val cur = currency
        val accId = _accountId.value.ifEmpty { null }
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: authRepository.ensureGuest()
            val frequency = when (candidate.cadence) {
                "weekly" -> "weekly"
                "yearly" -> "yearly"
                else -> "monthly"
            }
            runCatching {
                recurringRepository.create(
                    userId,
                    RecurringRepository.Input(
                        direction = "payment",
                        // 40 characters, web's cap. A bank narration is often
                        // the whole POS dump and would make the recurring list
                        // unreadable.
                        name = candidate.label.take(40),
                        amountMinor = candidate.amount,
                        currency = cur,
                        accountId = accId,
                        frequency = frequency,
                        firstDue = nowIso().take(10),
                        autoPost = false,
                    ),
                )
            }
            _addedRecurring.value = _addedRecurring.value + candidate.key
        }
    }
}
