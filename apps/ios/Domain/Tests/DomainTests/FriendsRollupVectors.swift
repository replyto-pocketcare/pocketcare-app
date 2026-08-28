import Foundation
@testable import Domain

// Wires FriendsRollup.swift into FunctionRegistry.
//
// A SPEC, not a capture: the rules live in three `useMemo`s inside a React
// component and cannot be imported. They were transcribed and the
// transcription was run.
//
// Money travels as STRINGS, per the corpus rule.
//
// The fixtures that matter are the ones both ports were getting wrong: a
// balance that exists ONLY inside a group. Reading `direct` alone — which is
// what SplitsViewModel did on both platforms — returns an empty list for the
// first four cases here.
//
// ORDER is asserted, not incidental. `friendNets` returns FIRST-APPEARANCE
// order because web spreads a JS Map, and `everyoneYouShareWith` sorts by the
// SIZE of the balance and then by NAME — the two-group fixture pins both, and
// the all-square fixture pins that a settled person is still listed at all.

private func people(_ raw: Any?) -> [PersonNet] {
    ((raw as? [Any]) ?? []).map { entry in
        let d = entry as! [String: Any]
        return PersonNet(userId: d["userId"] as! String, net: Int64(d["net"] as! String)!)
    }
}

private func groupsOfPeople(_ raw: Any?) -> [[PersonNet]] {
    ((raw as? [Any]) ?? []).map { people($0) }
}

private func idGroups(_ raw: Any?) -> [[String]] {
    ((raw as? [Any]) ?? []).map { group in ((group as? [Any]) ?? []).map { $0 as! String } }
}

private func emit(_ list: [PersonNet]) -> Any {
    list.map { ["userId": $0.userId, "net": String($0.net)] as [String: Any] }
}

func registerFriendsRollupVectors() {
    let domain = "splits-rollup"

    FunctionRegistry.register(domain: domain, fn: "friendNets") { input in
        let d = input as! [String: Any]
        return emit(friendNets(groupPerUser: groupsOfPeople(d["groupPerUser"]), direct: people(d["direct"])))
    }
    FunctionRegistry.register(domain: domain, fn: "owedToYou") { input in
        emit(owedToYou(people((input as! [String: Any])["nets"])))
    }
    FunctionRegistry.register(domain: domain, fn: "youOwe") { input in
        emit(youOwe(people((input as! [String: Any])["nets"])))
    }
    FunctionRegistry.register(domain: domain, fn: "everyoneYouShareWith") { input in
        let d = input as! [String: Any]
        return emit(
            everyoneYouShareWith(
                groupMemberIds: idGroups(d["groupMemberIds"]),
                direct: people(d["direct"]),
                nets: people(d["nets"]),
                names: ((d["names"] as? [String: Any]) ?? [:]).mapValues { $0 as! String }
            )
        )
    }
}
