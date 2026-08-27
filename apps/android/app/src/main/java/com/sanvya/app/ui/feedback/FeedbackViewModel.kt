package com.sanvya.app.ui.feedback

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.diagnostics.diagnosticsReport
import com.sanvya.app.data.repository.BugReportDraft
import com.sanvya.app.data.repository.FeedbackRepository
import com.sanvya.app.domain.feedback.FEEDBACK_APP_VERSION
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/** The form, as the user has filled it in so far. */
data class FeedbackUiState(
    /** "bug" | "suggestion". */
    val kind: String = "bug",
    val severity: String = "medium",
    val area: String = "",
    val title: String = "",
    val description: String = "",
    /**
     * Default ON.
     *
     * Web's comment: "the whole point is that the diagnosis arrives without the
     * user having to do anything. It's redacted, and the checkbox says so."
     */
    val includeLog: Boolean = true,
    val busy: Boolean = false,
    val done: Boolean = false,
    /** An i18n KEY, resolved by the sheet. Null when there is nothing wrong. */
    val errorKey: String? = null,
) {
    val isBug: Boolean get() = kind == "bug"
    val canSubmit: Boolean get() = !busy && description.isNotBlank()
}

/**
 * Sending feedback -- ported from `apps/web/src/ui/BugReport.tsx`.
 *
 * Mirrors iOS's FeedbackViewModel.
 */
class FeedbackViewModel : ViewModel(), KoinComponent {
    private val feedbackRepository: FeedbackRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _state = MutableStateFlow(FeedbackUiState())
    val state: StateFlow<FeedbackUiState> = _state.asStateFlow()

    fun setKind(v: String) = update { it.copy(kind = v, errorKey = null) }
    fun setSeverity(v: String) = update { it.copy(severity = v) }
    fun setArea(v: String) = update { it.copy(area = v) }
    fun setTitle(v: String) = update { it.copy(title = v) }
    fun setDescription(v: String) = update { it.copy(description = v, errorKey = null) }
    fun setIncludeLog(v: Boolean) = update { it.copy(includeLog = v) }

    /** Web's `reset()` -- back to a blank form, staying on the sheet. */
    fun reset() { _state.value = FeedbackUiState() }

    /**
     * File it.
     *
     * [route] is the shell's current route, standing in for web's `pathname`;
     * the rest of the captured context is the platform's and is gathered by the
     * sheet, which is the only layer that can see a window.
     */
    fun submit(route: String, platform: String, userAgent: String, viewport: String, online: Boolean) {
        val s = _state.value
        if (s.busy) return
        if (s.description.isBlank()) {
            update { it.copy(errorKey = if (s.isBug) "errNeedBug" else "errNeedSuggestion") }
            return
        }
        val userId = authRepository.currentUserId.value ?: return
        update { it.copy(busy = true, errorKey = null) }
        viewModelScope.launch {
            val result = runCatching {
                feedbackRepository.submit(
                    userId = userId,
                    draft = BugReportDraft(
                        kind = s.kind,
                        severity = if (s.isBug) s.severity else null,
                        area = s.area,
                        title = s.title,
                        description = s.description,
                        diagnostics = if (s.includeLog) {
                            diagnosticsReport(mapOf("version" to FEEDBACK_APP_VERSION, "route" to route))
                        } else {
                            null
                        },
                        route = route,
                        platform = platform,
                        userAgent = userAgent,
                        viewport = viewport,
                        online = online,
                    ),
                )
            }
            update {
                if (result.isSuccess) {
                    it.copy(busy = false, done = true)
                } else {
                    it.copy(busy = false, errorKey = "errSubmit")
                }
            }
        }
    }

    private inline fun update(block: (FeedbackUiState) -> FeedbackUiState) {
        _state.value = block(_state.value)
    }
}
