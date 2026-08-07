package com.sanvya.app.ui.receipts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.ReceiptsRepository
import com.sanvya.app.data.repository.SaveScanInput
import com.sanvya.app.domain.receipts.ParseOptions
import com.sanvya.app.domain.receipts.ReceiptDraft
import com.sanvya.app.domain.receipts.parseReceiptText
import com.sanvya.app.domain.receipts.reconcile
import com.sanvya.app.domain.receipts.subtotals
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.LocalDate
import java.time.ZoneOffset

/** Mirrors `ScanStage` (apps/web/src/receipts/scan.ts) minus the AI stage --
 * see docs/mobile/screen-specs/receipt-scan.md scope note #2. */
sealed class CaptureStage {
    object Idle : CaptureStage()
    object Preparing : CaptureStage()
    object Reading : CaptureStage()
    object Understanding : CaptureStage()
    /** Couldn't read this cleanly -- mirrors `describeMismatch` in
     * apps/web/app/receipts/new/page.tsx. */
    data class Mismatch(val reason: String) : CaptureStage()
    data class Error(val message: String) : CaptureStage()
}

/** Instantiated via the parameterless `viewModel()` factory, matching every
 * other screen ViewModel in this app. Owns the OCR -> parse -> reconcile
 * pipeline and the scan save; CameraX/ML Kit plumbing itself lives in
 * ReceiptCaptureScreen.kt (Context/lifecycle-bound, doesn't belong here). */
class ReceiptCaptureViewModel : ViewModel(), KoinComponent {
    private val receiptsRepository: ReceiptsRepository by inject()

    private val _stage = MutableStateFlow<CaptureStage>(CaptureStage.Idle)
    val stage: StateFlow<CaptureStage> = _stage

    /** Set once a scan is saved -- the screen navigates to review on this
     * becoming non-null. */
    private val _savedScanId = MutableStateFlow<String?>(null)
    val savedScanId: StateFlow<String?> = _savedScanId

    private var pendingDraft: ReceiptDraft? = null

    fun onCaptureStarted() {
        _stage.value = CaptureStage.Preparing
    }

    fun onReadingStarted() {
        _stage.value = CaptureStage.Reading
    }

    /** Called once ML Kit hands back recognized text. Text-only path --
     * see receipt-scan.md scope note #3 (no per-word bounding boxes). */
    fun onTextRecognized(rawText: String) {
        _stage.value = CaptureStage.Understanding
        val today = LocalDate.now(ZoneOffset.UTC).toString()
        val draft = parseReceiptText(rawText, ParseOptions(currency = "INR", today = today, engine = "tesseract"))
        pendingDraft = draft
        val rec = reconcile(draft)
        if (rec.ok) {
            commit(draft)
        } else {
            _stage.value = CaptureStage.Mismatch(rec.reason)
        }
    }

    fun onCaptureFailed(message: String) {
        _stage.value = CaptureStage.Error(message)
    }

    /** "Edit it myself" -- saves the unreconciled draft anyway, exactly like
     * web's `commit(result.draft, source)` on that button. */
    fun editManually() {
        val draft = pendingDraft ?: return
        commit(draft)
    }

    fun retake() {
        pendingDraft = null
        _stage.value = CaptureStage.Idle
    }

    /** Human-facing reason text -- mirrors `describeMismatch` exactly. */
    fun mismatchMessage(reason: String): String = when (reason) {
        "no_lines" -> "We couldn't find any items on this receipt."
        "missing_total" -> "We read the items but couldn't find the total."
        else -> "The items we read don't add up to the printed total."
    }

    private fun commit(draft: ReceiptDraft) {
        viewModelScope.launch {
            try {
                val s = subtotals(draft.lines)
                val id = receiptsRepository.saveScan(
                    SaveScanInput(
                        source = "camera",
                        engine = draft.engine,
                        merchant = draft.merchant,
                        occurredAt = draft.occurredAt,
                        currency = draft.currency,
                        subtotal = s.items,
                        tax = s.tax,
                        serviceCharge = s.serviceCharge,
                        tip = s.tip,
                        discount = s.discount,
                        total = draft.total,
                        confidence = draft.confidence.toLong(),
                        rawText = draft.rawText,
                        parsedJson = draft.toJsonString(),
                    )
                )
                _savedScanId.value = id
            } catch (e: Exception) {
                _stage.value = CaptureStage.Error(e.message ?: "Couldn't save this scan.")
            }
        }
    }
}
