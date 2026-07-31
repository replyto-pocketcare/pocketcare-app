import Foundation
@testable import Domain

// P1.4b: wires the real SplitsMath.swift port into FunctionRegistry so
// splits-math.json's vectors un-skip. Registered under
// (domain="splits-math", fn="pairwiseEdges") to match
// tools/golden-vectors/vectors/splits-math.json exactly.

private func asParty(_ any: Any) -> Party {
    let d = any as! [String: Any]
    return Party(userId: d["userId"] as! String, share: (d["share"] as! NSNumber).int64Value, paid: (d["paid"] as! NSNumber).int64Value)
}

private func splitEdgeToJson(_ e: SplitEdge) -> [String: Any] {
    ["userId": e.userId, "amount": e.amount]
}

func registerSplitsMathVectors() {
    FunctionRegistry.register(domain: "splits-math", fn: "pairwiseEdges") { input in
        let d = input as! [String: Any]
        let parties = (d["parties"] as! [Any]).map(asParty)
        let selfId = d["selfId"] as! String
        return pairwiseEdges(parties, selfId).map(splitEdgeToJson)
    }
}
