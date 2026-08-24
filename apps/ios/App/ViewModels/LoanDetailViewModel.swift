import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

public enum EmiRowState: Sendable { case paid, autoMarked, due }

public struct EmiRowUiModel: Identifiable, Equatable, Sendable {
    public var id: Int { month }
    public let month: Int
    public let amountFormatted: String
    public let hasAmount: Bool
    /// Minor-unit EMI amount for this row (0 for an unset variable month) --
    /// used to post the mark-paid expense transaction.
    public let emiMinor: Int64
    public let state: EmiRowState
    public let dueFormatted: String
    public let paidOnOrDueFormatted: String
    // fixed-rate only:
    public let principalFormatted: String?
    public let interestFormatted: String?
    public let balanceFormatted: String?
    public let hasInterest: Bool
    // variable-rate only:
    public let rawAmountMajor: String
}

public struct MarkPaidAccountOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let balanceFormatted: String
    public let isCreditCard: Bool
}

public struct LoanDetailUiModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let lender: String
    public let principalFormatted: String
    public let emiFormatted: String
    public let interestRateText: String
    public let emisPaidText: String
    public let nextEmiDueFormatted: String
    public let remainingText: String
    public let isVariable: Bool
    public let hasInterest: Bool
    public let totalInterestFormatted: String?
    public let variablePaidFormatted: String?
    public let progress: Double
    public let hasTenure: Bool
    public let autoMarkPaid: Bool
    public let autoMarkDueDayText: String
    public let rows: [EmiRowUiModel]
    public let emptyScheduleHint: Bool
    // raw fields for edit prefill
    public let rawLender: String
    public let rawPrincipalMajor: String
    public let rawEmiMajor: String
    public let rawInterestRate: String
    public let rawTenure: String
    public let rawStartDate: String
    public let rawDueDay: String
    public let rawRateType: String
    public let rawAlertTimeLocal: String
    public let currency: String
}

/// Loan detail (EMI schedule, mark-paid, auto-mark, edit/delete). Ported
/// from apps/web/app/loans/[id]/page.tsx per docs/mobile/screen-specs/
/// loans.md (task #27/#42). New file -- iOS had no per-loan detail screen
/// at all before this pass, mirroring Android's LoanDetailViewModel.kt
/// field-for-field.
@Observable
@MainActor
public final class LoanDetailViewModel {
    @ObservationIgnored
    @Injected(\.loansRepository) private var loansRepository
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    public var uiModel: LoanDetailUiModel?
    public var markPaidAccounts: [MarkPaidAccountOption] = []
    public var defaultFundingAccountId: String?

    private var latestLoan: Loan?
    private var observeTask: Task<Void, Never>?
    private var loadedId: String?

