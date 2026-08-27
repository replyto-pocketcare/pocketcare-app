package com.sanvya.app.ui.receipts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.ItemizedSplitInput
import com.sanvya.app.data.repository.PayerInput
import com.sanvya.app.data.repository.ReceiptsRepository
import com.sanvya.app.data.repository.SplitGroup
import com.sanvya.app.data.repository.SplitsRepository
import com.sanvya.app.data.repository.nowIso
import com.sanvya.app.domain.receipts.AllocationResult
import com.sanvya.app.domain.receipts.LineAssignment
import com.sanvya.app.domain.receipts.LineProblem
import com.sanvya.app.domain.receipts.ReceiptDraft
import com.sanvya.app.domain.receipts.ReceiptLine
import com.sanvya.app.domain.receipts.ShareInput
import com.sanvya.app.domain.receipts.allocateReceipt
import com.sanvya.app.domain.receipts.isCharge
import com.sanvya.app.domain.receipts.lineWeight
import com.sanvya.app.domain.receipts.receiptDigits
import com.sanvya.app.domain.receipts.validateSplitLine
import com.sanvya.app.ui.baseCurrencyNow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * One line's assignment as the screen holds it: who is on it, how it divides,
 * and the raw text each person typed.
 *
 * The text is kept RAW, not parsed, for the same reason web does: a
 * half-entered "12." must survive a recomposition, and parsing on every
 * keystroke would delete the character the user is in the middle of typing.
 */
data class SplitLineState(
    val mode: String,
    val members: List<String>,
    /** userId -> raw input string. Its meaning depends on [mode]. */
    val weights: Map<String, String> = emptyMap(),
)

/**
 * Per-item split assignment — "who had what".
 *
 * Ported from `apps/web/app/receipts/split/page.tsx`. All of the arithmetic
 * lives in Domain's `SplitAssign.kt` and `allocateReceipt`; this holds the
 * screen's state and nothing else. Mirrors iOS's SplitReceiptViewModel.swift.
 */
class SplitReceiptViewModel : ViewModel(), KoinComponent {
    private val receiptsRepository: ReceiptsRepository by inject()
    private val splitsRepository: SplitsRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _draft = MutableStateFlow<ReceiptDraft?>(null)
    val draft: StateFlow<ReceiptDraft?> = _draft

    private val _group = MutableStateFlow<SplitGroup?>(null)
    val group: StateFlow<SplitGroup?> = _group

    private val _memberIds = MutableStateFlow<List<String>>(emptyList())
    val memberIds: StateFlow<List<String>> = _memberIds

    private val _state = MutableStateFlow<Map<String, SplitLineState>>(emptyMap())
    val state: StateFlow<Map<String, SplitLineState>> = _state

    private val _loaded = MutableStateFlow(false)
    val loaded: StateFlow<Boolean> = _loaded

    private val _saving = MutableStateFlow(false)
    val saving: StateFlow<Boolean> = _saving

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    /** Set once the split is written, so the screen can leave. */
    private val _savedExpenseId = MutableStateFlow<String?>(null)
    val savedExpenseId: StateFlow<String?> = _savedExpenseId

    /** True when the scan's JSON would not parse — a different message from "no scan". */
    private val _corrupt = MutableStateFlow(false)
    val corrupt: StateFlow<Boolean> = _corrupt

    private var profileNames: Map<String, String> = emptyMap()
    private var me: String = ""
    private var scanId = ""
    private var groupId = ""
    private var accountId = ""
    private var categoryId = ""

    fun load(scanId: String, groupId: String, accountId: String, categoryId: String) {
        if (_loaded.value) return
        this.scanId = scanId
        this.groupId = groupId
        this.accountId = accountId
        this.categoryId = categoryId
        viewModelScope.launch {
            me = authRepository.currentUserId.value ?: authRepository.ensureGuest()

            val parsed = receiptsRepository.get(scanId)?.parsedJson
            if (parsed != null) {
                // A scan whose JSON will not parse is not an empty scan: the
                // screen says so rather than showing an empty bill you could
                // "save".
                val decoded = runCatching { receiptDraftFromJsonString(parsed) }.getOrNull()
                _draft.value = decoded
                _corrupt.value = decoded == null
            }

            _group.value = splitsRepository.getGroup(groupId)
            // A snapshot, not a subscription: the members of a group do not
            // change while you are assigning its bill.
            _memberIds.value = splitsRepository.watchGroupMemberIds(groupId).first()
            profileNames = splitsRepository.watchConnections(me).first().associate { it.id to it.name }

            seed()
            _loaded.value = true
        }
    }

