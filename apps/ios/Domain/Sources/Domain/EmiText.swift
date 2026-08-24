import Foundation

/// The description written on a posted EMI transaction.
///
/// **This string is not cosmetic — it is the cross-device dedupe key.** Loan
/// auto-post decides whether an instalment has already been charged by looking
/// for a transaction with exactly this description on exactly that account
/// (`autoPost.ts`), rather than by a local flag, so that a second device
/// running the same catch-up finds the first device's row and skips it.
///
/// It was previously a string literal built inline in `LoanDetailViewModel` on
/// both platforms, and web builds it in `src/loans/funding.ts`. Three
/// hand-written copies of a value that must match byte-for-byte across devices
/// *and* platforms: the day anyone "improved" the wording in one of them, every
/// device running the other would have started double-posting EMIs, silently,
/// and only on loans linked to an account.
///
/// The separator is an EM DASH (U+2014), matching web. The visually similar
/// "·" used on the credit-cards screen is display-only text and is deliberately
/// NOT this function — reusing it here would change the key.
public func emiDescription(_ emiNo: Int, _ lender: String?) -> String {
    let name = lender?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let name, !name.isEmpty else { return "EMI #\(emiNo)" }
    return "EMI #\(emiNo) — \(name)"
}
