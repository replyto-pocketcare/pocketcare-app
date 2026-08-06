import Foundation

// Ported from apps/web/src/insights/{types,generators}.ts (86 + 422 lines)
// for the Insights feed (task #28). Mirrors Android's domain/insights/
// Insights.kt added the same session. Pure -- no I/O, no locale
// dependencies (currency formatting is injected via GenContext.fmt,
// matching this codebase's established "domain never formats currency,
// screens do" convention -- see Money.swift, which has no format() either).
// Every threshold/priority/cap below is load-bearing, copied from
// generators.ts, not invented.

// ---- shared visual/card contract (types.ts) ----

public struct SeriesPoint: Sendable {
    public let label: String
    public let value: Double
    public let color: String?
    public init(_ label: String, _ value: Double, _ color: String? = nil) { self.label = label; self.value = value; self.color = color }
}

public enum InsightTheme: Sendable { case positive, warning, neutral, celebratory }

// NOTE: Swift enum associated values cannot carry default parameter
// values (unlike function params) -- every case constructor below must be
// called with all arguments explicit. All call sites in this file already
// do so.
public enum VisualSpec: Sendable {
    case bars(series: [SeriesPoint], unit: String?, horizontal: Bool)
    case area(series: [SeriesPoint])
    case donut(series: [SeriesPoint], centerLabel: String?, centerSub: String?)
    case gauge(value: Double, max: Double, warnAt: Double?, dangerAt: Double?, unit: String?, centerLabel: String?)
    case progress(value: Double, target: Double?, centerLabel: String?)
}

public struct InsightMetric: Sendable {
    public let display: String
    public let raw: Double?
    public let deltaPct: Int?
    public let direction: String?
    public init(display: String, raw: Double? = nil, deltaPct: Int? = nil, direction: String? = nil) {
        self.display = display; self.raw = raw; self.deltaPct = deltaPct; self.direction = direction
    }
}

public struct InsightCta: Sendable { public let label: String; public let target: String }

public struct InsightCard: Sendable, Identifiable {
    public let id: String
    public let type: String
    public let theme: InsightTheme
    public let generatedAt: String
    public let periodStart: String
    public let periodEnd: String
    public let priority: Int
    public let headline: String
    public let subhead: String?
    public let bullets: [String]
    public let metric: InsightMetric?
    public let visual: VisualSpec?
    public let cta: InsightCta?
    public let cadenceKey: String
    public let cadenceFrequency: String
}

/// Fixed multi-series palette -- theme-invariant, matches web's literal hex
/// array (not a CSS var, so it doesn't flip with dark mode either).
public let INSIGHT_PALETTE = ["#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#7c7264", "#5f6647"]

// ---- aggregate inputs (generators.ts's GenContext) ----

public struct DayAgg: Sendable { public let day: String; public let income: Int64; public let expense: Int64
    public init(_ day: String, _ income: Int64, _ expense: Int64) { self.day = day; self.income = income; self.expense = expense } }
public struct MonthAgg: Sendable { public let ym: String; public let income: Int64; public let expense: Int64
    public init(_ ym: String, _ income: Int64, _ expense: Int64) { self.ym = ym; self.income = income; self.expense = expense } }
public struct CatAgg: Sendable { public let name: String; public let expense: Int64
    public init(_ name: String, _ expense: Int64) { self.name = name; self.expense = expense } }
public struct BudgetAgg: Sendable { public let name: String; public let limit: Int64; public let spent: Int64
    public init(_ name: String, _ limit: Int64, _ spent: Int64) { self.name = name; self.limit = limit; self.spent = spent } }
public struct TopExpense: Sendable { public let label: String; public let amount: Int64
    public init(_ label: String, _ amount: Int64) { self.label = label; self.amount = amount } }
public struct SubAgg: Sendable { public let name: String; public let monthly: Int64
    public init(_ name: String, _ monthly: Int64) { self.name = name; self.monthly = monthly } }
public struct GoalAgg: Sendable { public let name: String; public let target: Int64; public let saved: Int64; public let emergency: Bool
    public init(_ name: String, _ target: Int64, _ saved: Int64, _ emergency: Bool) { self.name = name; self.target = target; self.saved = saved; self.emergency = emergency } }
public struct TxnDayCount: Sendable { public let day: String; public let count: Int
    public init(_ day: String, _ count: Int) { self.day = day; self.count = count } }
