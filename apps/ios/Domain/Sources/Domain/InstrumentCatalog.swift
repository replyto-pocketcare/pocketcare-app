import Foundation

/// The searchable universe of listed instruments behind the Add-investment
/// picker -- Swift port of apps/web/src/instruments/catalog.ts's SEED table
/// and searchInstruments(), mirroring Android's
/// domain/investments/InstrumentCatalog.kt row for row.
///
/// WHAT IS PORTED AND WHAT IS NOT. Web keeps two catalogs: this bundled seed,
/// which ships with the app and works on a brand-new install with no network,
/// and a 63k-row daily CSV it streams from GitHub into IndexedDB. Only the
/// seed is ported. The download needs an HTTP client, a local store that is
/// explicitly NOT PowerSync (it is global reference data, not user data), a
/// progress UI and a daily ETag check on two platforms -- and none of that
/// changes the shape of anything here, because the search below already takes
/// the candidate list as a PARAMETER rather than reading a module global the
/// way web's does. Wiring a downloaded list in later is a new caller, not a
/// rewrite.
///
/// What the seed DOES fix is the defect it was ported for: before it, every
/// holding added on a phone was written `off_list = 1`, so nothing the user
/// entered could ever be priced, matched to a dividend row, or recognised as
/// the same instrument they hold on web.

/// One listed instrument. Mirrors web's `Instrument`.
public struct Instrument: Sendable, Equatable, Identifiable {
    /// Ticker, upper-cased (e.g. "AAPL", "RELIANCE").
    public let symbol: String
    /// Company / fund name.
    public let name: String
    /// Exchange code (e.g. "NASDAQ", "NSE_IN").
    public let exchange: String
    /// ISO 4217 code the instrument trades in.
    public let currency: String

    public init(symbol: String, name: String, exchange: String, currency: String) {
        self.symbol = symbol; self.name = name; self.exchange = exchange; self.currency = currency
    }

    /// The catalog key doubles as the SwiftUI list identity -- the same ticker
    /// on two exchanges is two rows and must not collide.
    public var id: String { instrumentKey(symbol, exchange) }
}

/// Stable key so the same ticker on two exchanges stays distinct.
public func instrumentKey(_ symbol: String, _ exchange: String) -> String {
    "\(symbol.uppercased())|\(exchange.uppercased())"
}

