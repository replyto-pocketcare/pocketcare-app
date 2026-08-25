import Foundation
import Observation
import Factory
import Domain
import Data

/// Ported from apps/web/app/budgets/page.tsx per
/// docs/mobile/screen-specs/budgets.md. Was list-read-only with a hardcoded
/// `categories = ["All"]` placeholder before this pass (2026-08-06) --
/// BudgetRepository now has real create/update/delete/scope methods
/// (see BudgetRepository.swift), so this ViewModel reads real category/label
/// names via LedgerRepository.watchCategories()/watchLabels() (same pattern
/// TransactionsViewModel already established) instead of faking them.
///
/// Fixed 2026-08-06 (list staleness bug): `budgets` used to be populated by
/// a one-shot `reload()` called from `.onAppear { viewModel.start() }`.
/// Add/Edit Budget are `.sheet(...)` presentations -- SwiftUI does not
/// reliably fire `.onDisappear`/`.onAppear` on the presenting view across a
/// sheet's presentation/dismissal, so `start()` (and its `reload()`) often
/// never ran again after the sheet closed, leaving a newly created/edited
/// budget invisible until the whole screen was torn down and recreated some
/// other way. Now `budgets` is driven by BudgetRepository.watchBudgets()
/// (real db.watch()) -- per-budget spend/scope (spentThisPeriod/
/// categoryIds/labelNames) is still a one-shot read per row, recomputed on
/// every `budgets`-table change (covers create/edit/delete; a new
/// transaction alone won't retrigger this without a `budgets` row also
/// changing -- pre-existing scope, unrelated to this fix).
@Observable
@MainActor
public final class BudgetsViewModel {
    @ObservationIgnored
    @Injected(\.budgetRepository) private var budgetRepository
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    public enum ProgressColor: Sendable { case positive, warning, negative }