public struct PaceAgg: Sendable {
    public let thisSoFar: Double; public let lastSameSoFar: Double; public let lastFull: Double
    public let dayOfMonth: Int; public let daysInMonth: Int; public let cumulative: [SeriesPoint]
    public init(thisSoFar: Double, lastSameSoFar: Double, lastFull: Double, dayOfMonth: Int, daysInMonth: Int, cumulative: [SeriesPoint]) {
        self.thisSoFar = thisSoFar; self.lastSameSoFar = lastSameSoFar; self.lastFull = lastFull
        self.dayOfMonth = dayOfMonth; self.daysInMonth = daysInMonth; self.cumulative = cumulative
    }
}
public struct NoSpendAgg: Sendable { public let noSpendDays: Int; public let daysElapsed: Int; public let spendDays: Int
    public init(noSpendDays: Int, daysElapsed: Int, spendDays: Int) { self.noSpendDays = noSpendDays; self.daysElapsed = daysElapsed; self.spendDays = spendDays } }
public struct AvgDailyAgg: Sendable { public let thisAvg: Double; public let lastAvg: Double
    public init(thisAvg: Double, lastAvg: Double) { self.thisAvg = thisAvg; self.lastAvg = lastAvg } }
public struct CatSpike: Sendable { public let name: String; public let thisMonth: Double; public let avgPrior: Double
    public init(name: String, thisMonth: Double, avgPrior: Double) { self.name = name; self.thisMonth = thisMonth; self.avgPrior = avgPrior } }
public struct DividendAgg: Sendable {
    public let holdings: Int; public let trailing12: Int64; public let upcoming12: Int64; public let total: Int64; public let buckets: [SeriesPoint]
    public init(holdings: Int, trailing12: Int64, upcoming12: Int64, total: Int64, buckets: [SeriesPoint]) {
        self.holdings = holdings; self.trailing12 = trailing12; self.upcoming12 = upcoming12; self.total = total; self.buckets = buckets
    }
}
public struct ProjectionAgg: Sendable {
    public let holdings: Int; public let currentValue: Double; public let endValue: Double; public let contributed: Double
    public let years: Int; public let growthPct: Int; public let series: [SeriesPoint]
    public init(holdings: Int, currentValue: Double, endValue: Double, contributed: Double, years: Int, growthPct: Int, series: [SeriesPoint]) {
        self.holdings = holdings; self.currentValue = currentValue; self.endValue = endValue; self.contributed = contributed
        self.years = years; self.growthPct = growthPct; self.series = series
    }
}

public struct GenContext: Sendable {
    public let currency: String
    public let now: Date // normalized to start-of-day UTC
    public let nowIso: String
    /// Formats minor units in `currency` -- injected so this file stays
    /// locale-free; the ViewModel passes its own formatMoney().
    public let fmt: @Sendable (Int64) -> String
    public let days: [DayAgg]
    public let months: [MonthAgg]
    public let cats: [CatAgg]
    public let labels: [CatAgg]
    public let budgets: [BudgetAgg]
    public let streak: Int
    public let txnDays7: [TxnDayCount]
    public let topExpenses: [TopExpense]
    public let weekday: [SeriesPoint]
    public let weekdayTop: String
    public let subs: [SubAgg]
    public let subsTotal: Int64
    public let goals: [GoalAgg]
    public let pace: PaceAgg
    public let noSpend: NoSpendAgg
    public let avgDaily: AvgDailyAgg
    public let catSpike: CatSpike?
    public let dividends: DividendAgg?
    public let projection: ProjectionAgg?
    public let mindfulnessTxns: [TransactionForInsight]?

    public init(currency: String, now: Date, nowIso: String, fmt: @escaping @Sendable (Int64) -> String,
                days: [DayAgg], months: [MonthAgg], cats: [CatAgg], labels: [CatAgg], budgets: [BudgetAgg],
                streak: Int, txnDays7: [TxnDayCount], topExpenses: [TopExpense], weekday: [SeriesPoint], weekdayTop: String,
                subs: [SubAgg], subsTotal: Int64, goals: [GoalAgg], pace: PaceAgg, noSpend: NoSpendAgg, avgDaily: AvgDailyAgg,
                catSpike: CatSpike?, dividends: DividendAgg? = nil, projection: ProjectionAgg? = nil, mindfulnessTxns: [TransactionForInsight]? = nil) {
        self.currency = currency; self.now = now; self.nowIso = nowIso; self.fmt = fmt
        self.days = days; self.months = months; self.cats = cats; self.labels = labels; self.budgets = budgets
        self.streak = streak; self.txnDays7 = txnDays7; self.topExpenses = topExpenses; self.weekday = weekday; self.weekdayTop = weekdayTop
        self.subs = subs; self.subsTotal = subsTotal; self.goals = goals; self.pace = pace; self.noSpend = noSpend; self.avgDaily = avgDaily
        self.catSpike = catSpike; self.dividends = dividends; self.projection = projection; self.mindfulnessTxns = mindfulnessTxns
    }
}

