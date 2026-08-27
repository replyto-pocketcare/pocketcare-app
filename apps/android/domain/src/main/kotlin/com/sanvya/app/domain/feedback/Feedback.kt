package com.sanvya.app.domain.feedback

// GENERATED FILE — do not hand-edit.
// Source: apps/web/src/ui/BugReport.tsx (AREAS, SEVERITIES, APP_VERSION)
// Regenerate with: node tools/parity/generate-feedback.mjs

/**
 * The feedback form's vocabulary.
 *
 * [FEEDBACK_AREAS] and [FEEDBACK_SEVERITIES] are the values WRITTEN to
 * `bug_reports`, and they are web's English strings on purpose: they are
 * identifiers that happen to be readable, and a translated column is an
 * unsortable one. The label shown on screen is looked up in the `feedback`
 * i18n namespace by [feedbackAreaKey] / [feedbackSeverityKey].
 */

/** Web's own picker order, which is not alphabetical and is not incidental. */
val FEEDBACK_AREAS: List<String> = listOf(
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
)

/** Most severe first, as web lists them. */
val FEEDBACK_SEVERITIES: List<String> = listOf(
    "fatal",
    "high",
    "medium",
    "low",
)

/** The i18n key for an area's on-screen label. */
fun feedbackAreaKey(area: String): String = "area" + area
    .replace(Regex("[^A-Za-z0-9]+"), " ")
    .trim()
    .split(" ")
    .joinToString("") { it.replaceFirstChar { c -> c.uppercaseChar() } }

/** The i18n key for a severity's on-screen label. */
fun feedbackSeverityKey(severity: String): String =
    "sev" + severity.replaceFirstChar { it.uppercaseChar() }

/**
 * How much of the diagnostics log travels with a report.
 *
 * Web's `.slice(0, 20000)` — "a report is for diagnosing, not archiving a
 * whole session", in its own words.
 */
const val FEEDBACK_DIAGNOSTICS_CAP = 20000

/** The version stamped on a report. Web's `APP_VERSION` constant. */
const val FEEDBACK_APP_VERSION = "0.1.0"

/** Web truncates the user-agent string to this before storing it. */
const val FEEDBACK_USER_AGENT_CAP = 300
