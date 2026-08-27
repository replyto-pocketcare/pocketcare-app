import Foundation

/**
 The financial snapshot the assistant is given — and the only financial data
 that ever leaves the device.

 Ported from `apps/web/src/assistant/summary.ts`. Web's header makes the claim
 and this type is what enforces it: **aggregates only, never raw transactions.**
 No merchant names, no dates of individual spends, no counterparties. Amounts are
 MAJOR units here rather than minor, because the model reads them.

 Building this is repository work; SHAPING it for the prompt is not, and that
 half is here under vectors — because the prompt is an input to the model, and a
 phone that sent a differently-shaped prompt would get different answers to the
 same question.

 Mirrors Android's AssistantSummary.kt.
 */

public struct SummaryAccount: Equatable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let currency: String
    /// Major units.
    public let balance: Double
    public init(id: String, name: String, type: String, currency: String, balance: Double) {
        self.id = id
        self.name = name
        self.type = type
        self.currency = currency
        self.balance = balance
    }
}

public struct SummaryGoal: Equatable, Sendable {
    public let name: String
    public let target: Double
    public let saved: Double
    public let currency: String
    public init(name: String, target: Double, saved: Double, currency: String) {
        self.name = name
        self.target = target
        self.saved = saved
        self.currency = currency
    }
}

public struct SummaryUpcoming: Equatable, Sendable {
    public let name: String
    public let date: String
    public let amount: Double
    public let currency: String
    public init(name: String, date: String, amount: Double, currency: String) {
        self.name = name
        self.date = date
        self.amount = amount
        self.currency = currency
    }
}

public struct SummarySplits: Equatable, Sendable {
    public let owed: Double
    public let owe: Double
    public let groups: Int
    public init(owed: Double = 0, owe: Double = 0, groups: Int = 0) {
        self.owed = owed
        self.owe = owe
        self.groups = groups
    }
}

public struct SummaryMonth: Equatable, Sendable {
    public let ym: String
    public let income: Double
    public let expense: Double
    public init(ym: String, income: Double, expense: Double) {
        self.ym = ym
        self.income = income
        self.expense = expense
    }
}

public struct SummaryCategory: Equatable, Sendable {
    public let name: String
    public let amount: Double
    public init(name: String, amount: Double) {
        self.name = name
        self.amount = amount
    }
}

public struct FinancialSummary: Equatable, Sendable {
    public let baseCurrency: String
    /// YYYY-MM-DD. Carried for the caller; deliberately NOT sent in the prompt.
    public let today: String
    public let accounts: [SummaryAccount]
    public let liquidSavings: Double
    public let avgMonthlyIncome: Double
    public let avgMonthlyExpense: Double
    public let monthlySurplus: Double
    public let fixedMonthlyObligations: Double
    public let goals: [SummaryGoal]
    public let upcoming: [SummaryUpcoming]
    public let splits: SummarySplits
    /// Last 6 calendar months of income vs expense, major units.
    public let monthlyCashflow: [SummaryMonth]
    /// Top expense categories over the last ~3 months, major units.
    public let topCategories: [SummaryCategory]

    public init(
        baseCurrency: String,
        today: String,
        accounts: [SummaryAccount] = [],
        liquidSavings: Double = 0,
        avgMonthlyIncome: Double = 0,
        avgMonthlyExpense: Double = 0,
        monthlySurplus: Double = 0,
        fixedMonthlyObligations: Double = 0,
        goals: [SummaryGoal] = [],
        upcoming: [SummaryUpcoming] = [],
        splits: SummarySplits = SummarySplits(),
        monthlyCashflow: [SummaryMonth] = [],
        topCategories: [SummaryCategory] = []
    ) {
        self.baseCurrency = baseCurrency
        self.today = today
        self.accounts = accounts
        self.liquidSavings = liquidSavings
        self.avgMonthlyIncome = avgMonthlyIncome
        self.avgMonthlyExpense = avgMonthlyExpense
        self.monthlySurplus = monthlySurplus
        self.fixedMonthlyObligations = fixedMonthlyObligations
        self.goals = goals
        self.upcoming = upcoming
        self.splits = splits
        self.monthlyCashflow = monthlyCashflow
        self.topCategories = topCategories
    }
}

/// Web's own caps. Every one of them is a token budget, not a display choice.
let summaryMaxAccounts = 12
let summaryMaxGoals = 12
let summaryMaxUpcoming = 8

/**
 `JSON.stringify` on a number that is an exact multiple of one hundredth.

 The general JS algorithm is shortest-round-trip and is a genuinely hard thing to
 reimplement twice identically. It is also unnecessary here: EVERY number in this
 prompt comes from web's `major()`, which is `Math.round(minor) / 100`, or from
 `monthlySurplus`, which is `+(x).toFixed(2)`. Both are an integer number of
 hundredths, and for those the formatting is three cases.

 The narrow contract is the point. `1234.0` is what both `Double.description` and
 Kotlin's `toString` produce and `1234` is what JS produces — a general
 "close enough" formatter would put a different prompt in front of the model on
 each platform and nothing would ever fail loudly.
 */
