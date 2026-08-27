import Foundation
@testable import Domain

// Wires SplitAssign.swift into FunctionRegistry.
//
// The interesting half is validateSplitLine: it decides whether a bill may be
// written at all, and "off by one minor unit" has to mean the same thing on all
// three clients. The discount cases matter most — an exact split of a NEGATIVE
// line is the one place the sign rule is load-bearing.

private func splitAssignLine(_ any: Any) -> ReceiptLine {
    let d = any as! [String: Any]
    return ReceiptLine(
        id: d["id"] as! String,
        kind: d["kind"] as! String,
        description: d["description"] as! String,
        quantity: (d["quantity"] as? NSNumber)?.int64Value,
        unit: d["unit"] as? String,
        unitPrice: (d["unitPrice"] as? NSNumber)?.int64Value,
        amount: (d["amount"] as! NSNumber).int64Value,
        confidence: (d["confidence"] as! NSNumber).intValue
    )
}

private func problemToJson(_ p: LineProblem?) -> Any {
    guard let p else { return NSNull() }
    switch p {
    case .needsSomeone:
        return ["kind": "needsSomeone"] as [String: Any]
    case .exactMismatch(let diffMinor):
        return ["kind": "exactMismatch", "diffMinor": diffMinor] as [String: Any]
    case .percentMismatch(let pct):
        return ["kind": "percentMismatch", "pct": pct] as [String: Any]
    case .quantityMismatch(let gotMilli, let wantMilli):
        return ["kind": "quantityMismatch", "gotMilli": gotMilli, "wantMilli": wantMilli] as [String: Any]
    }
}

func registerSplitAssignVectors() {
    let domain = "split-assign"

    FunctionRegistry.register(domain: domain, fn: "receiptDigits") { input in
        let d = input as! [String: Any]
        return receiptDigits(d["currency"] as! String)
    }

    FunctionRegistry.register(domain: domain, fn: "minorFromText") { input in
        let d = input as! [String: Any]
        return minorFromText(d["value"] as! String, (d["digits"] as! NSNumber).intValue)
    }

    FunctionRegistry.register(domain: domain, fn: "majorTextFromMinor") { input in
        let d = input as! [String: Any]
        return majorTextFromMinor((d["minor"] as! NSNumber).int64Value, (d["digits"] as! NSNumber).intValue)
    }

    FunctionRegistry.register(domain: domain, fn: "qtyToMajor") { input in
        let d = input as! [String: Any]
        return qtyToMajor((d["milli"] as! NSNumber).int64Value)
    }

    FunctionRegistry.register(domain: domain, fn: "splitModesFor") { input in
        let d = input as! [String: Any]
        return splitModesFor(splitAssignLine(d["line"]!))
    }

    FunctionRegistry.register(domain: domain, fn: "lineWeight") { input in
        let d = input as! [String: Any]
        let w = lineWeight(
            mode: d["mode"] as! String,
            raw: d["raw"] as? String,
            lineAmount: (d["lineAmount"] as! NSNumber).int64Value,
            digits: (d["digits"] as! NSNumber).intValue
        )
        return w as Any? ?? NSNull()
    }

    FunctionRegistry.register(domain: domain, fn: "validateSplitLine") { input in
        let d = input as! [String: Any]
        let weights = (d["weights"] as! [String: Any]).compactMapValues { $0 as? String }
        return problemToJson(validateSplitLine(
            line: splitAssignLine(d["line"]!),
            mode: d["mode"] as! String,
            members: d["members"] as! [String],
            weights: weights,
            digits: (d["digits"] as! NSNumber).intValue
        ))
    }
}
