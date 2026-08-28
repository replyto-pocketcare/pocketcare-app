package com.sanvya.app.ui.receipts

import android.graphics.Bitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.AiScanError
import com.sanvya.app.data.repository.PrefsRepository
import com.sanvya.app.data.repository.ReceiptsRepository
import com.sanvya.app.data.repository.SaveScanInput
import com.sanvya.app.domain.receipts.ParseOptions
import com.sanvya.app.domain.receipts.ReceiptDraft
import com.sanvya.app.domain.receipts.parseReceiptText
import com.sanvya.app.domain.receipts.shouldEscalate
import com.sanvya.app.domain.receipts.reconcile
import com.sanvya.app.domain.receipts.subtotals
import com.sanvya.app.domain.entitlements.entitlementState
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

    /**
     * AI reads left this month. Web shows the count on the button and swaps the
     * whole note for an upgrade line at zero, because "Improve with AI" that
     * silently fails is worse than one that says why it cannot.
     */
    private val _quotaLeft = MutableStateFlow(0)
    val quotaLeft: StateFlow<Int> = _quotaLeft

    /**
     * Whether "Improve with AI" is worth offering, and the bytes it would send.
     *
     * Non-null ONLY for a photograph that did not reconcile: a PDF has no image
     * to escalate with (web's `canEscalate: false` on that branch), and a clean
     * read never reaches the card at all. Held here rather than in the screen
     * because the screen is recreated on rotation and the photo is not
     * retakeable once the camera has closed.
     */
    private var pendingImage: EscalationImage? = null

    /** True when the mismatch card should offer the AI button. */
    private val _canEscalate = MutableStateFlow(false)
    val canEscalate: StateFlow<Boolean> = _canEscalate

    /**
     * The photo, shrunk for the "couldn't read this cleanly" card.
     *
     * Web puts the picture on that card and it is the whole reason the card is
     * answerable: "the items don't add up to the total" is a claim about a
     * piece of paper the user can no longer see, and without it "Improve with
     * AI" and "Retake" are a coin toss. Both ports drew the card and neither
     * drew the photo.
     *
     * A DOWNSCALED copy, not the capture. A 12-megapixel frame is tens of
     * megabytes decoded and this is a 220dp thumbnail; holding the original
     * would trade an OOM for a preview. The full bytes stay in [pendingImage]
     * where the escalation needs them, and neither copy is ever written to disk.
     */
    private val _previewImage = MutableStateFlow<Bitmap?>(null)
    val previewImage: StateFlow<Bitmap?> = _previewImage

    private val _aiBusy = MutableStateFlow(false)
    val aiBusy: StateFlow<Boolean> = _aiBusy

    init {
        viewModelScope.launch {
            prefsRepository.watchEntitlement()
                .catch { /* offline -- keep the last known tier */ }
                .collectLatest { row ->
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
                    _canScan.value = state.isPaid
                    _quotaLeft.value = state.quotaLeft
                }
        }
    }

    fun onCaptureStarted() {
        source = ScanSource.CAMERA
        _stage.value = CaptureStage.Preparing
    }

    /**
     * The photo, kept in memory for a possible escalation.
     *
     * Called by the screen just before OCR. Nothing here is written to disk or
     * to the database: `receipt_scans.image_path` stays null on both platforms,
     * exactly as web promises, and this copy dies with the ViewModel.
     */
    fun onImageCaptured(base64: String, mediaType: String) {
        pendingImage = EscalationImage(base64, mediaType)
    }

    /**
     * The decoded, correctly-rotated photo, for the on-screen preview.
     *
     * Separate from [onImageCaptured] because the two want different things:
     * the escalation wants the ORIGINAL bytes (a re-encode reads measurably
     * worse to the model), and the preview wants a small upright bitmap. The
     * screen already holds both at the moment of capture, so neither is
     * re-derived here.
     */
    fun onPreviewImage(bitmap: Bitmap) {
        _previewImage.value = downscaleForPreview(bitmap)
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
     * feature accepts, which is why it is worth the separate path.
     *
     * The engine is left NULL, not set: `parseReceiptText` defaults it to
     * "pdf_text", which is the value web writes and the value the review
     * screen and `receipt_scans.engine` already understand. Naming a new one
     * here would have put a value in the column nothing else recognises.
     */
    fun onPdfText(res: android.content.res.Resources, text: String) {
        // Web's own floor: below this there is no text layer worth parsing, and
        // rasterising a scan to OCR it reads worse than photographing the paper
        // -- which is what the message says, in web's own words.
        if (text.trim().length < PDF_TEXT_FLOOR) {
            _stage.value = CaptureStage.Error(S.Receipts.errorsPdfNoText(res))
            return
        }
        ingest(text, engine = null)
    }

    private fun ingest(rawText: String, engine: String?) {
        _stage.value = CaptureStage.Understanding
        val today = LocalDate.now(ZoneOffset.UTC).toString()
        val draft = parseReceiptText(rawText, ParseOptions(currency = baseCurrencyNow(), today = today, engine = engine))
        pendingDraft = draft
        // A PDF has no image to escalate with -- web sets `canEscalate: false`
        // on that branch outright, and offering a button that cannot work is
        // worse than not offering one.
        _canEscalate.value = pendingImage != null && shouldEscalate(draft)
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
        pendingImage = null
        _previewImage.value = null
        _canEscalate.value = false
        _stage.value = CaptureStage.Idle
    }

    /**
     * "Improve with AI" -- send the ORIGINAL photo for a second reading.
     *
     * The on-device read is kept and passed along as `rawText`: web does the
     * same, and it is what lets the review screen show what the phone thought
     * next to what the model thought.
     *
     * A successful escalation commits straight to review, exactly as web's
     * `improveWithAi` does -- the user asked for a better read, not for another
     * decision.
     */
    fun improveWithAi(res: android.content.res.Resources) {
        val image = pendingImage ?: return
        if (_aiBusy.value) return
        _aiBusy.value = true
        viewModelScope.launch {
            try {
                val draft = receiptsRepository.aiParseReceipt(
                    base64 = image.base64,
                    mediaType = image.mediaType,
                    currencyHint = baseCurrencyNow(),
                    today = LocalDate.now(ZoneOffset.UTC).toString(),
                    rawText = pendingDraft?.rawText,
                )
                pendingDraft = draft
                commit(draft)
            } catch (e: AiScanError) {
                // The quota case is not hidden behind a generic failure: web
                // swaps the whole note for an upgrade line, and it can only do
                // that because the error says which failure it was.
                _stage.value = CaptureStage.Error(e.message ?: S.Receipts.errorsPdfUnreadable(res))
            } catch (e: Exception) {
                _stage.value = CaptureStage.Error(e.message ?: S.Receipts.errorsPdfUnreadable(res))
            } finally {
                _aiBusy.value = false
            }
        }
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

/**
 * The photo, base64-encoded, ready for the edge function.
 *
 * A tiny type rather than two loose fields because the two must travel
 * together: sending the bytes with the wrong media type is a silent
 * misread, not an error.
 */
data class EscalationImage(val base64: String, val mediaType: String)

/**
 * Shrink a capture to preview size, preserving its aspect ratio.
 *
 * Returns the original when it is already small enough — `createScaledBitmap`
 * would otherwise allocate a second copy of the same picture.
 */
private fun downscaleForPreview(source: Bitmap): Bitmap {
    val longEdge = maxOf(source.width, source.height)
    if (longEdge <= PREVIEW_LONG_EDGE_PX) return source
    val scale = PREVIEW_LONG_EDGE_PX.toFloat() / longEdge
    return Bitmap.createScaledBitmap(
        source,
        (source.width * scale).toInt().coerceAtLeast(1),
        (source.height * scale).toInt().coerceAtLeast(1),
        true,
    )
}

/**
 * Long edge of the preview copy, in pixels.
 *
 * The card shows it at 220dp tall; this leaves headroom for a 3x screen without
 * keeping a photograph in memory behind a thumbnail.
 */
private const val PREVIEW_LONG_EDGE_PX = 720
