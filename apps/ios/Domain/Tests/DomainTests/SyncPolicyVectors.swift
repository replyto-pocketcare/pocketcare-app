import Foundation
@testable import Domain

// P1.6b: wires the real SyncPolicy.swift port into FunctionRegistry so
// sync-policy.json's vectors un-skip. Mirrors Android's
// SyncPolicyVectors.kt.

private func asFailureInput(_ any: Any) -> FailureInput {
    let d = any as! [String: Any]
    return FailureInput(
        status: (d["status"] as? NSNumber)?.intValue,
        code: d["code"] as? String,
        message: d["message"] as? String
    )
}

private func asClassification(_ any: Any) -> Classification {
    let d = any as! [String: Any]
    return Classification(cls: d["cls"] as! String, reason: d["reason"] as! String)
}

private func classificationToJson(_ c: Classification) -> [String: Any] {
    ["cls": c.cls, "reason": c.reason]
}

func registerSyncPolicyVectors() {
    let domain = "sync-policy"

    // The vector JSON's "input" field IS the FailureInput object directly
    // (no extra field-name wrapper) -- confirmed by reading
    // sync-policy.json: {"fn":"classifyFailure","input":{"status":401}}.
    FunctionRegistry.register(domain: domain, fn: "classifyFailure") { input in
        classificationToJson(classifyFailure(asFailureInput(input)))
    }

    FunctionRegistry.register(domain: domain, fn: "shouldQuarantine") { input in
        let d = input as! [String: Any]
        let c = asClassification(d["c"]!)
        let attempts = (d["attempts"] as! NSNumber).intValue
        return shouldQuarantine(c, attempts)
    }

    FunctionRegistry.register(domain: domain, fn: "backoffMs") { input in
        let d = input as! [String: Any]
        let attempts = (d["attempts"] as! NSNumber).intValue
        let base = (d["base"] as? NSNumber)?.intValue ?? 1000
        let ceiling = (d["ceiling"] as? NSNumber)?.intValue ?? 60_000
        return backoffMs(attempts, base: base, ceiling: ceiling)
    }

    FunctionRegistry.register(domain: domain, fn: "explainForUser") { input in
        explainForUser(asFailureInput(input))
    }
}