    /// (Re)subscribes to the given loan id -- safe to call every time the
    /// detail screen appears, including with an unchanged id (a no-op in
    /// that case), matching Android's `select(id)` entry point (Compose's
    /// default `viewModel()` factory takes no constructor args, so this
    /// mirrors that same "parameterless VM + explicit select" shape rather
    /// than introducing per-screen constructor injection here only).
    public func load(id: String) {
        guard loadedId != id else { return }
        loadedId = id
        observeTask?.cancel()
        observeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.loansRepository.watchLoan(id: id)
                for try await loan in stream {
                    self.latestLoan = loan
                    self.defaultFundingAccountId = loan?.fundingAccountId
                    await self.refreshAccounts()
                    self.uiModel = loan.map { self.buildUiModel($0) }
                }
            } catch {
                print("Failed to observe loan \(id): \(error)")
            }
        }
    }

    public func cancel() {
        observeTask?.cancel()
        observeTask = nil
        loadedId = nil
    }

    private func refreshAccounts() async {
        let balances = (try? await ledgerRepository.accountBalances()) ?? []
        markPaidAccounts = balances.map {
            MarkPaidAccountOption(
                id: $0.account.id, name: $0.account.name,
                balanceFormatted: formatMoney($0.balance.amount, $0.account.currency),
                isCreditCard: $0.account.type == "credit_card"
            )
        }
    }

    private func buildUiModel(_ l: Loan) -> LoanDetailUiModel {
        let cur = l.currency.isEmpty ? baseCurrencyNow() : l.currency
        let tenure = l.tenureMonths ?? 0
        let emi = l.emiAmount ?? 0
        let dueDay = l.emiDueDay
        let autoMark = l.autoMarkPaid
        let isVariable = l.rateType == "variable"
        let schedule = (!isVariable && emi > 0) ? amortizationSchedule(l.principal, l.interestRate ?? 0, emi, tenure > 0 ? tenure : 600) : []
        let totalInterest = schedule.reduce(Int64(0)) { $0 + $1.interest }
        let hasInterest = (l.interestRate ?? 0) > 0

        var manual = parseManualPaid(l.emiPayments)
        if manual.isEmpty, let n = l.emisPaid, n > 0 { manual = Array(1...n) }
        let amounts = parseAmounts(l.emiAmounts)

        let knownMax = max(0, (Set(amounts.keys).union(manual)).max() ?? 0)
        let totalEmis = tenure > 0 ? tenure : (isVariable ? knownMax : schedule.count)
        let variableMonths = isVariable ? Array(1...max(totalEmis, knownMax, 1)) : []

        let today = isoToday()
        let effective = effectivePaidEmis(manual: manual, totalEmis: totalEmis, autoMark: autoMark, startIso: l.startDate, dueDay: dueDay, asOfIso: today)
        let manualSet = Set(manual)
        let monthsList = isVariable ? variableMonths : schedule.map { $0.month }
        let nextUnpaid = monthsList.first { !effective.contains($0) }
        let nextEmiDue = nextUnpaid.flatMap { emiDueDate(l.startDate, dueDay, $0) }
        let remaining = totalEmis > 0 ? max(0, totalEmis - effective.count) : nil
        let paidOnMap = parsePaidOnMap(l.emiPayments)
        let variablePaidTotal = variableMonths.filter { effective.contains($0) }.reduce(Int64(0)) { $0 + (amounts[$1] ?? 0) }

        let rows: [EmiRowUiModel]
        if isVariable {
            rows = variableMonths.map { m in
                let paid = effective.contains(m)
                let due = emiDueDate(l.startDate, dueDay, m)
                return EmiRowUiModel(
                    month: m, amountFormatted: amounts[m].map { formatMoney($0, cur) } ?? "—", hasAmount: amounts[m] != nil,
                    emiMinor: amounts[m] ?? 0,
                    state: paid ? (manualSet.contains(m) ? .paid : .autoMarked) : .due,
                    dueFormatted: fmtDateShort(due),
                    paidOnOrDueFormatted: paid ? fmtDateShort(paidOnMap[m] ?? due) : fmtDateShort(due),
                    principalFormatted: nil, interestFormatted: nil, balanceFormatted: nil, hasInterest: false,
                    rawAmountMajor: amounts[m].map { formatMajorPlain($0) } ?? ""
                )
            }
        } else {
            rows = schedule.map { r in
                let paid = effective.contains(r.month)
                let due = emiDueDate(l.startDate, dueDay, r.month)
                return EmiRowUiModel(
                    month: r.month, amountFormatted: formatMoney(r.emi, cur), hasAmount: true,
                    emiMinor: r.emi,
                    state: paid ? (manualSet.contains(r.month) ? .paid : .autoMarked) : .due,
                    dueFormatted: fmtDateShort(due),
                    paidOnOrDueFormatted: paid ? fmtDateShort(paidOnMap[r.month] ?? due) : fmtDateShort(due),
                    principalFormatted: formatMoney(r.principal, cur),
                    interestFormatted: hasInterest ? formatMoney(r.interest, cur) : nil,
                    balanceFormatted: !hasInterest ? formatMoney(r.balance, cur) : nil,
                    hasInterest: hasInterest,
                    rawAmountMajor: ""
                )
            }
        }

        return LoanDetailUiModel(
            id: l.id,
            lender: (l.lender?.isEmpty == false) ? l.lender! : S.Loans.loanFallback,
            principalFormatted: formatMoney(l.principal, cur),
            emiFormatted: isVariable ? S.Loans.varies : (emi > 0 ? formatMoney(emi, cur) : "—"),
            interestRateText: hasInterest ? "\(formatRate(l.interestRate ?? 0))% p.a.\(isVariable ? " (variable)" : "")" : (isVariable ? S.Loans.variable : "—"),
            emisPaidText: tenure > 0 ? "\(effective.count) / \(tenure)" : "\(effective.count)",
            nextEmiDueFormatted: (nextEmiDue != nil && remaining != 0) ? fmtDateLong(nextEmiDue) : "—",
            remainingText: remaining.map { "\($0) EMI\($0 == 1 ? "" : "s") left" } ?? "—",
            isVariable: isVariable,
            hasInterest: hasInterest,
            totalInterestFormatted: (!isVariable && hasInterest) ? formatMoney(totalInterest, cur) : nil,
            variablePaidFormatted: isVariable ? formatMoney(variablePaidTotal, cur) : nil,
            progress: tenure > 0 ? min(1.0, max(0.0, Double(effective.count) / Double(tenure))) : 0,
            hasTenure: tenure > 0,
            autoMarkPaid: autoMark,
            autoMarkDueDayText: dueDayLabel(dueDay: dueDay, startIso: l.startDate),
            rows: rows,
            emptyScheduleHint: !isVariable && schedule.isEmpty,
            rawLender: l.lender ?? "",
            rawPrincipalMajor: formatMajorPlain(l.principal),
            rawEmiMajor: l.emiAmount.map { formatMajorPlain($0) } ?? "",
            rawInterestRate: l.interestRate.map { formatRate($0) } ?? "",
            rawTenure: l.tenureMonths.map { String($0) } ?? "",
            rawStartDate: l.startDate ?? "",
            rawDueDay: l.emiDueDay.map { String($0) } ?? "",
            rawRateType: l.rateType ?? "fixed",
            rawAlertTimeLocal: utcToLocalTime(l.alertTimeUtc),
            currency: cur
        )
    }

    /// Matches web's `setManualPaid(month, paidOn)`.
    public func markPaid(month: Int, paidOn: String, accountId: String?, emiAmountMinor: Int64, currency: String) {
        Task { [weak self] in
            guard let self, let l = self.latestLoan else { return }
            var manual = parsePaidOnMap(l.emiPayments)
            manual[month] = paidOn
            let json = Self.jsonMap(manual)
            try? await self.loansRepository.setManualPaid(id: l.id, emiPaymentsJson: json, emisPaidCount: manual.count)
            if let accountId, emiAmountMinor > 0, let userId = self.authRepository.currentUserId {
                let occurredAt = "\(paidOn)T12:00:00.000Z"
                try? await self.ledgerRepository.createTransaction(
                    userId: userId, accountId: accountId, type: "expense",
                    amount: money(emiAmountMinor, currency), occurredAt: occurredAt,
                    // emiDescription(), not a literal: this string is the
                    // cross-device dedupe key loan auto-post matches on.
                    description: emiDescription(month, l.lender)
                )
                try? await self.loansRepository.setFundingAccountId(id: l.id, accountId: accountId)
            }
        }
    }

    /// Matches web's `setManualPaid(month, null)` (undo).
    public func unmarkPaid(month: Int) {
        Task { [weak self] in
            guard let self, let l = self.latestLoan else { return }
            var manual = parsePaidOnMap(l.emiPayments)
            manual.removeValue(forKey: month)
            try? await self.loansRepository.setManualPaid(id: l.id, emiPaymentsJson: Self.jsonMap(manual), emisPaidCount: manual.count)
        }
    }

    /// Matches web's `setAmount(month, minor)` (variable-rate EMI entry).
    public func setVariableAmount(month: Int, majorText: String, currency: String) {
        Task { [weak self] in
            guard let self, let l = self.latestLoan else { return }
            var amounts = parseAmounts(l.emiAmounts)
            let minor = Double(majorText).map { fromMajor($0, currency).amount }
            if let minor, minor > 0 { amounts[month] = minor } else { amounts.removeValue(forKey: month) }
            try? await self.loansRepository.setEmiAmounts(id: l.id, emiAmountsJson: Self.jsonMap(amounts))
        }
    }

    public func toggleAutoMark() {
        Task { [weak self] in
            guard let self, let l = self.latestLoan else { return }
            try? await self.loansRepository.setAutoMarkPaid(id: l.id, enabled: !l.autoMarkPaid)
        }
    }

    /// Matches web's `EditLoan.save()`.
    public func update(
        lender: String, principalMajorText: String, emiMajorText: String, interestRateText: String,
        tenureText: String, startDate: String, dueDayText: String, rateType: String, alertTimeUtc: String
    ) async -> String? {
        guard let l = latestLoan else { return "Loan not found." }
        let cur = l.currency.isEmpty ? baseCurrencyNow() : l.currency
        do {
            let principalMinor = fromMajor(Double(principalMajorText) ?? 0, cur).amount
            let isVariable = rateType == "variable"
            let rate = Double(interestRateText) ?? 0
            let tenure = Int(tenureText)
            let computedEmi = isVariable ? 0 : emiFromPrincipal(principalMinor, rate, tenure ?? 0)
            let emiToUse: Int64? = isVariable ? nil : (Double(emiMajorText).map { fromMajor($0, cur).amount } ?? (computedEmi > 0 ? computedEmi : nil))
            let dueDay = Int(dueDayText).map { min(31, max(1, $0)) }
            try await loansRepository.update(
                id: l.id,
                input: EditLoanInput(
                    lender: lender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : lender,
                    principal: principalMinor, emiAmount: emiToUse, interestRate: rate, tenureMonths: tenure,
                    startDate: startDate.isEmpty ? nil : startDate, emiDueDay: dueDay, rateType: rateType, alertTimeUtc: alertTimeUtc
                )
            )
            return nil
        } catch {
            return "Couldn't save changes: \(error.localizedDescription)"
        }
    }

    public func delete(onDone: @escaping () -> Void) {
        Task { [weak self] in
            guard let self, let id = self.latestLoan?.id else { return }
            do {
                try await self.loansRepository.delete(id: id)
                onDone()
            } catch {
                print("Failed to delete loan: \(error)")
            }
        }
    }

    private static func jsonMap(_ m: [Int: String]) -> String {
        let entries = m.map { "\"\($0.key)\":\"\(escapeJson($0.value))\"" }.joined(separator: ",")
        return "{\(entries)}"
    }

    private static func jsonMap(_ m: [Int: Int64]) -> String {
        let entries = m.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
        return "{\(entries)}"
    }
}

