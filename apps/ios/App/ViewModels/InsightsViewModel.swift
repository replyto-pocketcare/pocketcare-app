import Foundation
import Observation
import Factory
import Domain
import Data


private let utcCal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
private func ymd(_ d: Date) -> String {
    let c = utcCal.dateComponents([.year, .month, .day], from: d)
    return "\(c.year!)-\(String(format: "%02d", c.month!))-\(String(format: "%02d", c.day!))"
}
private func ymOf(_ d: Date) -> String {
    let c = utcCal.dateComponents([.year, .month], from: d)
    return "\(c.year!)-\(String(format: "%02d", c.month!))"
}
private func addDays(_ d: Date, _ n: Int) -> Date { utcCal.date(byAdding: .day, value: n, to: d)! }
private func addMonths(_ d: Date, _ n: Int) -> Date { utcCal.date(byAdding: .month, value: n, to: d)! }
private func daysInMonth(_ d: Date) -> Int { utcCal.range(of: .day, in: .month, for: d)!.count }
private func startOfMonth(_ d: Date) -> Date { utcCal.date(from: utcCal.dateComponents([.year, .month], from: d))! }
private func dayOfMonth(_ d: Date) -> Int { utcCal.component(.day, from: d) }
private func weekdayIndex(_ d: Date) -> Int { utcCal.component(.weekday, from: d) - 1 } // 0=Sun..6=Sat

/// Real port of apps/web/src/insights/useInsightStack.ts + src/insights/
/// generators.ts (task #28), replacing an entirely fake predecessor
/// (InsightsView/InsightsViewModel hardcoded a nonexistent "StreamTV"
/// subscription and a made-up "dining" keyword heuristic, yet were the one
/// LIVE Insights screen on iOS -- wired into ContentView.swift, unlike
/// Android's dead-code stub). See docs/mobile/screen-specs/insights.md for
/// the full source-verified spec this was built from, and Android's
/// InsightsViewModel.kt (same session) for the mirrored implementation.
///
/// Uses the established "N parallel Tasks writing into cached `latest*`
/// vars + a shared rebuild()" pattern (GoalsViewModel.swift precedent,
/// 2026-08-06) rather than Kotlin's combine() -- Swift's AsyncSequence has
/// no combineLatest equivalent. 12 live db.watch() streams + one one-shot
/// `rates()` call (re-fetched on every rebuild -- exchange rates change
/// daily, not per-keystroke, matching web's own non-reactive `useRates()`
/// closure).
@Observable
@MainActor
public final class InsightsViewModel {
    @ObservationIgnored @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored @Injected(\.budgetRepository) private var budgetRepository
    @ObservationIgnored @Injected(\.goalsRepository) private var goalsRepository
    @ObservationIgnored @Injected(\.investmentsRepository) private var investmentsRepository
    @ObservationIgnored @Injected(\.prefsRepository) private var prefsRepository
    @ObservationIgnored @Injected(\.authRepository) private var authRepository
    @ObservationIgnored @Injected(\.subscriptionsRepository) private var subscriptionsRepository

    public var cards: [InsightCard] = []
    public var isPaidUser: Bool = false
    public var entitlementLoaded: Bool = false
    public var activeIndex: Int = 0

    private var tasks: [Task<Void, Never>] = []
    private var latestTxns: [TransactionRow] = []
    private var latestCats: [CategoryRow] = []
    private var latestLabelMap: [String: [String]] = [:]
    private var latestBudgets: [BudgetLike] = []
    private var latestBudgetCats: [(budgetId: String, categoryId: String)] = []
    private var latestGoals: [Goal] = []
    private var latestAllocs: [GoalAllocation] = []
    private var latestSubs: [SubscriptionRow] = []
    private var latestHoldings: [Holding] = []
    private var latestDividends: [DividendRow] = []
    private var latestQuotes: [QuoteRow] = []
    private var latestEntitlement: EntitlementRow?

    public init() {
        start()
    }