// ---- helpers ----

private let utcCalendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

private func fmtL(_ ctx: GenContext, _ minor: Double) -> String { ctx.fmt(Int64(minor.rounded())) }
private func major(_ minor: Int64) -> Double { Double(minor) / 100.0 }
private func majorD(_ minor: Double) -> Double { minor / 100.0 }
private func pctOf(_ a: Double, _ b: Double) -> Int { b == 0 ? (a > 0 ? 100 : 0) : Int(((a - b) / abs(b) * 100).rounded()) }
private let WD_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
private func weekdayLabel(_ iso: String) -> String {
    let ymd = String(iso.prefix(10))
    guard let d = utcCalendar.date(from: DateComponents(year: Int(ymd.prefix(4)), month: Int(ymd.dropFirst(5).prefix(2)), day: Int(ymd.suffix(2)))) else { return "" }
    return WD_LABELS[utcCalendar.component(.weekday, from: d) - 1] // Calendar.weekday: 1=Sunday..7=Saturday
}
private let MON_LABELS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
private func monShort(_ ym: String) -> String { MON_LABELS[(Int(ym.suffix(2)) ?? 1) - 1] }
private func trunc(_ s: String, _ n: Int = 22) -> String { s.count > n ? String(s.prefix(n - 1)) + "…" : s }
private func ymOf(_ d: Date) -> String {
    let c = utcCalendar.dateComponents([.year, .month], from: d)
    return "\(c.year!)-\(String(format: "%02d", c.month!))"
}
private func yearOf(_ d: Date) -> Int { utcCalendar.component(.year, from: d) }
private func monthOf(_ d: Date) -> Int { utcCalendar.component(.month, from: d) } // 1-based

// ---- generators (each: GenContext -> [InsightCard]; order matches generators.ts) ----

public func genWeeklySummary(_ ctx: GenContext) -> [InsightCard] {
    let last7 = Array(ctx.days.suffix(7))
    if last7.count < 3 { return [] }
    let prev7 = Array(ctx.days.dropLast(7).suffix(7))
    let inc = last7.reduce(0) { $0 + $1.income }; let exp = last7.reduce(0) { $0 + $1.expense }; let net = inc - exp
    let prevNet = prev7.reduce(0) { $0 + $1.income } - prev7.reduce(0) { $0 + $1.expense }
    let series = last7.map { SeriesPoint(weekdayLabel($0.day), major($0.income - $0.expense)) }
    return [InsightCard(
        id: "weekly:\(last7.first!.day)", type: "weekly_summary", theme: net >= 0 ? .positive : .warning,
        generatedAt: ctx.nowIso, periodStart: last7.first!.day, periodEnd: last7.last!.day, priority: 92,
        headline: net >= 0 ? "You saved \(ctx.fmt(net)) this week" : "You spent \(ctx.fmt(-net)) more than you earned",
        subhead: "Last 7 days",
        bullets: [
            "Money in: \(ctx.fmt(inc))", "Money out: \(ctx.fmt(exp))",
            prev7.isEmpty ? "Your first week of tracking" : "\(net >= prevNet ? "Up" : "Down") \(ctx.fmt(abs(net - prevNet))) vs the week before",
        ],
        metric: InsightMetric(display: ctx.fmt(net), raw: major(net), deltaPct: (!prev7.isEmpty && prevNet != 0) ? pctOf(Double(net), Double(prevNet)) : nil, direction: net >= prevNet ? "up" : "down"),
        visual: .area(series: series), cta: nil, cadenceKey: "weekly_summary", cadenceFrequency: "weekly"
    )]
}