private func escapeJson(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

private func parsePaidOnMap(_ json: String?) -> [Int: String] {
    guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return [:] }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    var out: [Int: String] = [:]
    for (k, v) in obj {
        if let n = Int(k), let s = v as? String, !s.isEmpty { out[n] = s }
    }
    return out
}

private func parseAmounts(_ json: String?) -> [Int: Int64] {
    guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return [:] }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    var out: [Int: Int64] = [:]
    for (k, v) in obj {
        guard let n = Int(k) else { continue }
        if let num = v as? NSNumber, num.int64Value > 0 { out[n] = num.int64Value }
    }
    return out
}

private func fmtDateShort(_ iso: String?) -> String {
    guard let iso else { return "—" }
    let s = String(iso.prefix(10))
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let parts = s.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return "—" }
    var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d
    guard let date = cal.date(from: comps) else { return "—" }
    let fmt = DateFormatter()
    fmt.dateFormat = "d MMM"
    fmt.timeZone = TimeZone(identifier: "UTC")
    fmt.locale = Locale(identifier: "en_US")
    return fmt.string(from: date)
}

private func fmtDateLong(_ iso: String?) -> String {
    guard let iso else { return "—" }
    let s = String(iso.prefix(10))
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let parts = s.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return "—" }
    var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d
    guard let date = cal.date(from: comps) else { return "—" }
    let fmt = DateFormatter()
    fmt.dateFormat = "d MMM yyyy"
    fmt.timeZone = TimeZone(identifier: "UTC")
    fmt.locale = Locale(identifier: "en_US")
    return fmt.string(from: date)
}

/// 1 -> "1st", 2 -> "2nd", ... day-of-month ordinal -- matches web's ordinal().
private func ordinal(_ n: Int) -> String {
    let v = n % 100
    let suffix: String
    if (11...13).contains(v) { suffix = "th" }
    else if v % 10 == 1 { suffix = "st" }
    else if v % 10 == 2 { suffix = "nd" }
    else if v % 10 == 3 { suffix = "rd" }
    else { suffix = "th" }
    return "\(n)\(suffix)"
}

private func dueDayLabel(dueDay: Int?, startIso: String?) -> String {
    var day = dueDay
    if day == nil, let startIso, startIso.count >= 10 {
        let parts = String(startIso.prefix(10)).split(separator: "-")
        if parts.count == 3, let d = Int(parts[2]) { day = d }
    }
    guard let day else { return "" }
    return "Due on the \(ordinal(day)) each month"
}
