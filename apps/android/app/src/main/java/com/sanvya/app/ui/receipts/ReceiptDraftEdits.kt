package com.sanvya.app.ui.receipts

import com.sanvya.app.domain.receipts.ReceiptDraft
import com.sanvya.app.domain.receipts.reconcile

/**
 * Editable-draft helpers, mirroring `apps/web/src/receipts/draft.ts`.
 *
 * These live in the app layer on purpose, exactly as they do on web: they are
 * editor conveniences over an immutable parse result, not domain rules, so they
 * carry no golden vectors and do not belong in `:domain`. `ReceiptReviewViewModel`
 * previously imported `adoptComputedTotal` from `com.sanvya.app.domain.receipts`,
 * where it had never existed — the Android app has not compiled since.
 */

/**
 * Adopt the computed sum as the total.
 *
 * The counterpart to `balanceWithLine`: when the user has corrected the lines
 * and it is the PRINTED total that was misread, this trusts the lines instead.
 */
fun adoptComputedTotal(draft: ReceiptDraft): ReceiptDraft =
    draft.copy(total = reconcile(draft).computed)
