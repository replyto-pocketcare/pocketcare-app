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
    case error(String)
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
    private var pendingDraft: ReceiptDraft?

    public var stage: CaptureStage = .idle
    /// Set once a scan is saved -- the view navigates to review on this
    /// becoming non-nil.
    public var savedScanId: String?

    public init() {}

    public func onCaptureStarted() {
        stage = .preparing
    }

    public func onReadingStarted() {
        stage = .reading
    }

    /// Called once Vision hands back recognized text. Text-only path -- see
    /// receipt-scan.md scope note #3 (no per-word bounding boxes).
    public func onTextRecognized(_ rawText: String) {
        stage = .understanding
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let draft = parseReceiptText(rawText, ParseOptions(currency: "INR", today: String(today), engine: "tesseract"))
        pendingDraft = draft
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
        stage = .idle
    }

    /// Mirrors `describeMismatch` exactly.
    public func mismatchMessage(_ reason: String) -> String {
        switch reason {
        case "no_lines": return "We couldn't find any items on this receipt."
        case "missing_total": return "We read the items but couldn't find the total."
        default: return "The items we read don't add up to the printed total."
        }
    }

    private func commit(_ draft: ReceiptDraft) {
        Task {
            do {
                let s = subtotals(draft.lines)
                let id = try await receiptsRepository.saveScan(SaveScanInput(
                    source: "camera",
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
                    rawText: draft.rawText,
                    parsedJson: ReceiptDraftJson.encode(draft)
                ))
                savedScanId = id
            } catch {
                stage = .error(error.localizedDescription)
            }
        }
    }
}