    public struct BudgetUiModel: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let timeframeText: String
        public let scopeLabel: String
        public let spentFormatted: String
        public let remainingOrOverText: String
        public let progress: Double
        public let progressColor: ProgressColor
        // Edit-form prefill -- raw, unformatted.
        public let rawName: String
        public let limitMajor: String
        public let currency: String
        public let period: String
        public let thresholdPct: Int
        public let alertTimeLocal: String
        public let isCustomDated: Bool
        public let startDate: String?
        public let endDate: String?
        public let categoryIds: [String]
        public let labelNames: [String]
    }

    public struct CategoryOption: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
    }

    public var budgets: [BudgetUiModel] = []
    /// Expense-kind categories only -- matches spec's "Categories (optional):
    /// multi-select from expense-kind categories."
    public var expenseCategories: [CategoryOption] = []
    public var labels: [LabelRow] = []
    public var errorMessage: String?

    private var tasks: [Task<Void, Never>] = []

    public init() {}

    public func start() {
        cancel()
        let catTask = Task {
            do {
                for try await rows in try ledgerRepository.watchCategories() {
                    self.expenseCategories = rows.filter { $0.kind == "expense" }.map { CategoryOption(id: $0.id, name: $0.name) }
                }
            } catch {
                print("Error watching categories: \(error)")
            }
        }
        let labelTask = Task {
            do {
                for try await rows in try ledgerRepository.watchLabels() {
                    self.labels = rows
                }
            } catch {
                print("Error watching labels: \(error)")
            }
        }
        let budgetsTask = Task {
            do {
                for try await list in try budgetRepository.watchBudgets() {
                    await rebuild(list)
                }
            } catch {
                print("Failed to watch budgets: \(error)")
                self.errorMessage = "Couldn't load budgets."
            }
        }
        tasks = [catTask, labelTask, budgetsTask]
    }

    public func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// Recomputes the list's UI rows (spend/scope/progress) whenever
    /// BudgetRepository's live `budgets` watch emits -- see the type doc
    /// comment.
    private func rebuild(_ list: [BudgetLike]) async {
        do {
            let today = todayYmd()
            var uis: [BudgetUiModel] = []
            for b in list {
                let spent = try await budgetRepository.spentThisPeriod(budget: b, asOf: today)
                let limit = money(b.limitAmount, b.currency)
                let progress = try budgetProgress(limit, spent, Double(b.thresholdPct))
                let catIds = try await budgetRepository.categoryIds(budgetId: b.id)
                let labelNames = try await budgetRepository.labelNames(budgetId: b.id)
                let catNames = catIds.compactMap { id in self.expenseCategories.first { $0.id == id }?.name }
                let scopeLabel = (catNames + labelNames).isEmpty ? S.Budgets.allSpending : (catNames + labelNames).joined(separator: ", ")
                let win = periodWindow(period: b.period, startDate: b.startDate, endDate: b.endDate)
                let isCustom = b.startDate != nil && b.endDate != nil
                let timeframeText = isCustom ? win.label : "\(periodLabel(b.period)) · \(win.label)"

                let color: ProgressColor = progress.overLimit ? .negative : (progress.atOrOverThreshold ? .warning : .positive)
                let remainingOrOver: String
                if progress.overLimit {
                    let over = money(spent.amount - limit.amount, b.currency)
                    remainingOrOver = "Over by \(formatMoney(over))"
                } else {
                    remainingOrOver = "\(formatMoney(progress.remaining)) left"
                }

                uis.append(BudgetUiModel(
                    id: b.id,
                    title: b.name?.isEmpty == false ? b.name! : scopeLabel,
                    timeframeText: timeframeText,
                    scopeLabel: scopeLabel,
                    spentFormatted: "Spent \(formatMoney(spent))",
                    remainingOrOverText: remainingOrOver,
                    progress: progress.pct.isFinite ? progress.pct / 100 : 1,
                    progressColor: color,
                    rawName: b.name ?? "",
                    limitMajor: formatMajorPlain(b.limitAmount),
                    currency: b.currency,
                    period: b.period,
                    thresholdPct: b.thresholdPct,
                    alertTimeLocal: utcToLocalTime(b.alertTimeUtc),
                    isCustomDated: isCustom,
                    startDate: b.startDate,
                    endDate: b.endDate,
                    categoryIds: catIds,
                    labelNames: labelNames
                ))
            }
            self.budgets = uis
            self.errorMessage = nil
        } catch {
            print("Failed to load budgets: \(error)")
            self.errorMessage = "Couldn't load budgets."
        }
    }

    /// Matches web's addBudget(): limit must be > 0, custom mode requires
    /// both dates. Returns an error string on validation failure (mirrors
    /// web's inline `err` state) rather than throwing, so the create screen
    /// can show it the same way.
    public func create(
        name: String,
        limitMajorText: String,
        currency: String,
        thresholdPctText: String,
        alertTimeLocal: String,
        categoryIds: [String],
        labelNames: [String],
        isCustomDated: Bool,
        period: String,
        startDate: String?,
        endDate: String?
    ) async -> String? {
        guard let limitMajor = Double(limitMajorText), limitMajor > 0 else {
            return "Enter a limit greater than 0."
        }
        if isCustomDated && (startDate == nil || startDate!.isEmpty || endDate == nil || endDate!.isEmpty) {
            return "Pick both a start and end date."
        }
        guard let userId = await resolveUserId() else {
            return "Couldn't determine the current user."
        }
        do {
            let thresholdPct = min(100, max(1, Int(thresholdPctText) ?? 80))
            let id = try await budgetRepository.create(
                userId: userId,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name,
                period: period,
                startDate: isCustomDated ? startDate : nil,
                endDate: isCustomDated ? endDate : nil,
                limitAmount: fromMajor(limitMajor, currency).amount,
                currency: currency,
                thresholdPct: thresholdPct,
                alertTimeUtc: localToUtcTime(alertTimeLocal)
            )
            try await budgetRepository.writeScope(userId: userId, budgetId: id, categoryIds: categoryIds, labelNames: labelNames)
            return nil
        } catch {
            return "Couldn't create the budget: \(error.localizedDescription)"
        }
    }

    /// Matches web's saveEdit(): name/limit/period/threshold/alert-time only
    /// -- currency and start/end dates are not editable after creation.
    public func update(
        id: String,
        name: String,
        limitMajorText: String,
        currency: String,
        period: String,
        thresholdPctText: String,
        alertTimeLocal: String,
        categoryIds: [String],
        labelNames: [String]
    ) async -> String? {
        guard let userId = await resolveUserId() else {
            return "Couldn't determine the current user."
        }
        do {
            let limitMajor = Double(limitMajorText) ?? 0
            let thresholdPct = min(100, max(1, Int(thresholdPctText) ?? 80))
            try await budgetRepository.update(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name,
                limitAmount: fromMajor(limitMajor, currency).amount,
                period: period,
                thresholdPct: thresholdPct,
                alertTimeUtc: localToUtcTime(alertTimeLocal)
            )
            try await budgetRepository.writeScope(userId: userId, budgetId: id, categoryIds: categoryIds, labelNames: labelNames)
            return nil
        } catch {
            return "Couldn't save changes: \(error.localizedDescription)"
        }
    }

    public func delete(id: String) async {
        do {
            try await budgetRepository.delete(id: id)
        } catch {
            print("Failed to delete budget: \(error)")
        }
    }

    /// `authRepository.currentUserId ?? (try? await authRepository.ensureUser())`
    /// is invalid Swift -- `??`'s right-hand side is an `@autoclosure`, and
    /// composing `await`/`try?` inside it this way doesn't parse (the exact
    /// shape that broke AppDelegate.swift's push-token registration earlier
    /// this session; same fix applied here: an explicit if/else instead).
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId {
            return existing
        }
        return try? await authRepository.ensureUser()
    }

    private func formatMoney(_ m: Money) -> String {
        formatMoneyAware(m)
    }

}

