import Foundation
import Domain

/**
 Editable-draft helpers, mirroring `apps/web/src/receipts/draft.ts`.

 These live in the app layer on purpose, exactly as they do on web: they are
 editor conveniences over an immutable parse result, not domain rules, so they
 carry no golden vectors and do not belong in the `Domain` package.

 `ReceiptReviewViewModel` previously inlined this one, which meant the same
 behaviour existed twice in the codebase in two different shapes — Android
 imported it (from a module where it did not exist) while iOS hand-rolled it.
 */

/// Adopt the computed sum as the total.
///
/// The counterpart to `balanceWithLine`: when the user has corrected the lines
/// and it is the PRINTED total that was misread, this trusts the lines instead.
public func adoptComputedTotal(_ draft: ReceiptDraft) -> ReceiptDraft {
    ReceiptDraft(
        merchant: draft.merchant,
        occurredAt: draft.occurredAt,
        currency: draft.currency,
        lines: draft.lines,
        total: reconcile(draft).computed,
        confidence: draft.confidence,
        engine: draft.engine,
        rawText: draft.rawText
    )
}
