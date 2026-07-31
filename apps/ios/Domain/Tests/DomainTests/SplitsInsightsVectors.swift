import Foundation
@testable import Domain

// P1.4b: wires the real SplitsInsights.swift port into FunctionRegistry so
// splits-insights.json's vectors un-skip. Registered under
// (domain="splits-insights", fn=<name>) to match
// tools/golden-vectors/vectors/splits-insights.json exactly -- mirrors the
// Android adapter (SplitsInsightsVectors.kt) field-for-field.

private func asDebtLike(_ any: Any) -> DebtLike {
    let d = any as! [String: Any]
    return DebtLike(at: d["at"] as! String, amount: (d["amount"] as! NSNumber).int64Value)
}

private func asPaymentLike(_ any: Any) -> PaymentLike {
    let d = any as! [String: Any]
    return PaymentLike(at: d["at"] as! String, amount: (d["amount"] as! NSNumber).int64Value)
}

private func asFriendEdge(_ any: Any) -> FriendEdge {
    let d = any as! [String: Any]
    return FriendEdge(
        friendId: d["friendId"] as! String,
        groupId: d["groupId"] as! String,
        at: d["at"] as! String,
        amount: (d["amount"] as! NSNumber).int64Value
    )
}

private func asFriendSettlement(_ any: Any) -> FriendSettlement {
    let d = any as! [String: Any]
    return FriendSettlement(friendId: d["friendId"] as! String, at: d["at"] as! String, amount: (d["amount"] as! NSNumber).int64Value)
}

private func asFriendStats(_ any: Any) -> FriendStats {
    let d = any as! [String: Any]
    return FriendStats(
        friendId: d["friendId"] as! String,
        net: (d["net"] as! NSNumber).int64Value,
        youCovered: (d["youCovered"] as! NSNumber).int64Value,
        theyCovered: (d["theyCovered"] as! NSNumber).int64Value,
        lent: (d["lent"] as! NSNumber).int64Value,
        borrowed: (d["borrowed"] as! NSNumber).int64Value,
        groups: (d["groups"] as! NSNumber).intValue,
        groupsOwing: (d["groupsOwing"] as! NSNumber).intValue,
        groupsOwed: (d["groupsOwed"] as! NSNumber).intValue,
        expenses: (d["expenses"] as! NSNumber).intValue,
        avgSettleDays: (d["avgSettleDays"] as? NSNumber)?.doubleValue,
        settledDebts: (d["settledDebts"] as! NSNumber).intValue
    )
}

private func averageSettleResultToJson(_ r: AverageSettleResult) -> [String: Any] {
    ["avgDays": r.avgDays.map { jsonNumber($0) } ?? NSNull(), "clearedCount": r.clearedCount]
}

private func friendStatsToJson(_ s: FriendStats) -> [String: Any] {
    [
        "friendId": s.friendId,
        "net": s.net,
        "youCovered": s.youCovered,
        "theyCovered": s.theyCovered,
        "lent": s.lent,
        "borrowed": s.borrowed,
        "groups": s.groups,
        "groupsOwing": s.groupsOwing,
        "groupsOwed": s.groupsOwed,
        "expenses": s.expenses,
        "avgSettleDays": s.avgSettleDays.map { jsonNumber($0) } ?? NSNull(),
        "settledDebts": s.settledDebts,
    ]
}

private func friendInsightToJson(_ i: FriendInsight) -> [String: Any] {
    ["key": i.key, "friendId": i.friendId, "value": jsonNumber(i.value), "evidence": i.evidence]
}

// The same fixture edges/settlements export.ts's pickFriendInsights vector
// reuses from its own computeFriendStats vector -- that vector's
// input.stats field is just the descriptive placeholder string
// "computeFriendStats(edges,settlements) above", not real data, so this
// adapter reconstructs the identical fixture (read directly off
// tools/golden-vectors/export.ts's splits-insights section, not guessed),
// mirroring SplitsInsightsVectors.kt.
private let fixtureEdges = [
    FriendEdge(friendId: "f1", groupId: "g1", at: "2026-01-01T00:00:00Z", amount: 500),
    FriendEdge(friendId: "f1", groupId: "g1", at: "2026-01-10T00:00:00Z", amount: 300),
    FriendEdge(friendId: "f2", groupId: "g2", at: "2026-01-05T00:00:00Z", amount: -200),
]
private let fixtureSettlements = [
    FriendSettlement(friendId: "f1", at: "2026-01-15T00:00:00Z", amount: 500),
]

func registerSplitsInsightsVectors() {
    FunctionRegistry.register(domain: "splits-insights", fn: "averageSettleDays") { input in
        let d = input as! [String: Any]
        let debts = (d["debts"] as! [Any]).map(asDebtLike)
        let payments = (d["payments"] as! [Any]).map(asPaymentLike)
        return averageSettleResultToJson(averageSettleDays(debts, payments))
    }

    FunctionRegistry.register(domain: "splits-insights", fn: "computeFriendStats") { input in
        let d = input as! [String: Any]
        let edges = (d["edges"] as! [Any]).map(asFriendEdge)
        let settlements = (d["settlements"] as! [Any]).map(asFriendSettlement)
        return computeFriendStats(edges, settlements).map(friendStatsToJson)
    }

    FunctionRegistry.register(domain: "splits-insights", fn: "pickFriendInsights") { input in
        let d = input as! [String: Any]
        let statsField = d["stats"]
        let stats: [FriendStats]
        if let statsArray = statsField as? [Any] {
            stats = statsArray.map(asFriendStats)
        } else {
            stats = computeFriendStats(fixtureEdges, fixtureSettlements)
        }
        return pickFriendInsights(stats).map(friendInsightToJson)
    }
}
