import Foundation

/// Locale-aware labels for the ISO date strings the database stores.
///
/// Was private inside `TileViews.swift` until the notification inbox needed the
/// same formatting — a second copy is the re-inlining the audit's component
/// inventory exists to prevent. Mirrors Android's `DateLabels.kt`.
///
/// Every one of these builds the words with the DEVICE's locale. Web hardcodes
/// English month names in `buildTrend` and mixes in a localised
/// `toLocaleDateString()` elsewhere; neither is something to copy into two
/// otherwise translated apps.

/// "12 Aug" — web's `toLocaleDateString(undefined, { month: "short", day: "numeric" })`.
func dayMonthLabel(_ iso: String) -> String { isoLabel(iso, "d MMM") }

/// "23/08/2026" — web's bare `toLocaleDateString()`, the numeric short form.
///
/// `dateStyle = .short` rather than a template: the ORDER of day, month and year
/// is what varies by locale, and a template string picks one order for everybody.
func shortDateLabel(_ iso: String) -> String {
    let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return iso }
    var components = DateComponents()
    components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let date = calendar.date(from: components) else { return iso }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

/// Formats the date part of an ISO string, or returns it unchanged if it is not
/// one. `prefix(10)` because a stored timestamp may carry a time component.
///
/// The date is read in UTC deliberately: these strings are civil dates the
/// database stores as `YYYY-MM-DD`, and reading them in the device's zone would
/// shift a date across midnight for anyone west of Greenwich.
func isoLabel(_ iso: String, _ template: String) -> String {
    let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return iso }
    var components = DateComponents()
    components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let date = calendar.date(from: components) else { return iso }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
}