    public func setActiveIndex(_ i: Int) {
        activeIndex = max(0, min(i, max(0, cards.count - 1)))
    }

    /// Idempotent -- safe to call from every `.onAppear`. Guarded by
    /// `tasks.isEmpty` so all streams are always started/stopped together.
    ///
    /// `makeStream` closures take `self` as an explicit parameter rather
    /// than capturing it, so they carry no strong reference to the
    /// ViewModel at closure-creation time -- only `Task { [weak self] in
    /// guard let self ... }` holds a (weak, then locally-strong-for-that-
    /// iteration) reference, matching GoalsViewModel.swift's established
    /// retain-cycle-safe shape despite the extra indirection needed to
    /// de-duplicate 12 near-identical watch loops.
    public func start() {
        guard tasks.isEmpty else { return }
        // A placeholder so the `tasks.isEmpty` guard above blocks re-entry
        // immediately, even while userId resolution (below) is still async.
        let bootstrap = Task { [weak self] in
            guard let self else { return }
            guard let userId = await self.resolveUserId() else { return }
            self.startWatching(userId: userId)
        }
        tasks = [bootstrap]
    }

    private func startWatching(userId: String) {
        // `makeStream` is `async throws` (not just `throws`) specifically so
        // the goals/holdings/dividends/quotes closures below can `await`
        // into GoalsRepository/InvestmentsRepository -- both are Swift
        // `actor` types (unlike BudgetRepository/LedgerRepository/etc,
        // which are plain `@unchecked Sendable` classes), so even their
        // synchronous, non-throwing-async methods require a suspension
        // point to call from here. The non-actor repositories' calls below
        // stay plain `try $0....` -- a sync throwing call needs no `await`
        // just because it's inside an `async` closure.
        func watch<T>(_ label: String, _ makeStream: @escaping (InsightsViewModel) async throws -> AsyncThrowingStream<T, Error>, _ onValue: @escaping (InsightsViewModel, T) -> Void) -> Task<Void, Never> {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let stream = try await makeStream(self)
                    for try await v in stream {
                        onValue(self, v)
                        await self.rebuild()
                    }
                } catch {
                    print("Insights: failed to watch \(label): \(error)")
                }
            }
        }

        tasks += [
            watch("transactions", { try $0.ledgerRepository.watchAllTransactions() }, { $0.latestTxns = $1 }),
            watch("categories", { try $0.ledgerRepository.watchCategories() }, { $0.latestCats = $1 }),
            watch("labelNames", { try $0.ledgerRepository.watchTransactionLabelNames() }, { $0.latestLabelMap = $1 }),
            watch("budgets", { try $0.budgetRepository.watchBudgets() }, { $0.latestBudgets = $1 }),
            watch("budgetCategories", { try $0.budgetRepository.watchBudgetCategories() }, { $0.latestBudgetCats = $1 }),
            watch("goals", { try await $0.goalsRepository.watchGoals(userId: userId) }, { $0.latestGoals = $1 }),
            watch("allocations", { try await $0.goalsRepository.watchAllocations(userId: userId) }, { $0.latestAllocs = $1 }),
            watch("subscriptions", { try $0.subscriptionsRepository.watchActive() }, { $0.latestSubs = $1 }),
            watch("holdings", { try await $0.investmentsRepository.watchHoldings(userId: userId) }, { $0.latestHoldings = $1 }),
            watch("dividends", { try await $0.investmentsRepository.watchDividends() }, { $0.latestDividends = $1 }),
            watch("quotes", { try await $0.investmentsRepository.watchQuotes() }, { $0.latestQuotes = $1 }),
            watch("entitlement", { try $0.prefsRepository.watchEntitlement() }, { $0.latestEntitlement = $1; $0.entitlementLoaded = true }),
        ]
    }

    /// See GoalsViewModel.swift's identical helper -- `??`'s RHS is an
    /// `@autoclosure`, so `currentUserId ?? (try? await ensureUser())` is
    /// invalid Swift; use an explicit if/else instead.
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }

    public func cancel() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func rebuild() async {
        let ent = latestEntitlement
        isPaidUser = Domain.isPaid(tier: ent?.tier, premiumTrialStartDate: ent?.premiumTrialStartDate, compTier: ent?.compTier, compUntil: ent?.compUntil, now: Date())

        let rates = (try? await ledgerRepository.rates()) ?? { _, _ in 1.0 }
        let ctx = buildGenContext(rates: rates)
        cards = composeStack(ctx)
        if activeIndex >= cards.count { activeIndex = max(0, cards.count - 1) }
    }

    // swiftlint:disable:next function_body_length
    private func buildGenContext(rates: @escaping RateLookup) -> GenContext {
        let now = utcCal.startOfDay(for: Date())
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let thisM = ymOf(now)
        let txns = latestTxns

        // ---- 14-day continuous daily series ----
        var dayIncome: [String: Int64] = [:]; var dayExpense: [String: Int64] = [:]
        for t in txns where t.type == "income" || t.type == "expense" {
            let day = String(t.occurredAt.prefix(10))
            if t.type == "income" { dayIncome[day, default: 0] += t.amount } else { dayExpense[day, default: 0] += t.amount }
        }
        var days: [DayAgg] = []
        for i in stride(from: 13, through: 0, by: -1) {
            let d = ymd(addDays(now, -i))
            days.append(DayAgg(d, dayIncome[d] ?? 0, dayExpense[d] ?? 0))
        }

        // ---- 8-month continuous series ----
        var monthIncome: [String: Int64] = [:]; var monthExpense: [String: Int64] = [:]
        for t in txns where t.type == "income" || t.type == "expense" {
            let ym = String(t.occurredAt.prefix(7))
            if t.type == "income" { monthIncome[ym, default: 0] += t.amount } else { monthExpense[ym, default: 0] += t.amount }
        }
        var months: [MonthAgg] = []
        for i in stride(from: 7, through: 0, by: -1) {
            let ym = ymOf(addMonths(now, -i))
            months.append(MonthAgg(ym, monthIncome[ym] ?? 0, monthExpense[ym] ?? 0))
        }

        // ---- this month's category/label expense ----
        var catNameById: [String: String] = [:]
        for c in latestCats { catNameById[c.id] = c.name }
        let thisMonthExpenseTxns = txns.filter { $0.type == "expense" && String($0.occurredAt.prefix(7)) == thisM }
        var catExpenseById: [String: Int64] = [:]
        var catExpenseByName: [String: Int64] = [:]
        for t in thisMonthExpenseTxns {
            if let cid = t.categoryId { catExpenseById[cid, default: 0] += t.amount }
            let name = t.categoryId.flatMap { catNameById[$0] } ?? S.Receipts.reviewNoCategory
            catExpenseByName[name, default: 0] += t.amount
        }
        let cats = catExpenseByName.map { CatAgg($0.key, $0.value) }.sorted { $0.expense > $1.expense }
        let totalMonthExpenseAll = thisMonthExpenseTxns.reduce(0) { $0 + $1.amount }

        var labelExpense: [String: Int64] = [:]
        for t in thisMonthExpenseTxns {
            guard let names = latestLabelMap[t.id] else { continue }
            for n in names { labelExpense[n, default: 0] += t.amount }
        }
        let labels = Array(labelExpense.map { CatAgg($0.key, $0.value) }.sorted { $0.expense > $1.expense }.prefix(8))

        // ---- budgets (simplified monthly spend vs limit) ----
        var budgetCatsByBudget: [String: [String]] = [:]
        for pair in latestBudgetCats { budgetCatsByBudget[pair.budgetId, default: []].append(pair.categoryId) }
        let budgets = latestBudgets.filter { $0.period.isEmpty || $0.period == "monthly" }.map { b -> BudgetAgg in
            let scoped = budgetCatsByBudget[b.id] ?? []
            let spent = scoped.isEmpty ? totalMonthExpenseAll : scoped.reduce(0) { $0 + (catExpenseById[$1] ?? 0) }
            let name = (b.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Budget"
            return BudgetAgg(name, b.limitAmount, spent)
        }

        // ---- streak + last-7-day counts ----
        var daySet: Set<String> = []
        var countByDay: [String: Int] = [:]
        let streakCutoff = addDays(now, -30)
        for t in txns {
            let day = String(t.occurredAt.prefix(10))
            guard let dDate = dateFromYmd(day), dDate >= streakCutoff else { continue }
            daySet.insert(day); countByDay[day, default: 0] += 1
        }
        var streak = 0
        var cur = daySet.contains(ymd(now)) ? now : addDays(now, -1)
        while daySet.contains(ymd(cur)) { streak += 1; cur = addDays(cur, -1) }
        var txnDays7: [TxnDayCount] = []
        for i in stride(from: 6, through: 0, by: -1) {
            let d = ymd(addDays(now, -i))
            txnDays7.append(TxnDayCount(d, countByDay[d] ?? 0))
        }

        // ---- expense-by-day map (70d) for weekday / pace / no-spend / avg ----
        var expDay: [String: Int64] = [:]
        let expCutoff = addDays(now, -70)
        for t in txns where t.type == "expense" {
            let day = String(t.occurredAt.prefix(10))
            guard let dDate = dateFromYmd(day), dDate >= expCutoff else { continue }
            expDay[day, default: 0] += t.amount
        }

        // weekday averages, last 60 days
        var wdSum = [Double](repeating: 0, count: 7); var wdCnt = [Int](repeating: 0, count: 7)
        for i in 0..<60 {
            let d = addDays(now, -i)
            let wd = weekdayIndex(d)
            wdSum[wd] += Double(expDay[ymd(d)] ?? 0); wdCnt[wd] += 1
        }
        let wdLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let weekday: [SeriesPoint] = (0..<7).map { i in
            SeriesPoint(wdLabels[i], wdCnt[i] > 0 ? ((wdSum[i] / Double(wdCnt[i])).rounded() / 100.0) : 0)
        }
        let weekdayTop = weekday.max(by: { $0.value < $1.value })?.label ?? wdLabels[0]

        // month pace / no-spend / avg
        let dom = dayOfMonth(now)
        let dim = daysInMonth(now)
        let lastMonthStart = startOfMonth(addMonths(now, -1))
        let lastYm = ymOf(lastMonthStart)
        let daysInLastMonth = daysInMonth(lastMonthStart)
        var thisSoFar: Double = 0; var spendDays = 0; var cumulative: [SeriesPoint] = []
        for dd in 1...max(dom, 1) where dd <= dom {
            let k = "\(thisM)-\(String(format: "%02d", dd))"
            let v = Double(expDay[k] ?? 0); thisSoFar += v; if v > 0 { spendDays += 1 }
            cumulative.append(SeriesPoint(String(dd), thisSoFar / 100.0))
        }
        var lastSameSoFar: Double = 0; var lastFull: Double = 0
        for dd in 1...max(daysInLastMonth, 1) where dd <= daysInLastMonth {
            let k = "\(lastYm)-\(String(format: "%02d", dd))"
            let v = Double(expDay[k] ?? 0); lastFull += v; if dd <= dom { lastSameSoFar += v }
        }
        let pace = PaceAgg(thisSoFar: thisSoFar, lastSameSoFar: lastSameSoFar, lastFull: lastFull, dayOfMonth: dom, daysInMonth: dim, cumulative: cumulative)
        let noSpend = NoSpendAgg(noSpendDays: max(0, dom - spendDays), daysElapsed: dom, spendDays: spendDays)
        let avgDaily = AvgDailyAgg(thisAvg: dom > 0 ? thisSoFar / Double(dom) : 0, lastAvg: daysInLastMonth > 0 ? lastFull / Double(daysInLastMonth) : 0)

        // ---- top expenses (this month) ----
        let topExpenses = thisMonthExpenseTxns.sorted { $0.amount > $1.amount }.prefix(6)
            .map { TopExpense(($0.description ?? $0.note ?? S.Translation.transactionExpense).trimmingCharacters(in: .whitespacesAndNewlines), $0.amount) }

        // ---- subscriptions (monthly-normalised) ----
        func norm(_ amt: Int64, _ cycle: String?) -> Int64 {
            switch cycle { case "yearly": return amt / 12; case "weekly": return (amt * 52) / 12; case "quarterly": return amt / 3; default: return amt }
        }
        let subs = latestSubs.map { s -> SubAgg in
            let name = (s.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? S.Cashflow.subscription
            return SubAgg(name, norm(s.amount, s.billingCycle))
        }
        let subsTotal = subs.reduce(0) { $0 + $1.monthly }

        // ---- goals ----
        var savedByGoal: [String: Int64] = [:]
        for a in latestAllocs { savedByGoal[a.goalId, default: 0] += a.amountBlocked }
        let goals = latestGoals.map { g -> GoalAgg in
            let name = g.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return GoalAgg(name.isEmpty ? "Goal" : name, g.targetAmount, savedByGoal[g.id] ?? 0, g.isEmergencyFund)
        }

        // ---- category spike (this month vs prior 3 months average, per category) ----
        let fourMonthsAgo = addMonths(now, -4)
        var priorByCatYm: [String: [String: Int64]] = [:] // name -> ym -> total
        for t in txns where t.type == "expense" {
            let day = String(t.occurredAt.prefix(10))
            guard let dDate = dateFromYmd(day), dDate >= fourMonthsAgo else { continue }
            let name = t.categoryId.flatMap { catNameById[$0] } ?? S.Receipts.reviewNoCategory
            let ym = String(t.occurredAt.prefix(7))
            priorByCatYm[name, default: [:]][ym, default: 0] += t.amount
        }
        var catSpike: CatSpike?
        for (name, byYm) in priorByCatYm {
            let thisMonthTotal = byYm[thisM] ?? 0
            let prior = byYm.filter { $0.key != thisM }.values
            if thisMonthTotal <= 0 || prior.isEmpty { continue }
            let avgPrior = Double(prior.reduce(0, +)) / Double(prior.count)
            if avgPrior <= 0 || Double(thisMonthTotal) < avgPrior * 1.3 || thisMonthTotal < 5000 { continue }
            let ratio = Double(thisMonthTotal) / avgPrior
            if catSpike == nil || ratio > (catSpike!.thisMonth / catSpike!.avgPrior) {
                catSpike = CatSpike(name: name, thisMonth: Double(thisMonthTotal), avgPrior: avgPrior)
            }
        }

        // ---- investments: dividends + projection ----
        var dividends: DividendAgg?
        var projection: ProjectionAgg?
        if !latestHoldings.isEmpty {
            let lite = latestHoldings.map { HoldingLite(symbol: $0.symbol, exchange: $0.exchange, quantity: $0.quantity, currency: $0.currency) }
            let divRows = latestDividends.map { DivRow(symbol: $0.symbol, exchange: $0.exchange, exDate: $0.exDate, payDate: $0.payDate, amount: $0.amount, currency: $0.currency) }
            let events = computeDividendEvents(lite, divRows, rates, baseCurrencyNow())
            let summary = dividendSummary(events)
            let buckets = bucketize(events, .month).map { SeriesPoint($0.label, Double($0.value) / 100.0) }
            dividends = DividendAgg(holdings: latestHoldings.count, trailing12: summary.trailing12, upcoming12: summary.upcoming12, total: summary.total, buckets: buckets)

            func qKey(_ s: String, _ e: String?) -> String { "\(s.uppercased())|\((e ?? "").uppercased())" }
            var bySymEx: [String: QuoteRow] = [:]; var bySym: [String: QuoteRow] = [:]
            for q in latestQuotes { bySymEx[qKey(q.symbol, q.exchange)] = q; if bySym[q.symbol.uppercased()] == nil { bySym[q.symbol.uppercased()] = q } }
            var currentValue: Double = 0
            for h in latestHoldings {
                let q = bySymEx[qKey(h.symbol, h.exchange)] ?? bySym[h.symbol.uppercased()]
                let perShare = q.map { Double($0.price) } ?? Double(h.avgCost ?? 0)
                let ccy = q?.currency ?? h.currency
                let rate = ccy == baseCurrencyNow() ? 1.0 : rates(ccy, baseCurrencyNow())
                currentValue += perShare * h.quantity * rate
            }
            let projGrowthPct = 7; let projYears = 15
            let yieldRate = currentValue > 0 ? Double(summary.trailing12 > 0 ? summary.trailing12 : summary.upcoming12) / currentValue : 0
            let mGrowth = pow(1 + Double(projGrowthPct) / 100.0, 1.0 / 12.0) - 1
            var value = currentValue
            // Math.round(minorValue)/100 (matches web exactly -- round to the
            // nearest minor unit first, THEN convert to major, preserving
            // 2-decimal precision; rounding the major value directly would
            // instead round to whole rupees and lose precision).
            var series: [SeriesPoint] = [SeriesPoint("Now", currentValue.rounded() / 100.0)]
            for m in 1...(projYears * 12) {
                value *= (1 + mGrowth)
                value += (value * yieldRate) / 12
                if m % 12 == 0 && (m / 12) % 3 == 0 { series.append(SeriesPoint("\(m / 12)y", value.rounded() / 100.0)) }
            }
            projection = ProjectionAgg(holdings: latestHoldings.count, currentValue: currentValue, endValue: value, contributed: currentValue, years: projYears, growthPct: projGrowthPct, series: series)
        }

        // ---- mindfulness input transactions ----
        let mindfulnessCutoff = addDays(now, -30)
        let mindfulnessTxns: [TransactionForInsight] = txns
            .filter { t in
                guard t.type == "expense" else { return false }
                if t.intent != nil { return true }
                guard let d = dateFromYmd(String(t.occurredAt.prefix(10))) else { return false }
                return d >= mindfulnessCutoff
            }
            .map { TransactionForInsight(id: $0.id, amount: $0.amount, currency: $0.currency, occurredAt: $0.occurredAt, intent: $0.intent, categoryId: $0.categoryId) }

        return GenContext(
            currency: baseCurrencyNow(), now: now, nowIso: nowIso, fmt: formatMoneyINR,
            days: days, months: months, cats: cats, labels: labels, budgets: budgets,
            streak: streak, txnDays7: txnDays7, topExpenses: Array(topExpenses),
            weekday: weekday, weekdayTop: weekdayTop, subs: subs, subsTotal: subsTotal,
            goals: goals, pace: pace, noSpend: noSpend, avgDaily: avgDaily, catSpike: catSpike,
            dividends: dividends, projection: projection, mindfulnessTxns: mindfulnessTxns
        )
    }
}

/// A fresh NumberFormatter per call, not cached -- matches this codebase's
/// established non-Sendable-Foundation-formatter rule (see AUDIT_HISTORY.md's
/// TransactionsViewModel.swift/DashboardView.swift entry). A free function
/// (not a method) so it captures no `self`/actor isolation at all, safe to
/// hand to GenContext.fmt's plain `@Sendable` closure type as-is.
/// Insight cards are amounts on screen like any other, so they go through the
/// one masking formatter. This stays a free function with no actor isolation so
/// it can still be handed to GenContext.fmt's `@Sendable` closure type —
/// `formatMoney` is deliberately non-isolated for exactly this reason.
private func formatMoneyINR(_ minor: Int64) -> String {
    formatMoney(minor, baseCurrencyNow())
}

private func dateFromYmd(_ s: String) -> Date? {
    guard s.count == 10 else { return nil }
    let parts = s.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    return utcCal.date(from: DateComponents(year: y, month: m, day: d))
}