func jsonHundredths(_ v: Double) -> String {
    // `Math.round` semantics — half UP — though the input should already be
    // integral and this is only absorbing float noise.
    let cents = Int64(jsRound(v * 100))
    if cents == 0 { return "0" }
    let negative = cents < 0
    let magnitude = abs(cents)
    let whole = magnitude / 100
    let frac = magnitude % 100
    let body: String
    if frac == 0 {
        body = "\(whole)"
    } else if frac % 10 == 0 {
        body = "\(whole).\(frac / 10)"
    } else {
        body = "\(whole)." + String(format: "%02d", frac)
    }
    return negative ? "-" + body : body
}

/**
 `JSON.stringify` on a string.

 Non-ASCII is left ALONE, which is what JSON.stringify does — escaping it would
 be valid JSON and a different prompt, and merchant names in this app are
 routinely Devanagari.
 */
func jsonQuote(_ s: String) -> String {
    var out = "\""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case "\u{08}": out += "\\b"
        case "\u{0C}": out += "\\f"
        default:
            if ch.value < 0x20 {
                out += String(format: "\\u%04x", ch.value)
            } else {
                out.unicodeScalars.append(ch)
            }
        }
    }
    return out + "\""
}

private func obj(_ fields: [String]) -> String { "{" + fields.joined(separator: ",") + "}" }
private func field(_ key: String, _ value: String) -> String { "\(jsonQuote(key)):\(value)" }
private func arr<T>(_ items: [T], _ render: (T) -> String) -> String {
    "[" + items.map(render).joined(separator: ",") + "]"
}

/**
 Compact, token-light JSON of the summary — the exact string web sends.

 Empty sections are dropped and lists are capped, both to save tokens. Two
 details are easy to lose and are load-bearing:

 * **`today` is not sent.** It is on the type for the caller's use; the prompt
   carries the date separately.
 * **`upcoming` drops its currency.** Web's projection is `{n, date, amt}` and
   nothing else, so a renewal in a second currency is sent as a bare number.
   That is web's behaviour, reproduced rather than fixed — a phone that sent an
   extra field would be answering a different prompt.
 */
public func summaryForPrompt(_ s: FinancialSummary) -> String {
    var out: [String] = [
        field("baseCurrency", jsonQuote(s.baseCurrency)),
        field("liquidSavings", jsonHundredths(s.liquidSavings)),
        field("avgMonthlyIncome", jsonHundredths(s.avgMonthlyIncome)),
        field("avgMonthlyExpense", jsonHundredths(s.avgMonthlyExpense)),
        field("monthlySurplus", jsonHundredths(s.monthlySurplus)),
        field("fixedMonthlyObligations", jsonHundredths(s.fixedMonthlyObligations)),
        field("accounts", arr(Array(s.accounts.prefix(summaryMaxAccounts))) { a in
            obj([
                field("id", jsonQuote(a.id)),
                field("n", jsonQuote(a.name)),
                field("t", jsonQuote(a.type)),
                field("c", jsonQuote(a.currency)),
                field("bal", jsonHundredths(a.balance)),
            ])
        }),
    ]
    if !s.goals.isEmpty {
        out.append(field("goals", arr(Array(s.goals.prefix(summaryMaxGoals))) { g in
            obj([
                field("n", jsonQuote(g.name)),
                field("target", jsonHundredths(g.target)),
                field("saved", jsonHundredths(g.saved)),
                field("c", jsonQuote(g.currency)),
            ])
        }))
    }
    if !s.upcoming.isEmpty {
        out.append(field("upcoming", arr(Array(s.upcoming.prefix(summaryMaxUpcoming))) { u in
            obj([
                field("n", jsonQuote(u.name)),
                field("date", jsonQuote(u.date)),
                field("amt", jsonHundredths(u.amount)),
            ])
        }))
    }
    // Any ONE of the three being non-zero sends all three — "you owe nothing and
    // are owed nothing across 3 groups" is a real answer.
    if s.splits.owed != 0 || s.splits.owe != 0 || s.splits.groups != 0 {
        out.append(field("splits", obj([
            field("friendsOweYou", jsonHundredths(s.splits.owed)),
            field("youOwe", jsonHundredths(s.splits.owe)),
            field("groups", "\(s.splits.groups)"),
        ])))
    }
    // A run of all-zero months is six months of nothing, and saying so costs
    // tokens the model cannot use.
    if s.monthlyCashflow.contains(where: { $0.income != 0 || $0.expense != 0 }) {
        out.append(field("monthly", arr(s.monthlyCashflow) { m in
            obj([
                field("ym", jsonQuote(m.ym)),
                field("in", jsonHundredths(m.income)),
                field("exp", jsonHundredths(m.expense)),
            ])
        }))
    }
    if !s.topCategories.isEmpty {
        out.append(field("topSpendCategories", arr(s.topCategories) { c in
            obj([field("n", jsonQuote(c.name)), field("amt", jsonHundredths(c.amount))])
        }))
    }
    return obj(out)
}
