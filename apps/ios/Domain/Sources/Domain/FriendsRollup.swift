import Foundation

/**
 Who owes whom, across the whole ledger rather than per group.

 Ported from the three `useMemo`s at the top of `apps/web/app/friends/page.tsx`.
 It is here rather than in a screen because it is the answer to the question the
 Friends page exists to ask, and because both ports were getting it wrong in the
 same way: they read `overview.direct` ALONE, so somebody who owed you from a
 trip simply did not appear. `GroupOverview.perUser` was computed, returned, and
 never read.

 Mirrors Android's FriendsRollup.kt.
 */

/// One person's net position with you. Positive means they owe you.
public struct PersonNet: Equatable, Sendable {
    public let userId: String
    public let net: Int64

    public init(userId: String, net: Int64) {
        self.userId = userId
        self.net = net
    }
}

/**
 Every 1:1 balance — each group's per-user rollup plus the direct ones — summed
 into one net per person.

 ORDER IS FIRST-APPEARANCE, not sorted: web accumulates into a `Map` and spreads
 it, and a JS Map iterates in insertion order. The two callers below sort;
 anything that does not, inherits this order, so it has to be the same order on
 both platforms — which is why this walks an array of keys rather than
 iterating a Swift Dictionary, whose order is arbitrary.

 Zero nets are dropped, as web does: a settled person is not a debt.
 */
public func friendNets(groupPerUser: [[PersonNet]], direct: [PersonNet]) -> [PersonNet] {
    var order: [String] = []
    var totals: [String: Int64] = [:]
    func add(_ b: PersonNet) {
        if totals[b.userId] == nil { order.append(b.userId) }
        totals[b.userId, default: 0] += b.net
    }
    for group in groupPerUser { for b in group { add(b) } }
    for d in direct { add(d) }
    return order.compactMap { id in
        guard let net = totals[id], net != 0 else { return nil }
        return PersonNet(userId: id, net: net)
    }
}

/// They owe you — largest first.
public func owedToYou(_ nets: [PersonNet]) -> [PersonNet] {
    nets.filter { $0.net > 0 }.sorted { $0.net > $1.net }
}

/**
 You owe them — largest DEBT first.

 Web sorts ascending on a negative number, which puts the biggest debt at the
 top. Sorting by absolute value descending would read the same here and be wrong
 the moment a zero slipped through, so this keeps web's comparison.
 */
public func youOwe(_ nets: [PersonNet]) -> [PersonNet] {
    nets.filter { $0.net < 0 }.sorted { $0.net < $1.net }
}

/**
 Everyone you share a group with, INCLUDING the people you are square with.

 The two lists above drop a settled person by construction. A "Friends"
 directory that only lists debts is a debt list; web's own comment says so, and
 this is the function that makes it a directory.

 Sorted by the SIZE of the balance, then by name — so the people you have
 something outstanding with float to the top and the rest stay alphabetical.
 */
public func everyoneYouShareWith(
    groupMemberIds: [[String]],
    direct: [PersonNet],
    nets: [PersonNet],
    names: [String: String]
) -> [PersonNet] {
    var netByUser: [String: Int64] = [:]
    for n in nets { netByUser[n.userId] = n.net }

    var seen = Set<String>()
    var ids: [String] = []
    for group in groupMemberIds {
        for id in group where seen.insert(id).inserted { ids.append(id) }
    }
    for d in direct where seen.insert(d.userId).inserted { ids.append(d.userId) }

    return ids
        .map { PersonNet(userId: $0, net: netByUser[$0] ?? 0) }
        .sorted { a, b in
            let (x, y) = (abs(a.net), abs(b.net))
            if x != y { return x > y }
            return (names[a.userId] ?? a.userId) < (names[b.userId] ?? b.userId)
        }
}
