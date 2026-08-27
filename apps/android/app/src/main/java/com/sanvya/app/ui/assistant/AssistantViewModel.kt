package com.sanvya.app.ui.assistant

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.AssistantRepository
import com.sanvya.app.data.repository.AssistantThread
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.domain.assistant.ASSISTANT_PERSONA
import com.sanvya.app.domain.assistant.ASSISTANT_TOOL_DECLINED
import com.sanvya.app.domain.assistant.ASSISTANT_TOOL_REJECTED
import com.sanvya.app.domain.assistant.ApiMessage
import com.sanvya.app.domain.assistant.AssistantContent
import com.sanvya.app.domain.assistant.EntitlementQuota
import com.sanvya.app.domain.assistant.ToolUse
import com.sanvya.app.domain.assistant.assistantActionNote
import com.sanvya.app.domain.assistant.assistantErrorKey
import com.sanvya.app.domain.assistant.assistantThreadTitle
import com.sanvya.app.domain.assistant.describeToolCall
import com.sanvya.app.domain.assistant.planAssistantTurn
import com.sanvya.app.domain.assistant.summaryForPrompt
import com.sanvya.app.domain.entitlements.entitlementState
import com.sanvya.app.ui.baseCurrencyNow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.LocalDate

/** One bubble in the transcript. `role` is "user" | "assistant" | "action". */
data class ChatBubble(val id: String, val role: String, val text: String)

/**
 * The assistant chat.
 *
 * Ported from `apps/web/src/assistant/AssistantChat.tsx`. The DECISIONS live in
 * Domain and are vector-pinned — which tools run silently, which are refused,
 * how the history window is trimmed, what the confirm card says. This holds the
 * screen's state and drives the loop.
 *
 * **The turn loop recurses.** A model turn can end in tool calls; running them
 * produces `tool_result` blocks which are sent back as a new user turn, and the
 * model answers again. Web recurses through `runTurn`; so does this. The chain
 * only stops when a turn comes back with no tool calls, or when one is waiting
 * on the user.
 *
 * Mirrors iOS's AssistantViewModel.swift.
 */
class AssistantViewModel : ViewModel(), KoinComponent {
    private val assistantRepository: AssistantRepository by inject()
    private val authRepository: AuthRepository by inject()
    private val prefsRepository: PrefsRepository by inject()

    // ---- screen state ----

    /** "landing" | "chat" — web's own two views. */
    private val _view = MutableStateFlow("landing")
    val view: StateFlow<String> = _view.asStateFlow()

    private val _bubbles = MutableStateFlow<List<ChatBubble>>(emptyList())
    val bubbles: StateFlow<List<ChatBubble>> = _bubbles.asStateFlow()

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    /** The confirmation card currently on screen, or null. */
    private val _pendingTool = MutableStateFlow<ToolUse?>(null)
    val pendingTool: StateFlow<ToolUse?> = _pendingTool.asStateFlow()

    private val _quota = MutableStateFlow<EntitlementQuota?>(null)
    val quota: StateFlow<EntitlementQuota?> = _quota.asStateFlow()

    private val _isPaid = MutableStateFlow(false)
    val isPaid: StateFlow<Boolean> = _isPaid.asStateFlow()

    /** True once the entitlement has been read at all, so the gate does not flash. */
    private val _entitlementKnown = MutableStateFlow(false)
    val entitlementKnown: StateFlow<Boolean> = _entitlementKnown.asStateFlow()

    /** The exact context string sent to the model, for the "view data" sheet. */
    private val _payload = MutableStateFlow<String?>(null)
    val payload: StateFlow<String?> = _payload.asStateFlow()

