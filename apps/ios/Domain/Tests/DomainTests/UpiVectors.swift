import Foundation
@testable import Domain

// P1.6b: wires the real Upi.swift port into FunctionRegistry so upi.json's
// vectors un-skip. Mirrors Android's UpiVectors.kt.

private func builtIntentToJson(_ b: BuiltIntent) -> [String: Any] {
    ["url": b.url, "ref": b.ref]
}

/// UpiTarget's optional fields (name/amountMinor/note) are OPTIONAL TS
/// fields, omitted from the JSON entirely when absent (not emitted as
/// null) -- same convention as ReceiptDraft.rawText (P1.5). Vectors that
/// only carry a bare vpa expect a target object with JUST a "vpa" key, so
/// emitting the others as explicit NSNull() here would fail exact
/// key-set comparison. Mirrors UpiVectors.kt's identical reasoning.
private func upiTargetToJson(_ t: UpiTarget) -> [String: Any] {
    var out: [String: Any] = ["vpa": t.vpa]
    if let name = t.name { out["name"] = name }
    if let amountMinor = t.amountMinor { out["amountMinor"] = amountMinor }
    if let note = t.note { out["note"] = note }
    return out
}

/// UpiParseResult is a discriminated union in the TS source
/// (`{ok:true;target}|{ok:false;reason}`) -- the two branches have
/// DIFFERENT key sets, so (again mirroring the optional-field-omission
/// convention above) only one of "target"/"reason" is ever emitted,
/// matching whichever branch `ok` selects.
private func upiParseResultToJson(_ r: UpiParseResult) -> [String: Any] {
    var out: [String: Any] = ["ok": r.ok]
    if r.ok, let target = r.target {
        out["target"] = upiTargetToJson(target)
    } else if let reason = r.reason {
        out["reason"] = reason
    }
    return out
}

private func asIntentParams(_ any: Any) -> IntentParams {
    let d = any as! [String: Any]
    return IntentParams(
        vpa: d["vpa"] as! String,
        name: d["name"] as! String,
        amountMinor: (d["amountMinor"] as! NSNumber).doubleValue,
        note: d["note"] as? String,
        ref: d["ref"] as? String,
        currency: d["currency"] as? String
    )
}

func registerUpiVectors() {
    let domain = "upi"

    FunctionRegistry.register(domain: domain, fn: "isValidVpa") { input in
        let d = input as! [String: Any]
        return isValidVpa(d["value"] as! String)
    }
    FunctionRegistry.register(domain: domain, fn: "normalizeVpa") { input in
        let d = input as! [String: Any]
        return normalizeVpa(d["value"] as! String)
    }
    FunctionRegistry.register(domain: domain, fn: "maskVpa") { input in
        let d = input as! [String: Any]
        return maskVpa(d["value"] as! String)
    }
    FunctionRegistry.register(domain: domain, fn: "formatAmount") { input in
        let d = input as! [String: Any]
        return try formatAmount((d["minor"] as! NSNumber).doubleValue)
    }
    FunctionRegistry.register(domain: domain, fn: "newPaymentRef") { input in
        let d = input as! [String: Any]
        let seed = (d["seed"] as! NSNumber).int32Value
        return newPaymentRef(seededRandom(seed))
    }
    FunctionRegistry.register(domain: domain, fn: "isValidRef") { input in
        let d = input as! [String: Any]
        return isValidRef(d["ref"] as! String)
    }
    FunctionRegistry.register(domain: domain, fn: "buildIntentUrl") { input in
        builtIntentToJson(try buildIntentUrl(asIntentParams(input)))
    }
    FunctionRegistry.register(domain: domain, fn: "buildQrPayload") { input in
        builtIntentToJson(try buildQrPayload(asIntentParams(input)))
    }
    FunctionRegistry.register(domain: domain, fn: "canPayViaUpi") { input in
        let d = input as! [String: Any]
        return canPayViaUpi(
            currency: d["currency"] as! String,
            amountMinor: (d["amountMinor"] as! NSNumber).doubleValue,
            hasHandle: (d["hasHandle"] as! NSNumber).boolValue
        )
    }
    FunctionRegistry.register(domain: domain, fn: "parseUpiTarget") { input in
        let d = input as! [String: Any]
        return upiParseResultToJson(parseUpiTarget(d["input"] as? String))
    }
}