public func genBudgetWarnings(_ ctx: GenContext) -> [InsightCard] {
    ctx.budgets
        .filter { $0.limit > 0 && Double($0.spent) / Double($0.limit) >= 0.8 }
        .sorted { Double($0.spent) / Double($0.limit) > Double($1.spent) / Double($1.limit) }
        .prefix(2)
        .map { b in
            let ratio = Double(b.spent) / Double(b.limit); let over = b.spent > b.limit
            return InsightCard(
                id: "budget:\(b.name):\(yearOf(ctx.now))-\(monthOf(ctx.now) - 1)", type: "budget_warning", theme: .warning,
                generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: over ? 100 : 96,
                headline: over ? "\(b.name) budget is over by \(ctx.fmt(b.spent - b.limit))" : "\(b.name) budget is \(Int((ratio * 100).rounded()))% used",
                subhead: over ? "Over budget" : "Almost there",
                bullets: ["Spent \(ctx.fmt(b.spent)) of \(ctx.fmt(b.limit))", over ? "Consider easing off this category" : "\(ctx.fmt(b.limit - b.spent)) left this period"],
                metric: InsightMetric(display: "\(Int((ratio * 100).rounded()))%", raw: (ratio * 100).rounded()),
                visual: .gauge(value: major(b.spent), max: major(b.limit), warnAt: major(b.limit) * 0.8, dangerAt: major(b.limit), unit: nil, centerLabel: "\(Int((ratio * 100).rounded()))%"),
                cta: InsightCta(label: "Review budgets", target: "/budgets"), cadenceKey: "budget_warning:\(b.name)", cadenceFrequency: "daily"
            )
        }
}

public func genSavingsAchievement(_ ctx: GenContext) -> [InsightCard] {
    guard let cur = ctx.months.last else { return [] }
    let net = cur.income - cur.expense
    if net <= 0 || cur.income <= 0 { return [] }
    let rate = Int(((Double(net) / Double(cur.income)) * 100).rounded())
    let prev = ctx.months.count > 1 ? ctx.months[ctx.months.count - 2] : nil
    let prevNet = prev.map { $0.income - $0.expense } ?? 0
    return [InsightCard(
        id: "savings:\(cur.ym)", type: "savings_achievement", theme: .celebratory,
        generatedAt: ctx.nowIso, periodStart: "\(cur.ym)-01", periodEnd: "\(cur.ym)-01", priority: 84,
        headline: "You saved \(ctx.fmt(net)) in \(monShort(cur.ym))", subhead: "That's a \(rate)% savings rate",
        bullets: ["Kept \(rate)% of what you earned", (prev != nil && net > prevNet) ? "Beat last month by \(ctx.fmt(net - prevNet))" : "Every bit compounds"],
        metric: InsightMetric(display: "\(rate)%", raw: Double(rate), direction: "up"),
        visual: .progress(value: major(net), target: major(cur.income), centerLabel: "\(rate)%"),
        cta: nil, cadenceKey: "savings_achievement", cadenceFrequency: "monthly"
    )]
}

public func genSpendingTrend(_ ctx: GenContext) -> [InsightCard] {
    let m = Array(ctx.months.suffix(6)); if m.count < 4 { return [] }
    let half = m.count / 2
    func avg(_ arr: [MonthAgg]) -> Double { arr.isEmpty ? 0 : Double(arr.reduce(0) { $0 + $1.expense }) / Double(arr.count) }
    let recent = avg(Array(m.suffix(m.count - half))); let older = avg(Array(m.prefix(half)))
    let down = recent <= older; let delta = pctOf(recent, older)
    let series = m.map { SeriesPoint(monShort($0.ym), major($0.expense)) }
    return [InsightCard(
        id: "trend:\(m.last!.ym)", type: "spending_trend", theme: down ? .positive : .warning,
        generatedAt: ctx.nowIso, periodStart: "\(m.first!.ym)-01", periodEnd: "\(m.last!.ym)-01", priority: 72,
        headline: down ? "Your spending is trending down" : "Your spending is creeping up", subhead: "Over the last \(m.count) months",
        bullets: ["Recent months average \(fmtL(ctx, recent))", "\(down ? "Down" : "Up") \(abs(delta))% vs earlier months"],
        metric: InsightMetric(display: "\(delta > 0 ? "+" : "")\(delta)%", raw: Double(delta), direction: down ? "down" : "up"),
        visual: .area(series: series), cta: nil, cadenceKey: "spending_trend", cadenceFrequency: "weekly"
    )]
}

