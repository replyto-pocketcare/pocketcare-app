import Foundation

/**
 When a newly-entered credit-card statement balance is actually payable.

 Ported from the `cardDueDate` helper at the top of
 `apps/web/app/accounts/new/page.tsx`. It is three lines of month arithmetic
 with two off-by-one traps in it, it decides a date the user is told to pay
 money on, and it was duplicated nowhere — which is exactly the shape of thing
 that belongs in Domain under vectors rather than inside a screen.

 The rule: a statement closes on `statementDay`. If the card is entered on or
 before that day the balance belongs to the CURRENT cycle; enter it after and
 the statement has already closed, so it rolls to the next one. The due day may
 itself fall in the month after the statement — a card that closes on the 25th
 and is due on the 5th is due in the FOLLOWING month, which is the second `+ 1`
 below.

 Mirrors Android's CardCycle.kt.
 */

/// Web's `{ dueOn, thisCycle }`, with the date as a plain `yyyy-MM-dd`.
public struct CardDue: Equatable, Sendable {
    public let dueOn: String
    /// False when the balance rolled into the next statement. Web uses it only
    /// to choose which of two preview sentences to show — the amount is stored
    /// either way, and the rolled case is expressed by the DATE, not by a zero.
    public let thisCycle: Bool

    public init(dueOn: String, thisCycle: Bool) {
        self.dueOn = dueOn
        self.thisCycle = thisCycle
    }
}

/**
 Web's `Math.min(28, Math.max(1, Number(v) || fallback))`.

 28 rather than 31 so the day exists in February; the clamp is web's and the
 ceiling is not negotiable, because a due date of 31 February is not a date.
 An unparseable field falls back rather than refusing — `Number("") || 1` is 1,
 and web relies on that for the empty box.
 */
public func clampCardDay(_ raw: String, fallback: Int) -> Int {
    let n = jsNumber(raw)
    let v = (n.isNaN || n == 0) ? Double(fallback) : n
    return min(28, max(1, Int(v)))
}

/**
 The due date for a balance entered on `createdIso` (a `yyyy-MM-dd` day).

 **One deliberate divergence from web, and it is a real bug there.** Web builds
 `new Date(year, dueMonth, dueDay)` — LOCAL midnight — and then stores
 `.toISOString().slice(0, 10)`, which is UTC. Every user east of Greenwich
 therefore gets a due date one day EARLY: in IST, local midnight on the 20th is
 18:30 UTC on the 19th. This computes the calendar date and keeps it, so the day
 the user was shown is the day that is stored. A vector pins the difference.
 */
public func cardDueDate(createdIso: String, statementDay: Int, dueDay: Int) -> CardDue {
    let parts = String(createdIso.prefix(10)).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return CardDue(dueOn: String(createdIso.prefix(10)), thisCycle: true) }
    let (year, month, day) = (parts[0], parts[1], parts[2])

    // Rolled to the next statement? Web compares the day of month, inclusive.
    let billMonthOffset = day <= statementDay ? 0 : 1
    // A due day BEFORE the statement day lands in the month after it.
    let dueMonthOffset = billMonthOffset + (dueDay >= statementDay ? 0 : 1)

    // Plain integer month arithmetic on a 0-based month, then back to 1-based.
    // No Calendar and no Date: the answer is a calendar date, and routing it
    // through an instant is exactly the step that gives web the wrong day.
    let zeroBased = (month - 1) + dueMonthOffset
    let dueYear = year + zeroBased / 12
    let dueMonth = zeroBased % 12 + 1
    let dd = String(format: "%04d-%02d-%02d", dueYear, dueMonth, dueDay)
    return CardDue(dueOn: dd, thisCycle: billMonthOffset == 0)
}
