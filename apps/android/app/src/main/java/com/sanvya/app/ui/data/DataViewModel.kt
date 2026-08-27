package com.sanvya.app.ui.data

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.data.repository.nowIso
import com.sanvya.app.domain.csv.CanonRow
import com.sanvya.app.domain.csv.IMPORT_ADAPTERS
import com.sanvya.app.domain.csv.parseWithAdapter
import com.sanvya.app.domain.entitlements.isPaid
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/** A CSV waiting for the user to choose where it goes. */
data class PendingExport(val csv: String, val suggestedName: String)

data class DataState(
    val exporting: Boolean = false,
    val exportMessage: String? = null,
    val fileName: String? = null,
    val parsedRows: List<CanonRow>? = null,
    val parseError: String? = null,
    val importing: Boolean = false,
    val result: LedgerRepository.ImportResult? = null,
)

/**
 * Import & export -- ported from apps/web/app/data/page.tsx.
 *
 * The CSV itself is domain's (vector-tested) and the two database halves are
 * `LedgerRepository.exportTransactionsCsv` / `importTransactions`. What is here
 * is the screen's state machine: parse a picked file, preview it, import it.
 *
 * **File picking is NOT here.** Choosing where a file goes has no shared shape
 * across a browser anchor, a UIDocumentPicker and Android's SAF, so the screen
 * hands this model the TEXT it read and takes back the text to write.
 *
 * Mirrors apps/ios/App/ViewModels/DataViewModel.swift.
 */
class DataViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val prefsRepository: PrefsRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _state = MutableStateFlow(DataState())
    val state: StateFlow<DataState> = _state.asStateFlow()

    private val _adapterId = MutableStateFlow(IMPORT_ADAPTERS.first().id)
    val adapterId: StateFlow<String> = _adapterId.asStateFlow()

    private val _skipDuplicates = MutableStateFlow(true)
    val skipDuplicates: StateFlow<Boolean> = _skipDuplicates.asStateFlow()

    /** Set when a CSV is ready; the screen turns it into a file, then clears it. */
    private val _pendingExport = MutableStateFlow<PendingExport?>(null)
    val pendingExport: StateFlow<PendingExport?> = _pendingExport.asStateFlow()

    /**
     * Web blocks import during the free trial and shows the upgrade note.
     * `null` until the entitlement has been read, so the screen shows neither
     * the form nor the upsell before it knows -- the same "keep the gate closed,
     * but say nothing yet" rule the Statements screen uses.
     */
    val isPaidUser: StateFlow<Boolean?> = prefsRepository.watchEntitlement()
        .map { row ->
            isPaid(
                row?.tier,
                row?.premiumTrialStartDate,
                row?.compTier,
                row?.compUntil,
                System.currentTimeMillis(),
            )
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    fun setAdapterId(v: String) {
        _adapterId.value = v
        _state.value = _state.value.copy(parsedRows = null, parseError = null, result = null)
    }

    fun setSkipDuplicates(v: Boolean) { _skipDuplicates.value = v }

    fun consumePendingExport() { _pendingExport.value = null }

    fun exportCsv(noExportMessage: String, failedMessage: (String) -> String, exportedMessage: (Int) -> String) {
        if (_state.value.exporting) return
        _state.value = _state.value.copy(exporting = true, exportMessage = null)
        viewModelScope.launch {
            try {
                val out = ledgerRepository.exportTransactionsCsv()
                if (out.count == 0) {
                    _state.value = _state.value.copy(exporting = false, exportMessage = noExportMessage)
                    return@launch
                }
                _pendingExport.value = PendingExport(
                    csv = out.csv,
                    suggestedName = "sanvya-transactions-${nowIso().take(10)}.csv",
                )
                _state.value = _state.value.copy(exporting = false, exportMessage = exportedMessage(out.count))
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    exporting = false,
                    exportMessage = failedMessage(e.message ?: e.toString()),
                )
            }
        }
    }

    /** The screen read a file; parse it with the selected adapter. */
    fun parse(fileName: String, text: String, noRowsMessage: String) {
        val rows = parseWithAdapter(_adapterId.value, text, nowIso())
        _state.value = _state.value.copy(
            fileName = fileName,
            result = null,
            parseError = if (rows.isEmpty()) noRowsMessage else null,
            parsedRows = rows.ifEmpty { null },
        )
    }

    fun failedToRead(message: String) {
        _state.value = _state.value.copy(
            parsedRows = null,
            result = null,
            parseError = message,
        )
    }

    fun runImport(baseCurrency: String) {
        val rows = _state.value.parsedRows ?: return
        if (_state.value.importing) return
        _state.value = _state.value.copy(importing = true, result = null)
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value
            if (userId == null) {
                _state.value = _state.value.copy(importing = false)
                return@launch
            }
            val out = try {
                ledgerRepository.importTransactions(
                    userId = userId,
                    rows = rows,
                    baseCurrency = baseCurrency,
                    stampIso = nowIso(),
                    skipDuplicates = _skipDuplicates.value,
                )
            } catch (e: Exception) {
                LedgerRepository.ImportResult(
                    created = 0,
                    skipped = 0,
                    failed = rows.size,
                    errors = listOf(e.message ?: e.toString()),
                )
            }
            _state.value = _state.value.copy(
                importing = false,
                result = out,
                parsedRows = null,
                fileName = null,
            )
        }
    }
}