/// A compact, high-coverage starter set across the exchanges Sanvya users
/// actually hold, transcribed from web's SEED in catalog.ts.
///
/// This is reference data, not copy: every field is a ticker, a legal entity
/// name, an exchange code or an ISO 4217 code, none of which is translated on
/// any platform. It is a table, and it stays a literal for the same reason
/// `lakhCroreCurrencies` does.
public let seedInstruments: [Instrument] = [
    // United States -- NASDAQ
    Instrument(symbol: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "MSFT", name: "Microsoft Corp.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "NVDA", name: "NVIDIA Corp.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "AMZN", name: "Amazon.com Inc.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "GOOGL", name: "Alphabet Inc. Class A", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "META", name: "Meta Platforms Inc.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "TSLA", name: "Tesla Inc.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "AVGO", name: "Broadcom Inc.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "COST", name: "Costco Wholesale Corp.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "NFLX", name: "Netflix Inc.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "AMD", name: "Advanced Micro Devices Inc.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "PEP", name: "PepsiCo Inc.", exchange: "NASDAQ", currency: "USD"),
    Instrument(symbol: "QQQ", name: "Invesco QQQ Trust", exchange: "NASDAQ", currency: "USD"),
    // United States -- NYSE
    Instrument(symbol: "BRK.B", name: "Berkshire Hathaway Inc. Class B", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "JPM", name: "JPMorgan Chase & Co.", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "V", name: "Visa Inc.", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "MA", name: "Mastercard Inc.", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "JNJ", name: "Johnson & Johnson", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "WMT", name: "Walmart Inc.", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "XOM", name: "Exxon Mobil Corp.", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "PG", name: "Procter & Gamble Co.", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "KO", name: "Coca-Cola Co.", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "DIS", name: "Walt Disney Co.", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "BAC", name: "Bank of America Corp.", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "SPY", name: "SPDR S&P 500 ETF Trust", exchange: "NYSE", currency: "USD"),
    Instrument(symbol: "VOO", name: "Vanguard S&P 500 ETF", exchange: "NYSE", currency: "USD"),
    // India -- NSE
    Instrument(symbol: "RELIANCE", name: "Reliance Industries Ltd.", exchange: "NSE_IN", currency: "INR"),
    Instrument(symbol: "TCS", name: "Tata Consultancy Services Ltd.", exchange: "NSE_IN", currency: "INR"),
    Instrument(symbol: "HDFCBANK", name: "HDFC Bank Ltd.", exchange: "NSE_IN", currency: "INR"),
    Instrument(symbol: "INFY", name: "Infosys Ltd.", exchange: "NSE_IN", currency: "INR"),
    Instrument(symbol: "ICICIBANK", name: "ICICI Bank Ltd.", exchange: "NSE_IN", currency: "INR"),
    Instrument(symbol: "BHARTIARTL", name: "Bharti Airtel Ltd.", exchange: "NSE_IN", currency: "INR"),
    Instrument(symbol: "SBIN", name: "State Bank of India", exchange: "NSE_IN", currency: "INR"),
    Instrument(symbol: "ITC", name: "ITC Ltd.", exchange: "NSE_IN", currency: "INR"),
    Instrument(symbol: "LT", name: "Larsen & Toubro Ltd.", exchange: "NSE_IN", currency: "INR"),
    Instrument(symbol: "HINDUNILVR", name: "Hindustan Unilever Ltd.", exchange: "NSE_IN", currency: "INR"),
    Instrument(symbol: "NIFTYBEES", name: "Nippon India Nifty 50 BeES ETF", exchange: "NSE_IN", currency: "INR"),
    // India -- BSE (dual-listed names commonly held)
    Instrument(symbol: "500325", name: "Reliance Industries Ltd.", exchange: "BSE_IN", currency: "INR"),
    Instrument(symbol: "532540", name: "Tata Consultancy Services Ltd.", exchange: "BSE_IN", currency: "INR"),
    // United Kingdom -- LSE
    Instrument(symbol: "HSBA", name: "HSBC Holdings plc", exchange: "LSE", currency: "GBP"),
    Instrument(symbol: "AZN", name: "AstraZeneca plc", exchange: "LSE", currency: "GBP"),
    Instrument(symbol: "SHEL", name: "Shell plc", exchange: "LSE", currency: "GBP"),
    Instrument(symbol: "ULVR", name: "Unilever plc", exchange: "LSE", currency: "GBP"),
    Instrument(symbol: "BP", name: "BP plc", exchange: "LSE", currency: "GBP"),
    Instrument(symbol: "VUSA", name: "Vanguard S&P 500 UCITS ETF", exchange: "LSE", currency: "GBP"),
    // Europe
    Instrument(symbol: "ASML", name: "ASML Holding N.V.", exchange: "AMS", currency: "EUR"),
    Instrument(symbol: "MC", name: "LVMH Moet Hennessy Louis Vuitton", exchange: "EPA", currency: "EUR"),
    Instrument(symbol: "SAP", name: "SAP SE", exchange: "XETRA", currency: "EUR"),
    Instrument(symbol: "SIE", name: "Siemens AG", exchange: "XETRA", currency: "EUR"),
    Instrument(symbol: "NESN", name: "Nestle S.A.", exchange: "SWX", currency: "CHF"),
    // Asia-Pacific
    Instrument(symbol: "7203", name: "Toyota Motor Corp.", exchange: "TSE", currency: "JPY"),
    Instrument(symbol: "9984", name: "SoftBank Group Corp.", exchange: "TSE", currency: "JPY"),
    Instrument(symbol: "0700", name: "Tencent Holdings Ltd.", exchange: "HKEX", currency: "HKD"),
    Instrument(symbol: "9988", name: "Alibaba Group Holding Ltd.", exchange: "HKEX", currency: "HKD"),
    Instrument(symbol: "BHP", name: "BHP Group Ltd.", exchange: "ASX", currency: "AUD"),
    Instrument(symbol: "CBA", name: "Commonwealth Bank of Australia", exchange: "ASX", currency: "AUD"),
    // Canada
    Instrument(symbol: "RY", name: "Royal Bank of Canada", exchange: "TSX", currency: "CAD"),
    Instrument(symbol: "SHOP", name: "Shopify Inc.", exchange: "TSX", currency: "CAD"),
]

/// Every key in the bundled seed, sorted.
///
/// Exists to be vector-pinned. The seed is the one thing in this file that is
/// hand-transcribed on two platforms, so it is the one thing that can silently
/// drift between them -- and a search vector cannot catch that, because the
/// search takes its candidates as an argument. This can.
public func seedInstrumentKeys() -> [String] {
    seedInstruments.map { instrumentKey($0.symbol, $0.exchange) }.sorted()
}

/// All distinct exchanges present in `list`, sorted. Matches web's knownExchanges().
public func knownExchanges(_ list: [Instrument]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for i in list where !seen.contains(i.exchange) {
        seen.insert(i.exchange)
        out.append(i.exchange)
    }
    return out.sorted()
}

/// Search `all` by symbol or name, case-insensitively, optionally scoped to
/// one exchange. Ranking is web's, exactly: exact symbol, then symbol prefix,
/// then name prefix, then a substring of either -- ties broken by symbol so
/// the list is stable between keystrokes.
///
/// An empty query returns the head of the (unranked) scoped list rather than
/// nothing, which is what makes picking an exchange first a useful move.
public func searchInstruments(_ all: [Instrument], query: String, exchange: String?, limit: Int = 30) -> [Instrument] {
    let scoped = exchange != nil ? all.filter { $0.exchange == exchange } : all
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty { return Array(scoped.prefix(limit)) }
    var scored: [(Instrument, Int)] = []
    for i in scoped {
        let sym = i.symbol.lowercased()
        let name = i.name.lowercased()
        let s: Int
        if sym == q { s = 0 }
        else if sym.hasPrefix(q) { s = 1 }
        else if name.hasPrefix(q) { s = 2 }
        else if sym.contains(q) || name.contains(q) { s = 3 }
        else { s = -1 }
        if s >= 0 { scored.append((i, s)) }
    }
    let ranked = scored.sorted { a, b in a.1 != b.1 ? a.1 < b.1 : a.0.symbol < b.0.symbol }
    return ranked.prefix(limit).map { $0.0 }
}
