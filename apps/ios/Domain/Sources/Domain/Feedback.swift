import Foundation

// GENERATED FILE — do not hand-edit.
// Source: apps/web/src/ui/BugReport.tsx (AREAS, SEVERITIES, APP_VERSION)
// Regenerate with: node tools/parity/generate-feedback.mjs

/**
 The feedback form's vocabulary.

 `feedbackAreas` and `feedbackSeverities` are the values WRITTEN to
 `bug_reports`, and they are web's English strings on purpose: they are
 identifiers that happen to be readable, and a translated column is an
 unsortable one. The label shown on screen is looked up in the `feedback` i18n
 namespace by `feedbackAreaKey` / `feedbackSeverityKey`.
 */

/// Web's own picker order, which is not alphabetical and is not incidental.
public let feedbackAreas: [String] = [
    "Dashboard",
    "Transactions",
    "Accounts & Cards",
    "Budgets",
    "Goals",
    "Investments",
    "Friends & Splits",
    "Subscriptions",
    "Loans",
    "Ask Sanvya",
    "Insights",
    "Settings & Billing",
    "Sync / Offline",
    "Other",
]

/// Most severe first, as web lists them.
public let feedbackSeverities: [String] = [
    "fatal",
    "high",
    "medium",
    "low",
]

/// The i18n key for an area's on-screen label.
///
/// The separator test is ASCII-only, deliberately: Kotlin's side is the regex
/// `[^A-Za-z0-9]+`, and Swift's `isLetter` is Unicode-aware — `é` is a letter
/// to one and a separator to the other. Every area is ASCII today, so this
/// changes nothing now and stops the two ports disagreeing the day one is not.
public func feedbackAreaKey(_ area: String) -> String {
    let words = area.split(whereSeparator: { !$0.isASCII || !($0.isLetter || $0.isNumber) })
    return "area" + words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
}

/// The i18n key for a severity's on-screen label.
public func feedbackSeverityKey(_ severity: String) -> String {
    "sev" + severity.prefix(1).uppercased() + severity.dropFirst()
}

/**
 How much of the diagnostics log travels with a report.

 Web's `.slice(0, 20000)` — "a report is for diagnosing, not archiving a whole
 session", in its own words.
 */
public let feedbackDiagnosticsCap = 20000

/// The version stamped on a report. Web's `APP_VERSION` constant.
public let feedbackAppVersion = "0.1.0"

/// Web truncates the user-agent string to this before storing it.
public let feedbackUserAgentCap = 300
