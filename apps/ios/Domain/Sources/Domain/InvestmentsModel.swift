import Foundation

/// Investments domain model (pure, UI-agnostic) -- Swift port of
/// apps/web/src/investments/model.ts, mirroring Android's
/// domain/investments/InvestmentsModel.kt field-for-field (2026-08-06,
/// task #26). A "holding" is any tracked investment: a listed stock/MF, or
/// a crypto coin, fixed deposit, SIP, or other scheme. Holdings are
/// grouped for display by **exchange** (for listed stocks) and by **asset
/// class** (everything else), each group carrying invested/current/gain
/// subtotals.
///
/// Live market quotes are NOT ported (see docs/mobile/screen-specs/
/// investments.md's Deferred section) -- `valuation` is always called
/// with `quotePrice = nil` on both native platforms, so listed holdings
/// value at `current_value ?? cost` exactly like an off-list holding
/// would on web. This is a real, documented simplification, not a bug.

public enum AssetClass: String, CaseIterable, Sendable {
    case stock, mf, sip, crypto, fd, other

    public var label: String {
        switch self {
        case .stock: return "Stock"
        case .mf: return "Mutual fund"
        case .sip: return "SIP"
        case .crypto: return "Crypto"
        case .fd: return "Fixed deposit"
        case .other: return "Other scheme"
        }
    }

    public var icon: String {
        switch self {
        case .stock: return "▤"
        case .mf: return "◈"
        case .sip: return "↻"
        case .crypto: return "◇"
        case .fd: return "▦"
        case .other: return "✦"
        }
    }

    public var unitWord: String {
        switch self {
        case .stock: return "shares"
        case .mf, .sip: return "units"
        case .crypto: return "coins"
        case .fd, .other: return ""
        }
    }

    public static func fromKey(_ key: String?) -> AssetClass {
        guard let key, let c = AssetClass(rawValue: key) else { return .other }
        return c
    }
}

public func isListed(_ c: AssetClass) -> Bool { c == .stock || c == .mf }

/// Minimal holding shape the pure functions below operate on -- mirrors
/// web's HoldingRow / Android's HoldingRow. Callers (repositories) map
/// their own data type into this one.
public struct HoldingRow: Sendable {
    public let id: String
    public let accountId: String
    public let symbol: String
    public let exchange: String?
    public let quantity: Double
    public let avgCost: Int64?
    public let currency: String
    public let offList: Bool
    public let name: String?
    public let assetClass: String?
    public let currentValue: Int64?

    public init(id: String, accountId: String, symbol: String, exchange: String?, quantity: Double, avgCost: Int64?, currency: String, offList: Bool, name: String?, assetClass: String?, currentValue: Int64?) {
        self.id = id; self.accountId = accountId; self.symbol = symbol; self.exchange = exchange
        self.quantity = quantity; self.avgCost = avgCost; self.currency = currency; self.offList = offList
        self.name = name; self.assetClass = assetClass; self.currentValue = currentValue
    }
}

public func assetClassOf(_ h: HoldingRow) -> AssetClass { AssetClass.fromKey(h.assetClass) }

/// Display label for a holding -- matches web's holdingLabel() exactly.
public func holdingLabel(_ h: HoldingRow) -> String {
    if h.offList || !isListed(assetClassOf(h)) {
        if let n = h.name, !n.isEmpty { return n }
        if !h.symbol.isEmpty { return h.symbol }
        return "Investment"
    }
    if !h.symbol.isEmpty { return h.symbol }
    if let n = h.name, !n.isEmpty { return n }
    return "Holding"
}

/// Stable grouping key: listed stocks by exchange, everything else by class.
public func groupKeyOf(_ h: HoldingRow) -> String {
    let c = assetClassOf(h)
    if c == .stock {
        let ex = (h.exchange?.isEmpty == false ? h.exchange! : "OTHER").uppercased()
        return "ex:\(ex)"
    }
    return "cls:\(c.rawValue)"
}

