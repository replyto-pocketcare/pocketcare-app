import Foundation

/// A web path, resolved to a destination both native apps can navigate to.
///
/// Web hands links around as URLs -- `/budgets`, `/groups/<id>`,
/// `/search?q=Swiggy&type=expense` -- because on web the router IS the path.
/// Native has no such thing: SwiftUI and Compose each carry their own route
/// vocabulary, and neither is web's. Every place that receives a web path
/// therefore needs the same translation, and until now no such translation
/// existed, so both places that receive one -- the notification inbox and the
/// assistant's `<ui>` actions -- simply did nothing on tap.
///
/// This is the translation, and it is deliberately in Domain rather than in
/// either app: the paths are web's, the set is closed, and a difference between
/// the two platforms in where `/friends` lands is a bug that no compiler would
/// catch. What stays per-platform is the LAST step -- `AppScreen` to a SwiftUI
/// destination or a Compose route string.
///
/// Mirrors Android's AppLink.kt; pinned by `applink.json`.

/// Every destination a web path can name.
///
/// The names are web's routes, not iOS's or Android's, because the input is a
/// web path. Two of web's routes are redirects and are folded in here rather
/// than carried: `/subscriptions` redirects to `/recurring` and `/groups` to
/// `/friends`, and reproducing a redirect as a redirect on native would mean a
/// visible double-navigation for no reason.
public enum AppScreen: String, Sendable, Hashable, CaseIterable {
    case dashboard = "DASHBOARD"
    case accounts = "ACCOUNTS"
    case accountNew = "ACCOUNT_NEW"
    case accountEdit = "ACCOUNT_EDIT"
    case transactions = "TRANSACTIONS"
    case transactionNew = "TRANSACTION_NEW"
    case transactionEdit = "TRANSACTION_EDIT"
    case budgets = "BUDGETS"
    case goals = "GOALS"
    case recurring = "RECURRING"
    case recurringDirection = "RECURRING_DIRECTION"
    case loans = "LOANS"
    case loanDetail = "LOAN_DETAIL"
    case investments = "INVESTMENTS"
    case cards = "CARDS"
    case splits = "SPLITS"
    case groupDetail = "GROUP_DETAIL"
    case insights = "INSIGHTS"
    case reflect = "REFLECT"
    case statements = "STATEMENTS"
    case statementsAnalyze = "STATEMENTS_ANALYZE"
    case receiptNew = "RECEIPT_NEW"
    case search = "SEARCH"
    case notifications = "NOTIFICATIONS"
    case assistant = "ASSISTANT"
    case help = "HELP"
    case settings = "SETTINGS"
    case settingsData = "SETTINGS_DATA"
    case settingsCategories = "SETTINGS_CATEGORIES"
    case settingsLabels = "SETTINGS_LABELS"
    case login = "LOGIN"
}

/// A resolved link.
///
/// `id` is the record a detail route names (`/loans/<id>` -> the loan) or, for
/// `.recurringDirection`, the direction slug -- it is whatever the one dynamic
/// path segment held, unescaped.
///
/// `query` is the decoded query string, kept as strings because that is what
/// the receiving screen's filter state is made of. Only `.search` currently
/// reads it; it is carried for every screen because dropping it silently would
/// be worse than carrying something unused.
public struct AppLink: Equatable, Sendable, Hashable {
    public let screen: AppScreen
    public let id: String?
    public let query: [String: String]

    public init(screen: AppScreen, id: String? = nil, query: [String: String] = [:]) {
        self.screen = screen
        self.id = id
        self.query = query
    }
}

/// The static paths, exactly as web's `app/` directory defines them.
private let staticPaths: [String: AppScreen] = [
    "": .dashboard,
    "accounts": .accounts,
    "accounts/new": .accountNew,
    "transactions": .transactions,
    "transactions/new": .transactionNew,
    "budgets": .budgets,
    "goals": .goals,
    "recurring": .recurring,
    // `/subscriptions` is a server redirect to `/recurring` (web's own comment:
    // "kept so old links -- dashboard tiles, insights CTAs, bookmarks -- still
    // land"). The persona still advertises it, so it must resolve.
    "subscriptions": .recurring,
    "loans": .loans,
    "investments": .investments,
    "cards": .cards,
    "friends": .splits,
    // `/groups` redirects to `/friends` -- "Groups and Splits were one screen's
    // worth of information split across two". `/groups/<id>` is NOT a redirect
    // and is handled below.
    "groups": .splits,
    "insights": .insights,
    "reflect": .reflect,
    "statements": .statements,
    "statements/analyze": .statementsAnalyze,
    "receipts/new": .receiptNew,
    "search": .search,
    "notifications": .notifications,
    "assistant": .assistant,
    "help": .help,
    "settings": .settings,
    "settings/categories": .settingsCategories,
    "settings/labels": .settingsLabels,
    "data": .settingsData,
    "login": .login,
]