public func genCategoryBreakdown(_ ctx: GenContext) -> [InsightCard] {
    let top = Array(ctx.cats.filter { $0.expense > 0 }.prefix(6)); if top.count < 2 { return [] }
    let total = top.reduce(0) { $0 + $1.expense }; let lead = top[0]
    return [InsightCard(
        id: "cats:\(yearOf(ctx.now))-\(monthOf(ctx.now) - 1)", type: "category_breakdown", theme: .neutral,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 62,
        headline: "Where your money went", subhead: "This month, by category",
        bullets: ["\(lead.name) led at \(ctx.fmt(lead.expense))", "\(Int((Double(lead.expense) / Double(total) * 100).rounded()))% of your tracked spending"],
        metric: InsightMetric(display: ctx.fmt(total), raw: major(total)),
        visual: .donut(series: top.map { SeriesPoint($0.name, major($0.expense)) }, centerLabel: ctx.fmt(total), centerSub: "this month"),
        cta: nil, cadenceKey: "category_breakdown", cadenceFrequency: "weekly"
    )]
}

public func genStreak(_ ctx: GenContext) -> [InsightCard] {
    if ctx.streak < 3 { return [] }
    return [InsightCard(
        id: "streak:\(String(ctx.nowIso.prefix(10)))", type: "streak", theme: .celebratory,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 55,
        headline: "\(ctx.streak)-day logging streak", subhead: "Consistency pays off",
        bullets: ["You've logged transactions \(ctx.streak) days running", "The best budgets are the ones you actually keep"],
        metric: InsightMetric(display: "\(ctx.streak)", raw: Double(ctx.streak), direction: "up"),
        visual: .bars(series: ctx.txnDays7.map { SeriesPoint(weekdayLabel($0.day), Double($0.count)) }, unit: "txns", horizontal: false),
        cta: nil, cadenceKey: "streak", cadenceFrequency: "daily"
    )]
}

public func genBiggestExpense(_ ctx: GenContext) -> [InsightCard] {
    let top = Array(ctx.topExpenses.filter { $0.amount > 0 }.prefix(5)); if top.isEmpty { return [] }
    let lead = top[0]
    return [InsightCard(
        id: "bigexp:\(yearOf(ctx.now))-\(monthOf(ctx.now) - 1)", type: "biggest_expense", theme: .neutral,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 68,
        headline: "Your biggest expense was \(ctx.fmt(lead.amount))", subhead: lead.label.isEmpty ? "This month" : lead.label,
        bullets: top.prefix(3).map { "\($0.label): \(ctx.fmt($0.amount))" },
        metric: InsightMetric(display: ctx.fmt(lead.amount), raw: major(lead.amount)),
        visual: .bars(series: top.map { SeriesPoint(trunc($0.label, 16), major($0.amount)) }, unit: nil, horizontal: true),
        cta: nil, cadenceKey: "biggest_expense", cadenceFrequency: "weekly"
    )]
}

public func genWeekdayPattern(_ ctx: GenContext) -> [InsightCard] {
    let nonzero = ctx.weekday.filter { $0.value > 0 }; if nonzero.count < 3 { return [] }
    guard let top = ctx.weekday.max(by: { $0.value < $1.value }) else { return [] }
    return [InsightCard(
        id: "weekday:\(yearOf(ctx.now))-\(monthOf(ctx.now))", type: "weekday_pattern", theme: .neutral,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 50,
        headline: "\(ctx.weekdayTop) is your priciest day", subhead: "Average spend by weekday · last 60 days",
        bullets: ["You spend most on \(ctx.weekdayTop)s", "Around \(fmtL(ctx, top.value * 100)) on an average \(ctx.weekdayTop)"],
        metric: nil,
        visual: .bars(series: ctx.weekday, unit: nil, horizontal: false), cta: nil, cadenceKey: "weekday_pattern", cadenceFrequency: "weekly"
    )]
}

public func genLabelBreakdown(_ ctx: GenContext) -> [InsightCard] {
    let top = Array(ctx.labels.filter { $0.expense > 0 }.prefix(6)); if top.count < 2 { return [] }
    let total = top.reduce(0) { $0 + $1.expense }; let lead = top[0]
    return [InsightCard(
        id: "labels:\(yearOf(ctx.now))-\(monthOf(ctx.now) - 1)", type: "label_breakdown", theme: .neutral,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 54,
        headline: "Spending by label", subhead: "This month, across your tags",
        bullets: ["\(lead.name) topped your labels at \(ctx.fmt(lead.expense))", "\(top.count) labels tracked this month"],
        metric: InsightMetric(display: ctx.fmt(total), raw: major(total)),
        visual: .donut(series: top.map { SeriesPoint($0.name, major($0.expense)) }, centerLabel: ctx.fmt(total), centerSub: "labelled"),
        cta: nil, cadenceKey: "label_breakdown", cadenceFrequency: "weekly"
    )]
}

