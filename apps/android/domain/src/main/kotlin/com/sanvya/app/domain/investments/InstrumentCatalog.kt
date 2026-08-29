package com.sanvya.app.domain.investments

/**
 * The searchable universe of listed instruments behind the Add-investment
 * picker -- Kotlin port of apps/web/src/instruments/catalog.ts's SEED table
 * and searchInstruments().
 *
 * WHAT IS PORTED AND WHAT IS NOT. Web keeps two catalogs: this bundled seed,
 * which ships with the app and works on a brand-new install with no network,
 * and a 63k-row daily CSV it streams from GitHub into IndexedDB. Only the
 * seed is ported. The download needs an HTTP client, a local store that is
 * explicitly NOT PowerSync (it is global reference data, not user data), a
 * progress UI and a daily ETag check on two platforms -- and none of that
 * changes the shape of anything here, because the search below already takes
 * the candidate list as a PARAMETER rather than reading a module global the
 * way web's does. Wiring a downloaded list in later is a new caller, not a
 * rewrite.
 *
 * What the seed DOES fix is the defect it was ported for: before it, every
 * holding added on a phone was written `off_list = 1`, so nothing the user
 * entered could ever be priced, matched to a dividend row, or recognised as
 * the same instrument they hold on web.
 */

/** One listed instrument. Mirrors web's `Instrument`. */
data class Instrument(
    /** Ticker, upper-cased (e.g. "AAPL", "RELIANCE"). */
    val symbol: String,
    /** Company / fund name. */
    val name: String,
    /** Exchange code (e.g. "NASDAQ", "NSE_IN"). */
    val exchange: String,
    /** ISO 4217 code the instrument trades in. */
    val currency: String,
)

/** Stable key so the same ticker on two exchanges stays distinct. */
fun instrumentKey(symbol: String, exchange: String): String =
    "${symbol.uppercase()}|${exchange.uppercase()}"

/**
 * A compact, high-coverage starter set across the exchanges Sanvya users
 * actually hold, transcribed from web's SEED in catalog.ts.
 *
 * This is reference data, not copy: every field is a ticker, a legal entity
 * name, an exchange code or an ISO 4217 code, none of which is translated on
 * any platform. It is a table, and it stays a literal for the same reason
 * `lakhCroreCurrencies` does.
 */