/// Resolve a web path.
///
/// Returns nil for anything that is not an in-app destination:
///
///  * an absolute URL (`https://...`) or a protocol-relative one (`//...`) --
///    the persona says "never an external URL", and honouring one would take
///    the user out of the app;
///  * a path with no leading `/`, which on web would resolve relative to
///    whatever page happened to be open and has no native meaning at all;
///  * `/admin/*`, `/auth/*`, `/onboarding`, `/join/*` -- real web routes with
///    no native destination, deliberately not guessed at;
///  * anything else unrecognised, including `/cashflow` and `/templates`, which
///    the assistant persona advertises and web does not implement (recorded as
///    a web defect in PARITY_AUDIT; NOT fixed here, because the persona is
///    generated from web's own text).
///
/// A nil result is a link that must not be offered, not one to render dead.
public func parseAppLink(_ href: String) -> AppLink? {
    let raw = href.trimmingCharacters(in: .whitespacesAndNewlines)
    guard raw.hasPrefix("/"), !raw.hasPrefix("//") else { return nil }

    let noHash = String(raw.prefix(while: { $0 != "#" }))
    let pathPart = String(noHash.prefix(while: { $0 != "?" }))
    let queryPart: String = {
        guard let mark = noHash.firstIndex(of: "?") else { return "" }
        return String(noHash[noHash.index(after: mark)...])
    }()

    // Trailing and doubled slashes are the same page on web; a segment list
    // that drops empties says exactly that without a normalisation pass.
    let segments = pathPart.split(separator: "/", omittingEmptySubsequences: true)
        .map { decodeUriComponent(String($0)) }
    let query = parseQuery(queryPart)
    let key = segments.joined(separator: "/")

    if let screen = staticPaths[key] { return AppLink(screen: screen, id: nil, query: query) }

    if segments.count == 3, segments[0] == "accounts", segments[2] == "edit" {
        return AppLink(screen: .accountEdit, id: segments[1], query: query)
    }
    if segments.count == 3, segments[0] == "transactions", segments[2] == "edit" {
        return AppLink(screen: .transactionEdit, id: segments[1], query: query)
    }
    if segments.count == 2, segments[0] == "loans" {
        return AppLink(screen: .loanDetail, id: segments[1], query: query)
    }
    if segments.count == 2, segments[0] == "groups" {
        return AppLink(screen: .groupDetail, id: segments[1], query: query)
    }
    // `/recurring/<direction>` takes a SLUG, not an id, and web 404s on an
    // unknown one. Only the two slugs that exist resolve; anything else is not
    // a destination.
    if segments.count == 2, segments[0] == "recurring", segments[1] == "income" || segments[1] == "expense" {
        return AppLink(screen: .recurringDirection, id: segments[1], query: query)
    }
    return nil
}

/// `?a=1&b=hello%20world` -> `["a": "1", "b": "hello world"]`.
///
/// Deliberately `URLSearchParams`' rules and not a generic percent-decode: `+`
/// means a space in a query string (and only there), a key with no `=` maps to
/// the empty string, and a repeated key keeps the FIRST value because that is
/// what `params.get(k)` returns.
private func parseQuery(_ query: String) -> [String: String] {
    if query.isEmpty { return [:] }
    var out: [String: String] = [:]
    for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
        let text = String(pair)
        let rawName: String
        let rawValue: String
        if let eq = text.firstIndex(of: "=") {
            rawName = String(text[text.startIndex..<eq])
            rawValue = String(text[text.index(after: eq)...])
        } else {
            rawName = text
            rawValue = ""
        }
        let name = decodeUriComponent(rawName.replacingOccurrences(of: "+", with: " "))
        if name.isEmpty { continue }
        if out[name] != nil { continue }
        out[name] = decodeUriComponent(rawValue.replacingOccurrences(of: "+", with: " "))
    }
    return out
}

/// Percent-decoding, by hand.
///
/// `removingPercentEncoding` returns nil for an invalid escape and for bytes
/// that are not valid UTF-8, which would turn one bad character in a link the
/// model wrote into a whole dead action. A malformed escape is left literal
/// instead, matching Android's port byte for byte.
private func isHexDigit(_ c: Character) -> Bool {
    ("0"..."9").contains(c) || ("a"..."f").contains(c) || ("A"..."F").contains(c)
}

private func decodeUriComponent(_ value: String) -> String {
    guard value.contains("%") else { return value }
    var bytes: [UInt8] = []
    let chars = Array(value)
    var i = 0
    while i < chars.count {
        // Both digits checked explicitly: `UInt8(_:radix:)` accepts a leading
        // sign, so "%-1" would decode to nothing here and to 0xFF in Kotlin's
        // `toIntOrNull(16)`. Two ports, one behaviour.
        if chars[i] == "%", i + 2 < chars.count,
           isHexDigit(chars[i + 1]), isHexDigit(chars[i + 2]),
           let byte = UInt8(String(chars[(i + 1)...(i + 2)]), radix: 16) {
            bytes.append(byte)
            i += 3
            continue
        }
        bytes.append(contentsOf: Array(String(chars[i]).utf8))
        i += 1
    }
    return String(decoding: bytes, as: UTF8.self)
}
