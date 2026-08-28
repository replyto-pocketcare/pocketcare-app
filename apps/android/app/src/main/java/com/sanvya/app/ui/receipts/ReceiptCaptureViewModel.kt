package com.sanvya.app.ui.receipts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.data.repository.ReceiptsRepository
import com.sanvya.app.data.repository.SaveScanInput
import com.sanvya.app.domain.receipts.ParseOptions
import com.sanvya.app.domain.receipts.ReceiptDraft
import com.sanvya.app.domain.receipts.parseReceiptText
import com.sanvya.app.domain.receipts.reconcile
import com.sanvya.app.domain.receipts.subtotals
import com.sanvya.app.domain.entitlements.isPaid
import com.sanvya.app.i18n.S
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.time.LocalDate
import java.time.ZoneOffset
import com.sanvya.app.ui.baseCurrencyNow

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
    /**
     * An encrypted PDF, waiting on a password.
     *
     * A separate stage rather than an Error because it is not a failure: web
     * keeps the file and shows a password form, and re-running with the
     * password is the SAME scan, not a retake.
     */
    object NeedsPassword : CaptureStage()
    data class Error(val message: String) : CaptureStage()
}

/** Where the file came from. Stored on the scan row, exactly as web does. */
object ScanSource {
    const val CAMERA = "camera"
    const val UPLOAD = "upload"
}

/** Instantiated via the parameterless `viewModel()` factory, matching every
 * other screen ViewModel in this app. Owns the OCR -> parse -> reconcile
 * pipeline and the scan save; CameraX/ML Kit plumbing itself lives in
 * ReceiptCaptureScreen.kt (Context/lifecycle-bound, doesn't belong here). */
class ReceiptCaptureViewModel : ViewModel(), KoinComponent {
    private val receiptsRepository: ReceiptsRepository by inject()
    private val prefsRepository: PrefsRepository by inject()

    private val _stage = MutableStateFlow<CaptureStage>(CaptureStage.Idle)
    val stage: StateFlow<CaptureStage> = _stage

    /** Set once a scan is saved -- the screen navigates to review on this
     * becoming non-null. */
    private val _savedScanId = MutableStateFlow<String?>(null)
    val savedScanId: StateFlow<String?> = _savedScanId

    private var pendingDraft: ReceiptDraft? = null

    /**
     * Whether receipt scanning is available -- Lite, Pro, or an active trial.
     *
     * Same derivation as the shell's own `canScan`, and web gates this screen
     * on exactly the same value. It is a COURTESY gate: the receipt-scan edge
     * function enforces the rule server-side regardless. Without it a free user
     * met a server rejection where web shows them a plan card, which reads as
     * the app being broken rather than the feature being paid.
     *
     * Starts closed and stays closed if the entitlement cannot be read. A gate
     * that fails open is not a gate.
     */
    private val _canScan = MutableStateFlow(false)
    val canScan: StateFlow<Boolean> = _canScan

    init {
        viewModelScope.launch {
            prefsRepository.watchEntitlement()
                .catch { /* offline -- keep the last known tier */ }
                .collectLatest { row ->
                    _canScan.value = isPaid(
                        row?.tier,
                        row?.premiumTrialStartDate,
                        row?.compTier,
                        row?.compUntil,
                        System.currentTimeMillis(),
                    )
                }
        }
    }

    fun onCaptureStarted() {
        source = ScanSource.CAMERA
        _stage.value = CaptureStage.Preparing
    }

    /** A file was chosen from the picker -- an image or a PDF. */
    fun onUploadStarted() {
        source = ScanSource.UPLOAD
        _stage.value = CaptureStage.Preparing
    }

    /** The chosen PDF is encrypted; web keeps the file and asks. */
    fun onPasswordRequired() {
        _stage.value = CaptureStage.NeedsPassword
    }

    private var source: String = ScanSource.CAMERA

    fun onReadingStarted() {
        _stage.value = CaptureStage.Reading
    }

    /** Called once ML Kit hands back recognized text. Text-only path --
     * see receipt-scan.md scope note #3 (no per-word bounding boxes). */
    fun onTextRecognized(rawText: String) = ingest(rawText, engine = "tesseract")

    /**
     * A PDF's text layer, already flattened to lines.
     *
     * Web's PDF branch skips OCR entirely and calls `parseReceiptText` on the
     * joined rows -- an emailed bill is the single most accurate input this
     * feature accepts, which is why it is worth the separate path. The engine
     * is recorded as "pdf" rather than an OCR engine that never ran.
     */
    fun onPdfText(res: android.content.res.Resources, text: String) {
        // Web's own floor: below this there is no text layer worth parsing, and
        // rasterising a scan to OCR it reads worse than photographing the paper
        // -- which is what the message says, in web's own words.
        if (text.trim().length < PDF_TEXT_FLOOR) {
            _stage.value = CaptureStage.Error(S.Receipts.errorsPdfNoText(res))
            return
        }
        ingest(text, engine = "pdf")
    }

    private fun ingest(rawText: String, engine: String) {
        _stage.value = CaptureStage.Understanding
        val today = LocalDate.now(ZoneOffset.UTC).toString()
        val draft = parseReceiptText(rawText, ParseOptions(currency = baseCurrencyNow(), today = today, engine = engine))
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
    fun mismatchMessage(res: android.content.res.Resources, reason: String): String = when (reason) {
        "no_lines" -> S.Receipts.captureUnclearNoLines(res)
        "missing_total" -> S.Receipts.captureUnclearNoTotal(res)
        else -> S.Receipts.captureUnclearMismatch(res)
    }

    private fun commit(draft: ReceiptDraft) {
        viewModelScope.launch {
            try {
                val s = subtotals(draft.lines)
                val id = receiptsRepository.saveScan(
                    SaveScanInput(
                        source = source,
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
                        // Web caps the stored dump: a long grocery bill's OCR
                        // output is not worth syncing in full, and it is only
                        // ever used for re-parsing and debugging.
                        rawText = draft.rawText?.take(RAW_TEXT_CAP),
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

/** Web's `raw_text: draft.rawText.slice(0, 8000)`. */
private const val RAW_TEXT_CAP = 8000

/**
 * Below this many characters, a PDF has no text layer worth parsing.
 *
 * Web's own floor. It could rasterise and OCR the page instead, but a photo of
 * the paper beats a photo of a scan, so it says so rather than trying.
 */
private const val PDF_TEXT_FLOOR = 20