public func genSubscriptions(_ ctx: GenContext) -> [InsightCard] {
    let subs = ctx.subs.filter { $0.monthly > 0 }; if subs.isEmpty { return [] }
    let top = Array(subs.sorted { $0.monthly > $1.monthly }.prefix(6))
    return [InsightCard(
        id: "subs:\(yearOf(ctx.now))-\(monthOf(ctx.now))", type: "subscriptions_load", theme: .neutral,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 64,
        headline: "\(ctx.fmt(ctx.subsTotal))/mo on subscriptions", subhead: "\(subs.count) active subscription\(subs.count == 1 ? "" : "s")",
        bullets: ["Biggest: \(top[0].name) at \(ctx.fmt(top[0].monthly))/mo", "That's \(ctx.fmt(ctx.subsTotal * 12)) a year"],
        metric: InsightMetric(display: ctx.fmt(ctx.subsTotal), raw: major(ctx.subsTotal)),
        visual: .donut(series: top.map { SeriesPoint($0.name, major($0.monthly)) }, centerLabel: ctx.fmt(ctx.subsTotal), centerSub: "per month"),
        cta: InsightCta(label: "Manage subscriptions", target: "/subscriptions"), cadenceKey: "subscriptions_load", cadenceFrequency: "monthly"
    )]
}

public func genMonthPace(_ ctx: GenContext) -> [InsightCard] {
    let p = ctx.pace; if p.dayOfMonth < 3 || p.lastSameSoFar <= 0 { return [] }
    let projected = (p.thisSoFar / Double(p.dayOfMonth)) * Double(p.daysInMonth)
    let faster = p.thisSoFar > p.lastSameSoFar
    return [InsightCard(
        id: "pace:\(yearOf(ctx.now))-\(monthOf(ctx.now))", type: "month_pace", theme: faster ? .warning : .positive,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 74,
        headline: faster ? "You're spending faster than last month" : "You're pacing under last month",
        subhead: "Day \(p.dayOfMonth) of \(p.daysInMonth)",
        bullets: [
            "Spent \(fmtL(ctx, p.thisSoFar)) so far (was \(fmtL(ctx, p.lastSameSoFar)) by now last month)",
            "On track for about \(fmtL(ctx, projected)) vs \(fmtL(ctx, p.lastFull)) last month",
        ],
        metric: InsightMetric(display: fmtL(ctx, projected), raw: majorD(projected), direction: faster ? "up" : "down"),
        visual: .area(series: p.cumulative), cta: nil, cadenceKey: "month_pace", cadenceFrequency: "daily"
    )]
}

public func genNoSpendDays(_ ctx: GenContext) -> [InsightCard] {
    let n = ctx.noSpend; if n.daysElapsed < 5 { return [] }
    return [InsightCard(
        id: "nospend:\(yearOf(ctx.now))-\(monthOf(ctx.now))", type: "no_spend_days", theme: .positive,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 48,
        headline: "\(n.noSpendDays) no-spend day\(n.noSpendDays == 1 ? "" : "s") this month", subhead: "Out of \(n.daysElapsed) days so far",
        bullets: ["You didn't spend on \(n.noSpendDays) of \(n.daysElapsed) days", "No-spend days are an easy savings win"],
        metric: InsightMetric(display: "\(n.noSpendDays)", raw: Double(n.noSpendDays)),
        visual: .donut(series: [SeriesPoint("No-spend", Double(n.noSpendDays), "positive"), SeriesPoint("Spent", Double(n.spendDays), "border")], centerLabel: "\(n.noSpendDays)", centerSub: "no-spend days"),
        cta: nil, cadenceKey: "no_spend_days", cadenceFrequency: "weekly"
    )]
}