private let CLASS_LABEL: [AssetClass: String] = [
    .stock: "Stocks", .mf: "Mutual Funds", .crypto: "Crypto", .fd: "Fixed Deposits", .sip: "SIPs", .other: "Other Schemes",
]

public func groupLabel(_ key: String) -> String {
    if key.hasPrefix("ex:") {
        let ex = String(key.dropFirst(3))
        return ex == "OTHER" ? "Stocks (other)" : ex
    }
    let c = AssetClass.fromKey(String(key.dropFirst(4)))
    return CLASS_LABEL[c] ?? "Investments"
}

public func groupSort(_ key: String) -> Int {
    if key.hasPrefix("ex:") { return 0 }
    let order: [String: Int] = ["mf": 10, "sip": 11, "crypto": 12, "fd": 13, "other": 14]
    return order[String(key.dropFirst(4))] ?? 20
}

public struct Valuation: Sendable {
    public let cost: Int64
    public let value: Int64
    public let gain: Int64
    public let gainPct: Double
}

/// Value a holding in its own currency (minor units). Listed & priced
/// would use a live quote x quantity, but this port has no live-quote
/// source (deferred) so [quotePrice] is always nil in practice -- falls
/// back to the user-supplied current_value, else cost.
public func valuation(_ h: HoldingRow, quotePrice: Double? = nil) -> Valuation {
    let cost = Int64((Double(h.avgCost ?? 0) * h.quantity).rounded())
    let priced = !h.offList && isListed(assetClassOf(h)) && quotePrice != nil
    let value = priced ? Int64((quotePrice! * h.quantity).rounded()) : (h.currentValue ?? cost)
    let gain = value - cost
    let gainPct = cost > 0 ? (Double(gain) / Double(cost)) * 100 : 0
    return Valuation(cost: cost, value: value, gain: gain, gainPct: gainPct)
}

public struct InvestmentGroup: Sendable {
    public let key: String
    public let label: String
    public let holdings: [HoldingRow]
    public let cost: Int64
    public let value: Int64
    public let gain: Int64
    public let gainPct: Double
}

/// Bucket holdings into display groups with base-currency subtotals.
/// [convert] converts a holding-currency minor amount to base currency.
public func buildGroups(_ holdings: [HoldingRow], convert: (Int64, String) -> Int64) -> [InvestmentGroup] {
    struct Acc { var key: String; var label: String; var holdings: [HoldingRow] = []; var cost: Int64 = 0; var value: Int64 = 0 }
    var order: [String] = []
    var map: [String: Acc] = [:]
    for h in holdings {
        let key = groupKeyOf(h)
        if map[key] == nil {
            map[key] = Acc(key: key, label: groupLabel(key))
            order.append(key)
        }
        let v = valuation(h)
        map[key]!.holdings.append(h)
        map[key]!.cost += convert(v.cost, h.currency)
        map[key]!.value += convert(v.value, h.currency)
    }
    let groups = order.map { key -> InvestmentGroup in
        let acc = map[key]!
        let gain = acc.value - acc.cost
        let gainPct = acc.cost > 0 ? (Double(gain) / Double(acc.cost)) * 100 : 0
        return InvestmentGroup(key: acc.key, label: acc.label, holdings: acc.holdings, cost: acc.cost, value: acc.value, gain: gain, gainPct: gainPct)
    }
    return groups.sorted { a, b in
        let sa = groupSort(a.key), sb = groupSort(b.key)
        return sa != sb ? sa < sb : a.label < b.label
    }
}

public struct PortfolioTotals: Sendable {
    public let cost: Int64
    public let value: Int64
    public let gain: Int64
    public let gainPct: Double
}

public func portfolioTotals(_ groups: [InvestmentGroup]) -> PortfolioTotals {
    let cost = groups.reduce(0) { $0 + $1.cost }
    let value = groups.reduce(0) { $0 + $1.value }
    let gain = value - cost
    let gainPct = cost > 0 ? (Double(gain) / Double(cost)) * 100 : 0
    return PortfolioTotals(cost: cost, value: value, gain: gain, gainPct: gainPct)
}
