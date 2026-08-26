package com.sanvya.app.ui.reflect

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LedgerRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/** One thing the user did this visit. */
data class ReflectStep(val id: String, val judged: Boolean)

data class ReflectState(
    val visible: List<LedgerRepository.IntentQueueRow> = emptyList(),
    val isLoading: Boolean = true,
    val canUndo: Boolean = false,
)

/**
 * Reflect -- ported from apps/web/app/reflect/page.tsx.
 *
 * A card stack over untagged expenses: swipe left for "need", right for
 * "greed". Judging writes `transactions.intent`; skipping writes nothing and
 * only hides the card for this visit.
 *
 * **The history is what makes Undo work, and it is deliberately local.** Web
 * keeps the same list in component state: an undone judgement re-clears
 * `intent`, which brings the row back into the query naturally, and an undone
 * *skip* just stops hiding it. Persisting the history would mean a second
 * source of truth for something the ledger already records.
 *
 * Mirrors apps/ios/App/ViewModels/ReflectViewModel.swift.
 */
class ReflectViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()

    private val history = MutableStateFlow<List<ReflectStep>>(emptyList())

    val state: StateFlow<ReflectState> = combine(
        // `null` until the first emission, so "loading" and "the queue is
        // empty" are different states. They render very differently -- one is a
        // spinner, the other is "All caught up!" -- and an empty list cannot
        // tell them apart.
        ledgerRepository.watchIntentQueue()
            .map<List<LedgerRepository.IntentQueueRow>, List<LedgerRepository.IntentQueueRow>?> { it }
            .onStart { emit(null) },
        history,
    ) { rows, steps ->
        // A judged row leaves the query on its own once the write lands, but
        // not before the next emission -- so it is filtered here too, or the
        // card would flick back for a frame.
        val handled = steps.map { it.id }.toSet()
        ReflectState(
            visible = rows.orEmpty().filter { it.id !in handled },
            isLoading = rows == null,
            canUndo = steps.isNotEmpty(),
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ReflectState())

    fun judge(id: String, intent: String) {
        history.value = history.value + ReflectStep(id, judged = true)
        viewModelScope.launch { runCatching { ledgerRepository.setIntent(id, intent) } }
    }

    fun skip(id: String) {
        history.value = history.value + ReflectStep(id, judged = false)
    }

    fun undo() {
        val last = history.value.lastOrNull() ?: return
        history.value = history.value.dropLast(1)
        if (!last.judged) return
        viewModelScope.launch { runCatching { ledgerRepository.setIntent(last.id, null) } }
    }
}