public func genGoalProgress(_ ctx: GenContext) -> [InsightCard] {
    let eligible = ctx.goals.filter { $0.target > 0 }; if eligible.isEmpty { return [] }
    let unfinished = eligible.filter { $0.saved < $0.target }.sorted { Double($0.saved) / Double($0.target) > Double($1.saved) / Double($1.target) }
    guard let g = unfinished.first ?? eligible.first(where: { $0.emergency }) ?? eligible.first else { return [] }
    let ratio = min(1.0, Double(g.saved) / Double(g.target)); let doneP = Int((ratio * 100).rounded())
    return [InsightCard(
        id: "goal:\(g.name)", type: "goal_progress", theme: doneP >= 100 ? .celebratory : .positive,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 60,
        headline: doneP >= 100 ? "\(g.name) is fully funded!" : "\(g.name) is \(doneP)% funded", subhead: "Goal progress",
        bullets: ["\(ctx.fmt(g.saved)) of \(ctx.fmt(g.target)) set aside", doneP >= 100 ? "Time to set your next goal" : "\(ctx.fmt(g.target - g.saved)) to go"],
        metric: InsightMetric(display: "\(doneP)%", raw: Double(doneP), direction: "up"),
        visual: .gauge(value: major(g.saved), max: major(g.target), warnAt: nil, dangerAt: nil, unit: nil, centerLabel: "\(doneP)%"),
        cta: InsightCta(label: "View goals", target: "/goals"), cadenceKey: "goal_progress:\(g.name)", cadenceFrequency: "weekly"
    )]
}

public func genCategorySpike(_ ctx: GenContext) -> [InsightCard] {
    guard let s = ctx.catSpike else { return [] }
    let up = pctOf(s.thisMonth, s.avgPrior)
    return [InsightCard(
        id: "spike:\(s.name):\(yearOf(ctx.now))-\(monthOf(ctx.now))", type: "category_spike", theme: .warning,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 78,
        headline: "\(s.name) spending jumped \(up)%", subhead: "vs your recent average",
        bullets: ["\(fmtL(ctx, s.thisMonth)) this month", "Usually around \(fmtL(ctx, s.avgPrior))"],
        metric: InsightMetric(display: "+\(up)%", raw: Double(up), direction: "up"),
        visual: .bars(series: [SeriesPoint("Usual", majorD(s.avgPrior), "forest"), SeriesPoint("This mo", majorD(s.thisMonth), "warning")], unit: nil, horizontal: false),
        cta: InsightCta(label: "See transactions", target: "/transactions"), cadenceKey: "category_spike", cadenceFrequency: "weekly"
    )]
}

public func genAvgDaily(_ ctx: GenContext) -> [InsightCard] {
    let p = ctx.pace; if p.dayOfMonth < 3 { return [] }
    let thisAvg = ctx.avgDaily.thisAvg; let lastAvg = ctx.avgDaily.lastAvg
    if thisAvg <= 0 && lastAvg <= 0 { return [] }
    let lower = thisAvg <= lastAvg
    return [InsightCard(
        id: "avgday:\(yearOf(ctx.now))-\(monthOf(ctx.now))", type: "avg_daily_spend", theme: lower ? .positive : .neutral,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 52,
        headline: "You're averaging \(fmtL(ctx, thisAvg))/day",
        subhead: lastAvg > 0 ? "\(lower ? "Down from" : "Up from") \(fmtL(ctx, lastAvg))/day last month" : "So far this month",
        bullets: ["\(fmtL(ctx, thisAvg)) per day this month", lastAvg > 0 ? "\(fmtL(ctx, lastAvg)) per day last month" : "Keep it steady"],
        metric: InsightMetric(display: fmtL(ctx, thisAvg), raw: majorD(thisAvg), direction: lower ? "down" : "up"),
        visual: .bars(series: [SeriesPoint("Last mo", majorD(lastAvg), "forest"), SeriesPoint("This mo", majorD(thisAvg), "accent")], unit: nil, horizontal: false),
        cta: nil, cadenceKey: "avg_daily_spend", cadenceFrequency: "weekly"
    )]
}

