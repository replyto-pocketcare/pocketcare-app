import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

/// Base/display currency -- loans are always created in the base currency
/// (matches web: `AddLoan` inserts with `currency: base`, no per-loan
/// currency picker exists), matching Android's LoansViewModel.kt /
/// InvestmentsViewModel.swift's own established simplification.
private let BASE_CURRENCY = "INR"
private let NON_INVESTMENT_TYPES: Set<String> = ["stocks", "mutual_funds", "demat"]

/// Ported from apps/web/app/loans/page.tsx per docs/mobile/screen-specs/
/// loans.md (task #27/#42). Was a broken placeholder before this pass
/// (2026-08-06): non-optional access on now-nullable Loan fields (a real
/// crash risk once LoansRepository.swift was fixed to match web's actually-
/// nullable columns), a `"Loans & Recurring"` title that appears to be
/// invented drift merging with a separate, unbuilt "Recurring" nav item
/// (same class of bug as the earlier-fixed Goals/Cashflow merge -- see
/// LoansView.swift), and a placeholder `"Day \(dueDay)"` next-due string.
/// Rewritten to mirror Android's LoansViewModel.kt field-for-field: grouped
/// list totals, real create(), and driven entirely by
/// LoansRepository.watchLoans() (real db.watch(), not a one-shot list) so
/// this doesn't hit the list-staleness bug fixed for Goals/Budgets this
/// same pass (2026-08-06) -- see AUDIT_HISTORY.md.
@Observable
@MainActor
public final class LoansViewModel {
    @ObservationIgnored
    @Injected(\.loansRepository) private var loansRepository
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    public struct FundingAccountOption: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let isCreditCard: Bool
    }

    public struct LoanUiModel: Identifiable, Equatable, Sendable {
        public let id: String
        public let lender: String
        public let active: Bool
        public let rangeOrRate: String
        public let paidCountText: String
        public let progress: Double // 0...1, or 0 if no tenure
        public let hasTenure: Bool
        public let principalFormatted: String
        public let emiFormatted: String
    }

    public var loans: [LoanUiModel] = []
    public var totalEmiFormatted: String = formatMoney(0, BASE_CURRENCY)
    public var fundingAccounts: [FundingAccountOption] = []

    private var observeTask: Task<Void, Never>?

    public init() {
        start()
    }

    /// Idempotent -- guarded by `observeTask` alone, safe to call from every
    /// `.onAppear`.
    public func start() {
        guard observeTask == nil else { return }
        observeTask = Task { [weak self] in
            guard let self else { return }
            guard let userId = await self.resolveUserId() else { return }
            do {
                let stream = try await self.loansRepository.watchLoans(userId: userId)
                for try await dbLoans in stream {
                    await self.rebuild(dbLoans)
                }
            } catch {
                print("Failed to observe loans: \(error)")
            }
        }
    }

    public func cancel() {
        observeTask?.cancel()
        observeTask = nil
    }

    private func rebuild(_ dbLoans: [Loan]) async {
        let balances = (try? await ledgerRepository.accountBalances()) ?? []
        let rates = (try? await ledgerRepository.rates()) ?? { _, _ in 1.0 }

        fundingAccounts = balances
            .filter { !NON_INVESTMENT_TYPES.contains($0.account.type) }
            .sorted { ($0.account.type == "credit_card" ? 0 : 1) < ($1.account.type == "credit_card" ? 0 : 1) }
            .map { FundingAccountOption(id: $0.account.id, name: $0.account.name, isCreditCard: $0.account.type == "credit_card") }

        let today = isoToday()
        var totalEmiBase: Int64 = 0
        loans = dbLoans.map { l in
            let tenure = l.tenureMonths ?? 0
            let paid = paidCount(l, today)
            let remaining = tenure > 0 ? max(0, tenure - paid) : nil
            let closed = tenure > 0 && remaining == 0
            let range = loanRange(l.startDate, tenure)
            let cur = l.currency.isEmpty ? BASE_CURRENCY : l.currency
            if let emi = l.emiAmount {
                totalEmiBase += cur == BASE_CURRENCY ? emi : ((try? convert(money(emi, cur), to: BASE_CURRENCY, rate: rates(cur, BASE_CURRENCY)).amount) ?? emi)
            }
            return LoanUiModel(
                id: l.id,
                lender: (l.lender?.isEmpty == false) ? l.lender! : "Loan",
                active: !closed,
                rangeOrRate: range ?? (l.interestRate.map { "\(formatRate($0))% p.a." } ?? "—"),
                paidCountText: tenure > 0 ? "\(paid) / \(tenure) paid" : "\(paid) paid",
                progress: tenure > 0 ? min(1.0, max(0.0, Double(paid) / Double(tenure))) : 0,
                hasTenure: tenure > 0,
                principalFormatted: formatMoney(l.principal, cur),
                emiFormatted: l.emiAmount.map { formatMoney($0, cur) } ?? (l.rateType == "variable" ? "Varies" : "—")
            )
        }
        totalEmiFormatted = formatMoney(totalEmiBase, BASE_CURRENCY)
    }

    /// Matches web's `AddLoan.save()`: requires a lender name or a
    /// principal; EMI is caller-supplied (auto-calculated by the screen
    /// for fixed-rate loans via `emiFromPrincipal`, nil for variable).
    public func create(
        lender: String, principalMajorText: String, emiMajorText: String?, interestRateText: String,
        tenureText: String, startDate: String?, dueDayText: String, autoMarkPaid: Bool, rateType: String,
        fundingAccountId: String?, alertTimeUtc: String
    ) async -> String? {
        let trimmedLender = lender.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLender.isEmpty && principalMajorText.isEmpty { return "Enter a lender or a loan amount." }
        guard let userId = await resolveUserId() else { return "Couldn't determine the current user." }
        do {
            let principalMinor = fromMajor(Double(principalMajorText) ?? 0, BASE_CURRENCY).amount
            let dueDay = Int(dueDayText).map { min(31, max(1, $0)) }
            try await loansRepository.create(
                userId: userId,
                input: NewLoanInput(
                    lender: trimmedLender, currency: BASE_CURRENCY, principal: principalMinor,
                    emiAmount: emiMajorText.flatMap { Double($0) }.map { fromMajor($0, BASE_CURRENCY).amount },
                    interestRate: Double(interestRateText) ?? 0, tenureMonths: Int(tenureText),
                    startDate: startDate, emiDueDay: dueDay, autoMarkPaid: autoMarkPaid, rateType: rateType,
                    fundingAccountId: fundingAccountId, alertTimeUtc: alertTimeUtc
                )
            )
            return nil
        } catch {
            return "Couldn't add the loan: \(error.localizedDescription)"
        }
    }

    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }
}

