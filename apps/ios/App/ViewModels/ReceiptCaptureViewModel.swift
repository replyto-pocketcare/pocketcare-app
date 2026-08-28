import Foundation
import Observation
import Factory
import Data
import Domain

/// Mirrors `ScanStage` (apps/web/src/receipts/scan.ts) minus the AI stage --
/// see docs/mobile/screen-specs/receipt-scan.md scope note #2.
public enum CaptureStage: Equatable {
    case idle
    case preparing
    case reading
    case understanding
    /// Couldn't read this cleanly -- mirrors `describeMismatch` in
    /// apps/web/app/receipts/new/page.tsx.
    case mismatch(reason: String)
    /// An encrypted PDF, waiting on a password.
    ///
    /// A separate case rather than an error because it is not a failure: web
    /// keeps the file and shows a password form, and re-running with the
    /// password is the SAME scan, not a retake.
    case needsPassword
    case error(String)
}

/// Where the file came from. Stored on the scan row, exactly as web does.
public enum ScanSource {
    public static let camera = "camera"
    public static let upload = "upload"
}

/// Real port of apps/web/app/receipts/new/page.tsx's camera path (task
/// #62). Owns the OCR -> parse -> reconcile pipeline and the scan save;
/// AVFoundation/Vision plumbing lives in ReceiptCaptureView.swift
/// (UIKit/AVCaptureSession-bound, doesn't belong here). `@Injected` +
/// plain `ReceiptCaptureViewModel()` init at the call site -- matches
/// GroupDetailViewModel/SplitsViewModel's convention (this app's newer
/// ViewModels), not the older constructor-injection-via-Factory pattern
/// TransactionsViewModel/DashboardViewModel use.
@Observable
@MainActor
public final class ReceiptCaptureViewModel {
    @ObservationIgnored @Injected(\.receiptsRepository) private var receiptsRepository
    @ObservationIgnored @Injected(\.prefsRepository) private var prefsRepository
    private var pendingDraft: ReceiptDraft?
    private var source = ScanSource.camera
    @ObservationIgnored private var entitlementTask: Task<Void, Never>?

    public var stage: CaptureStage = .idle

    /// Whether receipt scanning is available — Lite, Pro, or an active trial.
    ///
    /// Same derivation as the shell's own `canScan`, and web gates this screen
    /// on exactly the same value. It is a COURTESY gate: the receipt-scan edge
    /// function enforces the rule server-side regardless. Without it a free
    /// user met a server rejection where web shows them a plan card, which
    /// reads as the app being broken rather than the feature being paid.
    ///
    /// Starts closed and stays closed if the entitlement cannot be read. A gate
    /// that fails open is not a gate.
    public var canScan = false

    /// AI reads left this month. Web shows the count on the button and swaps
    /// the whole note for an upgrade line at zero, because "Improve with AI"
    /// that silently fails is worse than one that says why it cannot.
    public var quotaLeft = 0

    /// True when the mismatch card should offer the AI button.
    public var canEscalate = false
    public var aiBusy = false

    /// The photo, kept in memory for a possible escalation.
    ///
    /// Non-nil ONLY for a photograph that did not reconcile: a PDF has no image
    /// to escalate with (web's `canEscalate: false` on that branch). Nothing
    /// here is written to disk or to the database — `receipt_scans.image_path`
    /// stays null on both platforms, exactly as web promises, and this copy
    /// dies with the view model.
    @ObservationIgnored private var pendingImage: EscalationImage?
    /// Set once a scan is saved -- the view navigates to review on this
    /// becoming non-nil.
    public var savedScanId: String?

    public init() {}

    public func watchEntitlement() {
        entitlementTask?.cancel()
        entitlementTask = Task { [weak self] in
            do {
                for try await row in try prefsRepository.watchEntitlement() {
                    let state = entitlementState(
                        tier: row?.tier,
                        premiumTrialStartDate: row?.premiumTrialStartDate,
                        compTier: row?.compTier,
                        compUntil: row?.compUntil,
                        nowMillis: Int64((Date().timeIntervalSince1970 * 1000).rounded()),
                        monthlyQuotaTotal: row?.monthlyQuotaTotal,
                        monthlyQuotaUsed: row?.monthlyQuotaUsed,
                        purchasedQuotaRemaining: row?.purchasedQuotaRemaining,
                        additionalPurchasedQuota: row?.additionalPurchasedQuota
                    )
                    self?.canScan = state.isPaid
                    self?.quotaLeft = state.quotaLeft
                }
            } catch {
                // Offline — keep the last known tier.
            }
        }
    }

    public func stopWatching() {
        entitlementTask?.cancel()
        entitlementTask = nil
    }

    public func onCaptureStarted() {
        source = ScanSource.camera
        stage = .preparing
    }

    /// The photo, kept in memory for a possible escalation.
    ///
    /// Called by the view just before OCR.
    public func onImageCaptured(base64: String, mediaType: String) {
        pendingImage = EscalationImage(base64: base64, mediaType: mediaType)
    }

    /// A file was chosen from the picker — an image or a PDF.
    public func onUploadStarted() {
        source = ScanSource.upload
        stage = .preparing
    }

    /// The chosen PDF is encrypted; web keeps the file and asks.
    public func onPasswordRequired() {
        stage = .needsPassword
    }