    /**
     * Seed every line with "everyone, split the obvious way" so the screen is
     * usable immediately and the user only edits the exceptions.
     */
    private fun seed() {
        val d = _draft.value ?: return
        val members = _memberIds.value
        if (members.isEmpty() || _state.value.isNotEmpty()) return
        _state.value = d.lines.associate { line ->
            line.id to SplitLineState(
                mode = if (isCharge(line.kind)) "proportional" else "equal",
                members = members,
            )
        }
    }

    // ---- derived ----

    val digits: Int get() = receiptDigits(_draft.value?.currency ?: baseCurrencyNow())
    val currency: String get() = _draft.value?.currency ?: baseCurrencyNow()

    fun nameOf(id: String, youLabel: String, someoneLabel: String): String =
        if (id == me) youLabel else profileNames[id] ?: someoneLabel

    /** Build Domain's assignment structures from the UI state. */
    fun assignments(): List<LineAssignment> {
        val d = _draft.value ?: return emptyList()
        val st = _state.value
        return d.lines.map { line ->
            val s = st[line.id] ?: return@map LineAssignment(line.id, "equal", emptyList())
            LineAssignment(
                lineId = line.id,
                mode = s.mode,
                shares = s.members.map { uid ->
                    ShareInput(uid, lineWeight(s.mode, s.weights[uid], line.amount, digits))
                },
            )
        }
    }

    /** Live allocation. A failure here is a validation message, not a crash. */
    fun allocation(): Result<AllocationResult>? {
        val d = _draft.value ?: return null
        if (d.lines.isEmpty()) return null
        return runCatching { allocateReceipt(d.lines, assignments()) }
    }

    fun problemFor(line: ReceiptLine): LineProblem? {
        val s = _state.value[line.id] ?: return LineProblem.NeedsSomeone
        return validateSplitLine(line, s.mode, s.members, s.weights, digits)
    }

    fun hasLineProblem(): Boolean {
        val d = _draft.value ?: return true
        return d.lines.any { problemFor(it) != null }
    }

    fun canSave(): Boolean =
        _draft.value != null && !_saving.value && accountId.isNotEmpty() &&
            !hasLineProblem() && allocation()?.isSuccess == true

    // ---- edits ----

    fun setMode(lineId: String, mode: String) = mutate(lineId) {
        // Weights are mode-specific: "50" means 50% in one mode and ₹0.50 in
        // another, so carrying them across would silently change the split.
        it.copy(mode = mode, weights = emptyMap())
    }

    fun setWeight(lineId: String, userId: String, raw: String) = mutate(lineId) {
        it.copy(weights = it.weights + (userId to raw))
    }

    fun toggleMember(lineId: String, userId: String) = mutate(lineId) { s ->
        val has = s.members.contains(userId)
        // A line must belong to somebody — refuse to empty the last one.
        if (has && s.members.size == 1) {
            s
        } else {
            s.copy(members = if (has) s.members - userId else s.members + userId)
        }
    }

    fun applyToAll(members: List<String>) {
        _state.value = _state.value.mapValues { (_, s) -> s.copy(members = members, weights = emptyMap()) }
    }

    fun everyone(): List<String> = _memberIds.value
    fun onlyMe(): List<String> = listOf(me)

    private inline fun mutate(lineId: String, fn: (SplitLineState) -> SplitLineState) {
        val s = _state.value[lineId] ?: return
        _state.value = _state.value + (lineId to fn(s))
    }

    // ---- save ----

    fun save() {
        val d = _draft.value ?: return
        val alloc = allocation()?.getOrNull() ?: return
        if (_saving.value) return
        _saving.value = true
        _error.value = null
        viewModelScope.launch {
            try {
                val expenseId = splitsRepository.createSplitExpenseItemized(
                    userId = me,
                    input = ItemizedSplitInput(
                        groupId = groupId,
                        draft = d,
                        assignments = assignments(),
                        // The scanner flow assumes you paid the whole bill;
                        // multi-payer stays in the richer add-transaction
                        // editor. Web says the same.
                        payers = listOf(PayerInput(me, alloc.total, accountId)),
                        categoryId = categoryId.ifEmpty { null },
                        occurredAt = d.occurredAt ?: nowIso().take(10),
                    ),
                )
                runCatching { receiptsRepository.linkScan(scanId, expenseId = expenseId) }
                _savedExpenseId.value = expenseId
            } catch (e: Exception) {
                _error.value = e.message
                _saving.value = false
            }
        }
    }
}
