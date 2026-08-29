import Foundation
@testable import Domain

// Wires ItemBreakdown.swift into FunctionRegistry.
//
// These vectors were TRANSCRIBED, not recorded: web's version of this
// arithmetic lives inside a React component (`ItemBreakdown.tsx`) and cannot be
// imported and run from node. The transcription was diffed against that
// component line by line — in particular the two orderings it inherits from JS
// Map insertion order, which the last vector pins deliberately.

private func optionalString(_ any: Any?) -> String? {
    guard let any, !(any is NSNull) else { return nil }
    return any as? String
}

private func items(_ arr: [Any]) -> [ItemBreakdownItem] {
    arr.map { entry in
        let o = entry as! [String: Any]
        return ItemBreakdownItem(
            id: o["id"] as! String,
            amount: (o["amount"] as! NSNumber).int64Value
        )
    }
}

private func shares(_ arr: [Any]) -> [ItemBreakdownShare] {
    arr.map { entry in
        let o = entry as! [String: Any]
        return ItemBreakdownShare(
            itemId: o["itemId"] as! String,
            userId: o["userId"] as! String,
            shareAmount: (o["shareAmount"] as! NSNumber).int64Value
        )
    }
}

private func lineToJson(_ line: ItemBreakdownLine) -> [String: Any] {
    [
        "itemId": line.itemId,
        "amount": line.amount,
        "shares": line.shares.map { ["userId": $0.userId, "amount": $0.amount] as [String: Any] },
    ]
}

func registerSplitsItemBreakdownVectors() {
    FunctionRegistry.register(domain: "splits-item-breakdown", fn: "itemBreakdown") { input in
        let d = input as! [String: Any]
        let view = itemBreakdown(
            items: items(d["items"] as! [Any]),
            shares: shares(d["shares"] as! [Any]),
            filterUserId: optionalString(d["filterUserId"])
        )
        return [
            "everyone": view.everyone,
            "lines": view.lines.map(lineToJson),
            "total": view.total,
        ] as [String: Any]
    }
}