    public func onReadingStarted() {
        stage = .reading
    }

    /// Called once Vision hands back recognized text. Text-only path -- see
    /// receipt-scan.md scope note #3 (no per-word bounding boxes).
    public func onTextRecognized(_ rawText: String) { ingest(rawText, engine: "tesseract") }

    /// A PDF's text layer, already flattened to lines.
    ///
    /// Web's PDF branch skips OCR entirely and calls `parseReceiptText` on the
    /// joined rows — an emailed bill is the single most accurate input this
    /// feature accepts, which is why it is worth the separate path.
    ///
    /// The engine is left NIL, not set: `parseReceiptText` defaults it to
    /// "pdf_text", which is the value web writes and the value the review
    /// screen and `receipt_scans.engine` already understand. Naming a new one
    /// here would have put a value in the column nothing else recognises.
    public func onPdfText(_ text: String) {
        // Web's own floor: below this there is no text layer worth parsing, and
        // rasterising a scan to OCR it reads worse than photographing the paper
        // — which is what the message says, in web's own words.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < pdfTextFloor {
            stage = .error(S.Receipts.errorsPdfNoText)
            return
        }
        ingest(text, engine: nil)
    }

    private func ingest(_ rawText: String, engine: String?) {
        stage = .understanding
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let draft = parseReceiptText(rawText, ParseOptions(currency: baseCurrencyNow(), today: String(today), engine: engine))
        pendingDraft = draft
        // A PDF has no image to escalate with — web sets `canEscalate: false`
        // on that branch outright, and offering a button that cannot work is
        // worse than not offering one.
        canEscalate = pendingImage != nil && shouldEscalate(draft)
        let rec = reconcile(draft)
        if rec.ok {
            commit(draft)
        } else {
            stage = .mismatch(reason: rec.reason)
        }
    }

    public func onCaptureFailed(_ message: String) {
        stage = .error(message)
    }

    /// "Edit it myself" -- saves the unreconciled draft anyway, exactly
    /// like web's `commit(result.draft, source)` on that button.
    public func editManually() {
        guard let draft = pendingDraft else { return }
        commit(draft)
    }

    public func retake() {
        pendingDraft = nil
        pendingImage = nil
        canEscalate = false
        stage = .idle
    }

    /// "Improve with AI" — send the ORIGINAL photo for a second reading.
    ///
    /// The on-device read is kept and passed along as `rawText`: web does the
    /// same, and it is what lets the review screen show what the phone thought
    /// next to what the model thought.
    ///
    /// A successful escalation commits straight to review, exactly as web's
    /// `improveWithAi` does — the user asked for a better read, not for another
    /// decision.
    public func improveWithAi() {
        guard let image = pendingImage, !aiBusy else { return }
        aiBusy = true
        Task {
            do {
                let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
                let draft = try await receiptsRepository.aiParseReceipt(
                    base64: image.base64,
                    mediaType: image.mediaType,
                    currencyHint: baseCurrencyNow(),
                    today: String(today),
                    rawText: pendingDraft?.rawText
                )
                pendingDraft = draft
                commit(draft)
            } catch let error as AiScanError {
                // The quota case is not hidden behind a generic failure: web
                // swaps the whole note for an upgrade line, and it can only do
                // that because the error says which failure it was.
                stage = .error(error.message)
            } catch {
                stage = .error(error.localizedDescription)
            }
            aiBusy = false
        }
    }

    /// Mirrors `describeMismatch` exactly.
    public func mismatchMessage(_ reason: String) -> String {
        switch reason {
        case "no_lines": return S.Receipts.captureUnclearNoLines
        case "missing_total": return S.Receipts.captureUnclearNoTotal
        default: return S.Receipts.captureUnclearMismatch
        }
    }

    private func commit(_ draft: ReceiptDraft) {
        Task {
            do {
                let s = subtotals(draft.lines)
                let id = try await receiptsRepository.saveScan(SaveScanInput(
                    source: source,
                    engine: draft.engine,
                    merchant: draft.merchant,
                    occurredAt: draft.occurredAt,
                    currency: draft.currency,
                    subtotal: s.items,
                    tax: s.tax,
                    serviceCharge: s.serviceCharge,
                    tip: s.tip,
                    discount: s.discount,
                    total: draft.total,
                    confidence: Int64(draft.confidence),
                    // Web caps the stored dump: a long grocery bill's OCR
                    // output is not worth syncing in full, and it is only ever
                    // used for re-parsing and debugging.
                    rawText: draft.rawText.map { String($0.prefix(rawTextCap)) },
                    parsedJson: ReceiptDraftJson.encode(draft)
                ))
                savedScanId = id
            } catch {
                stage = .error(error.localizedDescription)
            }
        }
    }
}

/// Web's `raw_text: draft.rawText.slice(0, 8000)`.
private let rawTextCap = 8000

/// Below this many characters, a PDF has no text layer worth parsing.
///
/// Web's own floor. It could rasterise and OCR the page instead, but a photo of
/// the paper beats a photo of a scan, so it says so rather than trying.
private let pdfTextFloor = 20

/// The photo, base64-encoded, ready for the edge function.
///
/// A tiny type rather than two loose fields because the two must travel
/// together: sending the bytes with the wrong media type is a silent misread,
/// not an error.
private struct EscalationImage {
    let base64: String
    let mediaType: String
}