    val threads: StateFlow<List<AssistantThread>> = authRepository.currentUserId
        .flatMapLatest { uid ->
            if (uid == null) flowOf(emptyList()) else assistantRepository.watchThreads(uid)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    // ---- the model conversation, which is NOT the transcript ----

    /**
     * What the model sees. Deliberately separate from [bubbles].
     *
     * The transcript is prose; this carries `tool_use` and `tool_result` blocks
     * that are never persisted and never shown. Rebuilding one from the other is
     * lossy in both directions, which is why web keeps two and so does this.
     */
    private var conversation: List<ApiMessage> = emptyList()
    private var systemBlocks: List<String> = listOf(ASSISTANT_PERSONA)
    private var threadId: String? = null
    private var pendingRest: List<ToolUse> = emptyList()
    private var pendingResults: List<AssistantContent> = emptyList()
    private var pendingMessages: List<ApiMessage> = emptyList()
    private var bubbleCounter = 0

    private var started = false

    fun start() {
        if (started) return
        started = true
        prefsRepository.watchEntitlement().onEach { row ->
            val state = entitlementState(
                tier = row?.tier,
                premiumTrialStartDate = row?.premiumTrialStartDate,
                compTier = row?.compTier,
                compUntil = row?.compUntil,
                nowMillis = System.currentTimeMillis(),
                monthlyQuotaTotal = row?.monthlyQuotaTotal,
                monthlyQuotaUsed = row?.monthlyQuotaUsed,
                purchasedQuotaRemaining = row?.purchasedQuotaRemaining,
                additionalPurchasedQuota = row?.additionalPurchasedQuota,
            )
            _isPaid.value = state.isPaid
            _quota.value = EntitlementQuota(
                planLeft = kotlin.math.max(0, state.quotaTotal - state.quotaUsed),
                total = state.quotaTotal,
                purchased = state.purchased,
                left = state.quotaLeft,
                resetDate = row?.quotaResetDate,
            )
            _entitlementKnown.value = true
        }.launchIn(viewModelScope)
    }

    val isOutOfQuota: Boolean get() = _quota.value?.let { it.left <= 0 } ?: false

    // ---- navigation between the landing and a chat ----

    fun newChat(greeting: String) {
        conversation = emptyList()
        threadId = null
        clearPending()
        // Local-only greeting: not persisted, not sent to the model. Web says
        // the same in its own comment, and it matters -- a greeting in the
        // model's context would be an assistant turn with nothing before it.
        _bubbles.value = listOf(bubble("assistant", greeting))
        _view.value = "chat"
    }

    fun openThread(id: String) {
        clearPending()
        threadId = id
        _view.value = "chat"
        viewModelScope.launch {
            val rows = assistantRepository.messagesOnce(id)
            _bubbles.value = rows.map { ChatBubble(it.id, it.role, it.content) }
            // Rebuild the model's context from the TEXT transcript. Tool blocks
            // were never persisted, so a reopened thread has no memory of the
            // calls it made -- web accepts the same loss.
            conversation = rows
                .filter { it.role == "user" || it.role == "assistant" }
                .map { ApiMessage(role = it.role, textContent = it.content) }
        }
    }

    fun backToLanding() {
        _view.value = "landing"
    }

    fun deleteThread(id: String) {
        viewModelScope.launch { assistantRepository.deleteThread(id) }
    }

    // ---- sending ----

    /**
     * Send a message.
     *
     * The snapshot and the remembered facts are rebuilt on EVERY send, not
     * cached: the user may have added a transaction between two questions, and
     * an assistant answering from a stale balance is worse than a slow one.
     */
    fun send(raw: String, errorText: (String, String) -> String) {
        val text = raw.trim()
        if (text.isEmpty() || _busy.value || _pendingTool.value != null || isOutOfQuota) return
        val userId = authRepository.currentUserId.value ?: return

        _bubbles.value = _bubbles.value + bubble("user", text)
        _view.value = "chat"

        viewModelScope.launch {
            val base = baseCurrencyNow()
            val context = runCatching {
                val summary = assistantRepository.buildFinancialSummary(
                    userId = userId,
                    baseCurrency = base,
                    todayIso = LocalDate.now().toString(),
                    nowMillis = System.currentTimeMillis(),
                )
                val memory = assistantRepository.loadMemory(userId)
                listOf(
                    "Today: ${summary.today}. Base currency: ${summary.baseCurrency}.",
                    "User's aggregated financial snapshot (the only financial data you have):",
                    summaryForPrompt(summary),
                    "",
                    "What you remember about this user:",
                    memory.ifEmpty { "Nothing yet." },
                ).joinToString("\n")
            }.getOrNull()

            _payload.value = context
            // On failure the PERSONA still goes -- an assistant with no snapshot
            // can still explain the app, and web degrades the same way.
            systemBlocks = if (context != null) listOf(ASSISTANT_PERSONA, context) else listOf(ASSISTANT_PERSONA)

            if (threadId == null) {
                threadId = assistantRepository.createThread(userId, assistantThreadTitle(text))
            }
            threadId?.let { runCatching { assistantRepository.appendMessage(userId, it, "user", text) } }

            conversation = conversation + ApiMessage(role = "user", textContent = text)
            runTurn(conversation, userId, base, errorText)
        }
    }

    /**
     * One round trip, plus whatever it leads to.
     *
     * Recursive, like web's. A turn that ends in auto-runnable tools sends their
     * results straight back; a turn that ends in a confirmable one stops here
     * and waits for [resolvePending].
     */
    private suspend fun runTurn(
        messages: List<ApiMessage>,
        userId: String,
        baseCurrency: String,
        errorText: (String, String) -> String,
    ) {
        _busy.value = true
        val response = assistantRepository.callModel(systemBlocks, messages)
        _busy.value = false

        val content = response.content
        if (content == null) {
            val message = errorText(assistantErrorKey(response.error), response.error.orEmpty())
            _bubbles.value = _bubbles.value + bubble("assistant", message)
            return
        }

        val withAssistant = messages + ApiMessage(role = "assistant", blocks = content)
        conversation = withAssistant

        val plan = planAssistantTurn(content)
        if (plan.text.isNotEmpty()) {
            _bubbles.value = _bubbles.value + bubble("assistant", plan.text)
            threadId?.let { runCatching { assistantRepository.appendMessage(userId, it, "assistant", plan.text) } }
        }

        val results = mutableListOf<AssistantContent>()
        for (tool in plan.autoRun) {
            val result = runCatching {
                assistantRepository.executeTool(userId, tool.name, tool.input, baseCurrency)
            }.getOrElse { "Error: ${it.message}" }
            results.add(AssistantContent.Result(tool.id, result))
        }
        for (tool in plan.rejected) {
            results.add(AssistantContent.Result(tool.id, ASSISTANT_TOOL_REJECTED))
        }

        if (plan.confirmQueue.isEmpty()) {
            if (results.isEmpty()) return
            val next = withAssistant + ApiMessage(role = "user", blocks = results)
            conversation = next
            runTurn(next, userId, baseCurrency, errorText)
        } else {
            pendingMessages = withAssistant
            pendingResults = results
            pendingRest = plan.confirmQueue.drop(1)
            _pendingTool.value = plan.confirmQueue.first()
        }
    }

    /** Confirm or skip the card on screen, then continue the chain. */
    fun resolvePending(confirmed: Boolean, errorText: (String, String) -> String) {
        val tool = _pendingTool.value ?: return
        val userId = authRepository.currentUserId.value ?: return
        val baseCurrency = baseCurrencyNow()
        _pendingTool.value = null

        viewModelScope.launch {
            val result = if (confirmed) {
                runCatching {
                    assistantRepository.executeTool(userId, tool.name, tool.input, baseCurrency)
                }.getOrElse { "Error: ${it.message}" }
            } else {
                ASSISTANT_TOOL_DECLINED
            }
            val note = assistantActionNote(tool.name, tool.input, baseCurrency, confirmed)
            _bubbles.value = _bubbles.value + bubble("action", note)
            threadId?.let { runCatching { assistantRepository.appendMessage(userId, it, "action", note) } }

            pendingResults = pendingResults + AssistantContent.Result(tool.id, result)
            if (pendingRest.isEmpty()) {
                val next = pendingMessages + ApiMessage(role = "user", blocks = pendingResults)
                conversation = next
                clearPending()
                runTurn(next, userId, baseCurrency, errorText)
            } else {
                _pendingTool.value = pendingRest.first()
                pendingRest = pendingRest.drop(1)
            }
        }
    }

    /** The one-line summary on the confirmation card. */
    fun describePending(tool: ToolUse): String = describeToolCall(tool.name, tool.input, baseCurrencyNow())

    private fun clearPending() {
        _pendingTool.value = null
        pendingRest = emptyList()
        pendingResults = emptyList()
        pendingMessages = emptyList()
    }

    private fun bubble(role: String, text: String) = ChatBubble("b${++bubbleCounter}", role, text)
}