public func genDividends(_ ctx: GenContext) -> [InsightCard] {
    guard let d = ctx.dividends, d.holdings > 0, d.total > 0 else { return [] }
    let series = Array(d.buckets.filter { $0.value != 0 }.suffix(8)); if series.isEmpty { return [] }
    let headlineAmt = d.trailing12 > 0 ? d.trailing12 : d.total
    return [InsightCard(
        id: "dividends:\(yearOf(ctx.now))-\(monthOf(ctx.now))", type: "dividend_income", theme: .positive,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 66,
        headline: d.trailing12 > 0 ? "\(ctx.fmt(d.trailing12)) in dividends this year" : "\(ctx.fmt(d.total)) in dividends so far",
        subhead: "From \(d.holdings) holding\(d.holdings == 1 ? "" : "s")",
        bullets: ["Last 12 months: \(ctx.fmt(d.trailing12))", d.upcoming12 > 0 ? "Next 12 months (est.): \(ctx.fmt(d.upcoming12))" : "All-time: \(ctx.fmt(d.total))"],
        metric: InsightMetric(display: ctx.fmt(headlineAmt), raw: major(headlineAmt)),
        visual: .bars(series: series, unit: nil, horizontal: false),
        cta: InsightCta(label: "See dividends", target: "/investments"), cadenceKey: "dividend_income", cadenceFrequency: "monthly"
    )]
}

public func genProjection(_ ctx: GenContext) -> [InsightCard] {
    guard let p = ctx.projection, p.holdings > 0, p.currentValue > 0 else { return [] }
    let growthPortion = max(0, p.endValue - p.contributed)
    return [InsightCard(
        id: "projection:\(yearOf(ctx.now))-\(monthOf(ctx.now))", type: "portfolio_projection", theme: .neutral,
        generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: 59,
        headline: "Your portfolio could reach \(fmtL(ctx, p.endValue))", subhead: "In \(p.years) years at \(p.growthPct)% a year",
        bullets: ["\(fmtL(ctx, p.currentValue)) invested today", "About \(fmtL(ctx, growthPortion)) of that would be growth", "A projection on default assumptions, not a forecast"],
        metric: InsightMetric(display: fmtL(ctx, p.endValue), raw: majorD(p.endValue), direction: "up"),
        visual: .area(series: p.series),
        cta: InsightCta(label: "Adjust assumptions", target: "/investments"), cadenceKey: "portfolio_projection", cadenceFrequency: "monthly"
    )]
}

public func genMindfulness(_ ctx: GenContext) -> [InsightCard] {
    guard let txns = ctx.mindfulnessTxns else { return [] }
    let t1 = computeTier1Insights(txns); let t2 = computeTier2Insights(txns)
    return (t1 + t2).map { i in
        InsightCard(
            id: "mindfulness:\(i.id):\(String(ctx.nowIso.prefix(10)))", type: "mindfulness",
            theme: i.severity == "warn" ? .warning : (i.severity == "success" ? .positive : .neutral),
            generatedAt: ctx.nowIso, periodStart: "", periodEnd: "", priority: i.type == "tier2" ? 80 : 45,
            headline: i.title, subhead: i.type == "tier2" ? "Need vs Greed" : "Spending Insight",
            bullets: [i.body], metric: nil, visual: nil, cta: nil, cadenceKey: "mindfulness:\(i.id)", cadenceFrequency: "weekly"
        )
    }
}

// Explicitly `@Sendable` -- a bare `(GenContext) -> [InsightCard]` function-type
// element isn't inferred Sendable, so Swift 6 strict concurrency flags this
// global `let` array as possibly holding shared mutable state even though
// every element is a top-level function with no captures (trivially
// Sendable). Every genXxx below is a free function, so the annotation costs
// nothing at the call sites.
private let GENERATORS: [@Sendable (GenContext) -> [InsightCard]] = [
    genBudgetWarnings, genCategorySpike, genMonthPace, genWeeklySummary, genSpendingTrend,
    genBiggestExpense, genSubscriptions, genCategoryBreakdown, genGoalProgress, genSavingsAchievement,
    genStreak, genLabelBreakdown, genAvgDaily, genWeekdayPattern, genNoSpendDays,
    genDividends, genProjection, genMindfulness,
]

/// Run every generator, then rank + dedupe by cadence key, capped to `limit`.
public func composeStack(_ ctx: GenContext, limit: Int = 12) -> [InsightCard] {
    let all = GENERATORS.flatMap { $0(ctx) }
    var byKey: [String: InsightCard] = [:]
    var order: [String] = []
    for c in all {
        if let existing = byKey[c.cadenceKey] {
            if c.priority > existing.priority { byKey[c.cadenceKey] = c }
        } else {
            byKey[c.cadenceKey] = c
            order.append(c.cadenceKey)
        }
    }
    let deduped = order.compactMap { byKey[$0] }
    return Array(deduped.sorted { $0.priority > $1.priority }.prefix(limit))
}
