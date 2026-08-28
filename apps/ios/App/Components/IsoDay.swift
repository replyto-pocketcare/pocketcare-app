import Foundation

/**
 The app's one `yyyy-MM-dd` converter.

 Every date COLUMN in the schema stores a calendar day in this shape, and every
 Domain function that compares dates (`autoSplitGroupFor`, `cardDueDate`, the
 budget window) compares these strings directly. So the format is not a display
 choice -- it is the wire format, and it must not vary.

 Two things here are load-bearing and were wrong in four of the six hand-rolled
 copies this replaces:

 `en_US_POSIX` pins the calendar to Gregorian. Without it a device set to the
 Japanese or Buddhist calendar formats `yyyy` in THAT era -- a start date of
 "0008-08-23" or "2569-08-23" -- and the row is silently unmatchable.

 The conversion is LOCAL, not UTC. The question a date column answers is "which
 calendar day was this for the person", so an 00:30 expense on the 3rd is the
 3rd. `ISO8601DateFormatter` answers a different question and moves the day
 across a trip or budget boundary for every user east of Greenwich.

 Built per call: `DateFormatter` is not `Sendable`, so a shared instance cannot
 cross an actor boundary.
 */
public enum IsoDay {
    /// The local calendar day of `date`, as `yyyy-MM-dd`.
    public static func string(from date: Date) -> String {
        formatter().string(from: date)
    }

    /// Today's local calendar day, as `yyyy-MM-dd`.
    public static func today() -> String {
        string(from: Date())
    }

    /// Parses a `yyyy-MM-dd` day back to a `Date` at local midnight.
    /// `nil` for anything that is not in the format.
    public static func date(from iso: String) -> Date? {
        formatter().date(from: iso)
    }

    private static func formatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }
}