/// Effective paid-EMI count for a loan row (manual marks union auto-marked
/// past-due) -- matches web's page-local `paidCount()` exactly, and
/// Android's LoansViewModel.kt `paidCount()`.
func paidCount(_ l: Loan, _ todayIso: String) -> Int {
    let tenure = l.tenureMonths ?? 0
    var manual = parseManualPaid(l.emiPayments)
    if manual.isEmpty, let n = l.emisPaid, n > 0 { manual = Array(1...n) }
    return effectivePaidEmis(manual: manual, totalEmis: tenure, autoMark: l.autoMarkPaid, startIso: l.startDate, dueDay: l.emiDueDay, asOfIso: todayIso).count
}

/// Parses the `emi_payments` JSON map `{ "1": "2026-01-05", "2": "" }` into
/// the list of EMI numbers with a non-blank paid-on date.
func parseManualPaid(_ json: String?) -> [Int] {
    guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return [] }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    return obj.compactMap { key, value -> Int? in
        let str = (value as? String) ?? ""
        guard !str.isEmpty, let n = Int(key) else { return nil }
        return n
    }
}

/// "Mar '26 - Nov '26" from a start date + tenure in months -- matches
/// web's `loanRange()` / Android's `loanRange()`.
func loanRange(_ startIso: String?, _ tenure: Int) -> String? {
    guard let startIso, !startIso.isEmpty, tenure > 0 else { return nil }
    let s = String(startIso.prefix(10))
    let parts = s.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d
    guard let start = cal.date(from: comps), let end = cal.date(byAdding: .month, value: tenure, to: start) else { return nil }
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM ''yy"
    fmt.timeZone = TimeZone(identifier: "UTC")
    fmt.locale = Locale(identifier: "en_US")
    return "\(fmt.string(from: start)) \u{2013} \(fmt.string(from: end))"
}

func formatRate(_ r: Double) -> String {
    r == r.rounded() ? String(Int64(r)) : String(r)
}

// formatMoney moved to App/Components/MoneyFormat.swift — one formatter,
// hide-amounts aware, fraction digits from minorUnits(currency).