/// Ported from apps/web/src/time.ts's utcToLocalTime/localToUtcTime exactly
/// -- both apply the given "HH:MM" to *today's* date (not a fixed epoch) in
/// the source timezone, then read the clock time back in the target
/// timezone, matching JS's `Date.setUTCHours`/`setHours` +
/// `toTimeString().slice(0,5)` behavior (today's date matters for DST
/// correctness, same reasoning as web's own comment-free but
/// date-anchored implementation).
func utcToLocalTime(_ utcTime: String?, defaultLocal: String = "09:00") -> String {
    guard let utcTime, !utcTime.isEmpty else { return defaultLocal }
    let parts = utcTime.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return defaultLocal }
    var utcCal = Calendar(identifier: .gregorian)
    utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
    var comps = utcCal.dateComponents([.year, .month, .day], from: Date())
    comps.hour = h; comps.minute = m; comps.second = 0
    guard let date = utcCal.date(from: comps) else { return defaultLocal }
    var localCal = Calendar(identifier: .gregorian)
    localCal.timeZone = TimeZone.current
    let localComps = localCal.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", localComps.hour ?? 0, localComps.minute ?? 0)
}

func localToUtcTime(_ localTime: String) -> String {
    guard !localTime.isEmpty else { return "00:00" }
    let parts = localTime.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return "00:00" }
    var localCal = Calendar(identifier: .gregorian)
    localCal.timeZone = TimeZone.current
    var comps = localCal.dateComponents([.year, .month, .day], from: Date())
    comps.hour = h; comps.minute = m; comps.second = 0
    guard let date = localCal.date(from: comps) else { return "00:00" }
    var utcCal = Calendar(identifier: .gregorian)
    utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
    let utcComps = utcCal.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", utcComps.hour ?? 0, utcComps.minute ?? 0)
}

private func periodLabel(_ period: String) -> String {
    switch period {
    case "daily": return S.Budgets.periodDaily
    case "weekly": return S.Budgets.periodWeekly
    case "yearly": return S.Budgets.periodYearly
    default: return S.Budgets.periodMonthly
    }
}

/// The active date window + label for a budget (current period for
/// recurring) -- matches web's page-local periodWindow() exactly (page.tsx
/// re-derives this client-side for display rather than sharing it with the
/// repository's own window math, which this mirrors: a separate,
/// display-only computation, not required to share code with
/// BudgetRepository.spentThisPeriod's query-boundary logic).
private func periodWindow(period: String, startDate: String?, endDate: String?) -> (start: String, end: String, label: String) {
    let dayFmt = DateFormatter()
    dayFmt.dateFormat = "d MMM"

    func fmtDay(_ isoDay: String) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = isoDay.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return isoDay }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        guard let date = cal.date(from: comps) else { return isoDay }
        dayFmt.timeZone = TimeZone(secondsFromGMT: 0)
        return dayFmt.string(from: date)
    }

    if let s = startDate, let e = endDate {
        let sDay = String(s.prefix(10))
        let eDay = String(e.prefix(10))
        return (sDay, eDay, "\(fmtDay(sDay)) \u{2013} \(fmtDay(eDay))")
    }

    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date()
    let todayComps = cal.dateComponents([.year, .month, .day], from: now)
    let isoDayFmt = DateFormatter()
    isoDayFmt.dateFormat = "yyyy-MM-dd"
    isoDayFmt.timeZone = TimeZone(secondsFromGMT: 0)

    var start: Date
    var end: Date
    switch period {
    case "daily":
        start = cal.date(from: todayComps)!
        end = start
    case "weekly":
        let weekday = cal.component(.weekday, from: now) // 1=Sunday...7=Saturday
        let dow = (weekday - 2 + 7) % 7 // 0=Monday...6=Sunday, matches web's (getDay()+6)%7
        start = cal.date(byAdding: .day, value: -dow, to: cal.date(from: todayComps)!)!
        end = cal.date(byAdding: .day, value: 6, to: start)!
    case "yearly":
        start = cal.date(from: DateComponents(year: todayComps.year, month: 1, day: 1))!
        end = cal.date(from: DateComponents(year: todayComps.year, month: 12, day: 31))!
    default: // monthly
        start = cal.date(from: DateComponents(year: todayComps.year, month: todayComps.month, day: 1))!
        let nextMonth = cal.date(byAdding: .month, value: 1, to: start)!
        end = cal.date(byAdding: .day, value: -1, to: nextMonth)!
    }
    let sIso = isoDayFmt.string(from: start)
    let eIso = isoDayFmt.string(from: end)
    return (sIso, eIso, "\(fmtDay(sIso)) \u{2013} \(fmtDay(eIso))")
}
