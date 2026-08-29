import Foundation

// Ported verbatim from apps/web/src/market/dividends.ts (89 lines) for the
// Insights feed's dividend_income/portfolio_projection cards (task #28).
// Mirrors Android's domain/insights/Dividends.kt added the same session.
// Neither this file's callers, nor apps/investments (P3.10/P3.15, task
// #26/#40), previously ported this math -- Investments' own spec lists a
// Dividend/Projection panel that was never actually built; this is the
// first mobile port of dividends.ts, done here because the Insights cards
// need it. Not golden-vector tested (dividends.ts has no vectors on web
// either -- see AUDIT_HISTORY's Insights entry).

/// A holding, reduced to the fields dividend matching needs.
public struct HoldingLite: Sendable {
    public let symbol: String
    public let exchange: String?
    public let quantity: Double
    public let currency: String
    public init(symbol: String, exchange: String?, quantity: Double, currency: String) {
        self.symbol = symbol; self.exchange = exchange; self.quantity = quantity; self.currency = currency
    }
}

/// One row from `market_dividends` (global, read-only).
public struct DivRow: Sendable {
    public let symbol: String
    public let exchange: String?
    public let exDate: String
    public let payDate: String?
    public let amount: Int64
    public let currency: String
    public init(symbol: String, exchange: String?, exDate: String, payDate: String?, amount: Int64, currency: String) {
        self.symbol = symbol; self.exchange = exchange; self.exDate = exDate; self.payDate = payDate; self.amount = amount; self.currency = currency
    }
}

/// One dividend payment estimated in the user's base currency (minor units).
public struct DivEvent: Sendable {
    public let date: String
    public let base: Int64
    public let upcoming: Bool
}

private func divKey(_ symbol: String, _ exchange: String?) -> String {
    "\(symbol.uppercased())|\((exchange ?? "").uppercased())"
}

/// Estimate dividend income per ex-date in base currency: for each dividend
/// row, sum (amount-per-share x shares held) over matching holdings,
/// converted to base. Uses CURRENT quantity (historical share counts
/// aren't tracked -- a reasonable estimate, matches web exactly). Matches
/// on symbol+exchange, falling back to symbol only.
public func computeDividendEvents(_ holdings: [HoldingLite], _ dividends: [DivRow], _ getRate: RateLookup, _ base: String) -> [DivEvent] {
    var bySymEx: [String: [HoldingLite]] = [:]
    var bySym: [String: [HoldingLite]] = [:]
    for h in holdings {
        bySymEx[divKey(h.symbol, h.exchange), default: []].append(h)
        bySym[h.symbol.uppercased(), default: []].append(h)
    }
    let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
    var events: [DivEvent] = []
    for d in dividends {
        let matches = bySymEx[divKey(d.symbol, d.exchange)] ?? bySym[d.symbol.uppercased()] ?? []
        if matches.isEmpty { continue }
        let shares = matches.reduce(0.0) { $0 + $1.quantity }
        if shares <= 0 { continue }
        let inCcy = Double(d.amount) * shares
        let rate = d.currency == base ? 1.0 : getRate(d.currency, base)
        events.append(DivEvent(date: d.exDate, base: Int64((inCcy * rate).rounded()), upcoming: d.exDate >= today))
    }
    return events.sorted { $0.date < $1.date }
}

public enum DividendPeriod: Sendable { case week, month, quarter, year, all }

public struct DividendBucket: Sendable {
    public let label: String
    public let key: String
    public let value: Int64
    public let upcoming: Bool
}

private let MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

private func isoWeek(_ d: Date) -> String {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let week = cal.component(.weekOfYear, from: d)
    let year = cal.component(.yearForWeekOfYear, from: d)
    return "\(year)-W\(String(format: "%02d", week))"
}

/// Group events into period buckets. Recent windows are capped; "all"
/// spans everything by year -- matches web's bucketize() exactly.
public func bucketize(_ events: [DivEvent], _ period: DividendPeriod) -> [DividendBucket] {
    var map: [String: DividendBucket] = [:]
    var order: [String] = []
    func put(_ k: String, _ label: String, _ v: Int64, _ upcoming: Bool) {
        if let cur = map[k] {
            map[k] = DividendBucket(label: cur.label, key: cur.key, value: cur.value + v, upcoming: cur.upcoming || upcoming)
        } else {
            map[k] = DividendBucket(label: label, key: k, value: v, upcoming: upcoming)
            order.append(k)
        }
    }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    for e in events {
        guard let d = ISO8601DateFormatter().date(from: e.date + "T00:00:00Z") else { continue }
        let year = cal.component(.year, from: d); let month = cal.component(.month, from: d)
        switch period {
        case .week: put(isoWeek(d), "\(MONTHS_SHORT[month - 1]) \(cal.component(.day, from: d))", e.base, e.upcoming)
        case .month: put("\(year)-\(String(format: "%02d", month))", "\(MONTHS_SHORT[month - 1]) '\(String(year).suffix(2))", e.base, e.upcoming)
        case .quarter:
            let q = (month - 1) / 3 + 1
            put("\(year)-Q\(q)", "Q\(q) '\(String(year).suffix(2))", e.base, e.upcoming)
        case .year, .all: put(String(year), String(year), e.base, e.upcoming) // year & all -> by year
        }
    }
    let all = order.sorted().compactMap { map[$0] }
    let cap: Int
    switch period { case .week: cap = 12; case .month: cap = 12; case .quarter: cap = 8; case .year: cap = 6; case .all: cap = 999 }
    return all.count > cap ? Array(all.suffix(cap)) : all
}

public struct DividendSummary: Sendable {
    public let trailing12: Int64
    public let upcoming12: Int64
    public let total: Int64
}

/// Trailing-12-month realized income + projected next-12-month income (from
/// scheduled + trailing run-rate) -- matches web's dividendSummary() exactly.
public func dividendSummary(_ events: [DivEvent]) -> DividendSummary {
    let now = Date().timeIntervalSince1970 * 1000
    let yearMs: Double = 365 * 86_400_000
    var trailing12: Int64 = 0; var upcoming12: Int64 = 0; var total: Int64 = 0
    for e in events {
        total += e.base
        guard let d = ISO8601DateFormatter().date(from: e.date + "T00:00:00Z") else { continue }
        let t = d.timeIntervalSince1970 * 1000
        if t <= now && t >= now - yearMs { trailing12 += e.base }
        if t > now && t <= now + yearMs { upcoming12 += e.base }
    }
    return DividendSummary(trailing12: trailing12, upcoming12: upcoming12, total: total)
}