val SEED_INSTRUMENTS: List<Instrument> = listOf(
    // United States -- NASDAQ
    Instrument("AAPL", "Apple Inc.", "NASDAQ", "USD"),
    Instrument("MSFT", "Microsoft Corp.", "NASDAQ", "USD"),
    Instrument("NVDA", "NVIDIA Corp.", "NASDAQ", "USD"),
    Instrument("AMZN", "Amazon.com Inc.", "NASDAQ", "USD"),
    Instrument("GOOGL", "Alphabet Inc. Class A", "NASDAQ", "USD"),
    Instrument("META", "Meta Platforms Inc.", "NASDAQ", "USD"),
    Instrument("TSLA", "Tesla Inc.", "NASDAQ", "USD"),
    Instrument("AVGO", "Broadcom Inc.", "NASDAQ", "USD"),
    Instrument("COST", "Costco Wholesale Corp.", "NASDAQ", "USD"),
    Instrument("NFLX", "Netflix Inc.", "NASDAQ", "USD"),
    Instrument("AMD", "Advanced Micro Devices Inc.", "NASDAQ", "USD"),
    Instrument("PEP", "PepsiCo Inc.", "NASDAQ", "USD"),
    Instrument("QQQ", "Invesco QQQ Trust", "NASDAQ", "USD"),
    // United States -- NYSE
    Instrument("BRK.B", "Berkshire Hathaway Inc. Class B", "NYSE", "USD"),
    Instrument("JPM", "JPMorgan Chase & Co.", "NYSE", "USD"),
    Instrument("V", "Visa Inc.", "NYSE", "USD"),
    Instrument("MA", "Mastercard Inc.", "NYSE", "USD"),
    Instrument("JNJ", "Johnson & Johnson", "NYSE", "USD"),
    Instrument("WMT", "Walmart Inc.", "NYSE", "USD"),
    Instrument("XOM", "Exxon Mobil Corp.", "NYSE", "USD"),
    Instrument("PG", "Procter & Gamble Co.", "NYSE", "USD"),
    Instrument("KO", "Coca-Cola Co.", "NYSE", "USD"),
    Instrument("DIS", "Walt Disney Co.", "NYSE", "USD"),
    Instrument("BAC", "Bank of America Corp.", "NYSE", "USD"),
    Instrument("SPY", "SPDR S&P 500 ETF Trust", "NYSE", "USD"),
    Instrument("VOO", "Vanguard S&P 500 ETF", "NYSE", "USD"),
    // India -- NSE
    Instrument("RELIANCE", "Reliance Industries Ltd.", "NSE_IN", "INR"),
    Instrument("TCS", "Tata Consultancy Services Ltd.", "NSE_IN", "INR"),
    Instrument("HDFCBANK", "HDFC Bank Ltd.", "NSE_IN", "INR"),
    Instrument("INFY", "Infosys Ltd.", "NSE_IN", "INR"),
    Instrument("ICICIBANK", "ICICI Bank Ltd.", "NSE_IN", "INR"),
    Instrument("BHARTIARTL", "Bharti Airtel Ltd.", "NSE_IN", "INR"),
    Instrument("SBIN", "State Bank of India", "NSE_IN", "INR"),
    Instrument("ITC", "ITC Ltd.", "NSE_IN", "INR"),
    Instrument("LT", "Larsen & Toubro Ltd.", "NSE_IN", "INR"),
    Instrument("HINDUNILVR", "Hindustan Unilever Ltd.", "NSE_IN", "INR"),
    Instrument("NIFTYBEES", "Nippon India Nifty 50 BeES ETF", "NSE_IN", "INR"),
    // India -- BSE (dual-listed names commonly held)
    Instrument("500325", "Reliance Industries Ltd.", "BSE_IN", "INR"),
    Instrument("532540", "Tata Consultancy Services Ltd.", "BSE_IN", "INR"),
    // United Kingdom -- LSE
    Instrument("HSBA", "HSBC Holdings plc", "LSE", "GBP"),
    Instrument("AZN", "AstraZeneca plc", "LSE", "GBP"),
    Instrument("SHEL", "Shell plc", "LSE", "GBP"),
    Instrument("ULVR", "Unilever plc", "LSE", "GBP"),
    Instrument("BP", "BP plc", "LSE", "GBP"),
    Instrument("VUSA", "Vanguard S&P 500 UCITS ETF", "LSE", "GBP"),
    // Europe
    Instrument("ASML", "ASML Holding N.V.", "AMS", "EUR"),
    Instrument("MC", "LVMH Moet Hennessy Louis Vuitton", "EPA", "EUR"),
    Instrument("SAP", "SAP SE", "XETRA", "EUR"),
    Instrument("SIE", "Siemens AG", "XETRA", "EUR"),
    Instrument("NESN", "Nestle S.A.", "SWX", "CHF"),
    // Asia-Pacific
    Instrument("7203", "Toyota Motor Corp.", "TSE", "JPY"),
    Instrument("9984", "SoftBank Group Corp.", "TSE", "JPY"),
    Instrument("0700", "Tencent Holdings Ltd.", "HKEX", "HKD"),
    Instrument("9988", "Alibaba Group Holding Ltd.", "HKEX", "HKD"),
    Instrument("BHP", "BHP Group Ltd.", "ASX", "AUD"),
    Instrument("CBA", "Commonwealth Bank of Australia", "ASX", "AUD"),
    // Canada
    Instrument("RY", "Royal Bank of Canada", "TSX", "CAD"),
    Instrument("SHOP", "Shopify Inc.", "TSX", "CAD"),
)

/**
 * Every key in the bundled seed, sorted.
 *
 * Exists to be vector-pinned. The seed is the one thing in this file that is
 * hand-transcribed on two platforms, so it is the one thing that can silently
 * drift between them -- and a search vector cannot catch that, because the
 * search takes its candidates as an argument. This can.
 */
fun seedInstrumentKeys(): List<String> =
    SEED_INSTRUMENTS.map { instrumentKey(it.symbol, it.exchange) }.sorted()

/** All distinct exchanges present in [list], sorted. Matches web's knownExchanges(). */
fun knownExchanges(list: List<Instrument>): List<String> =
    list.map { it.exchange }.distinct().sorted()

/**
 * Search [all] by symbol or name, case-insensitively, optionally scoped to
 * one exchange. Ranking is web's, exactly: exact symbol, then symbol prefix,
 * then name prefix, then a substring of either -- ties broken by symbol so
 * the list is stable between keystrokes.
 *
 * An empty query returns the head of the (unranked) scoped list rather than
 * nothing, which is what makes picking an exchange first a useful move.
 */
fun searchInstruments(all: List<Instrument>, query: String, exchange: String?, limit: Int = 30): List<Instrument> {
    val scoped = if (exchange != null) all.filter { it.exchange == exchange } else all
    val q = query.trim().lowercase()
    if (q.isEmpty()) return scoped.take(limit)
    val scored = mutableListOf<Pair<Instrument, Int>>()
    for (i in scoped) {
        val sym = i.symbol.lowercase()
        val name = i.name.lowercase()
        val s = when {
            sym == q -> 0
            sym.startsWith(q) -> 1
            name.startsWith(q) -> 2
            sym.contains(q) || name.contains(q) -> 3
            else -> -1
        }
        if (s >= 0) scored.add(i to s)
    }
    return scored
        .sortedWith(compareBy({ it.second }, { it.first.symbol }))
        .take(limit)
        .map { it.first }
}
