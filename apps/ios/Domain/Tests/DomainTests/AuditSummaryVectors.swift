import Foundation
@testable import Domain

// Wires AuditSummary.swift into FunctionRegistry.
//
// Web's version is a React component (`AuditChanges`) reading a module-level
// object literal, so it cannot be imported and called from node — these vectors
// were transcribed from it and diffed against the component line by line. The
// one deliberate divergence they pin is the ORDER: web iterates the parsed
// object, this iterates the whitelist. See `auditFields`.

private func nullableString(_ v: Any?) -> String? {
    guard let v, !(v is NSNull) else { return nil }
    return v as? String
}

/// The JSON name for a kind. Spelled out rather than taken from `rawValue` so
/// the corpus keeps one spelling across both platforms — Kotlin's `name` is
/// SCREAMING_SNAKE and Swift's `rawValue` is camelCase, and neither is the other.
private func kindName(_ kind: AuditValueKind) -> String {
    switch kind {
    case .money: return "money"
    case .date: return "date"
    case .category: return "category"
    case .account: return "account"
    case .paymentMethod: return "paymentMethod"
    case .type: return "type"
    case .text: return "text"
    }
}

private func changeToJson(_ c: AuditChange) -> [String: Any] {
    [
        "field": c.field,
        "kind": kindName(c.kind),
        "from": c.from as Any? ?? NSNull(),
        "to": c.to as Any? ?? NSNull(),
    ]
}

func registerTransactionAuditVectors() {
    FunctionRegistry.register(domain: "transaction-audit", fn: "summarizeAuditChanges") { input in
        let d = input as! [String: Any]
        var parsed: [String: AuditFromTo]?
        if let raw = d["changes"] as? [String: Any] {
            var out: [String: AuditFromTo] = [:]
            for (field, value) in raw {
                let o = value as? [String: Any] ?? [:]
                out[field] = AuditFromTo(from: nullableString(o["from"]), to: nullableString(o["to"]))
            }
            parsed = out
        } else {
            parsed = nil
        }
        switch summarizeAuditChanges(parsed) {
        case .absent:
            return ["kind": "absent"] as [String: Any]
        case .minorUpdate:
            return ["kind": "minorUpdate"] as [String: Any]
        case .changes(let entries):
            return ["kind": "changes", "entries": entries.map(changeToJson)] as [String: Any]
        }
    }
}
