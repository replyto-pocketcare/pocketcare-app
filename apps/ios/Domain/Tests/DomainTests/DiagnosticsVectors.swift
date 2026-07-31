import Foundation
@testable import Domain

// P1.6b: wires the real Diagnostics.swift port into FunctionRegistry so
// diagnostics.json's vectors un-skip. Mirrors Android's
// DiagnosticsVectors.kt, including the dynamic JSON<->DetailValue
// conversion (same shape of problem as ReconcileVectors.swift's Row
// conversion, P1.6b, same session).

private func isBoolNSNumber(_ n: NSNumber) -> Bool {
    CFGetTypeID(n) == CFBooleanGetTypeID()
}

private func asDetailValue(_ any: Any) -> DetailValue {
    if any is NSNull { return .null }
    if let s = any as? String { return .str(s) }
    if let n = any as? NSNumber {
        if isBoolNSNumber(n) { return .bool(n.boolValue) }
        let d = n.doubleValue
        if d == d.rounded(.towardZero) { return .intNum(n.int64Value) }
        return .doubleNum(d)
    }
    if let arr = any as? [Any] { return .arr(arr.map(asDetailValue)) }
    if let obj = any as? [String: Any] {
        // [String: Any] has no defined order -- fine for every current
        // vector (each has <=4 keys and the comparator is key-based, not
        // order-sensitive, for redactDetail's own equality check), but see
        // Diagnostics.swift's DetailValue.obj doc comment: this is a real,
        // if currently untested, gap for a value that round-trips through
        // formatLog's order-sensitive JSON.stringify rendering.
        return .obj(obj.map { DetailEntry(key: $0.key, value: asDetailValue($0.value)) })
    }
    fatalError("unsupported DetailValue JSON value: \(any)")
}

private func detailValueToJson(_ v: DetailValue) -> Any {
    switch v {
    case .null: return NSNull()
    case .str(let s): return s
    case .intNum(let n): return n
    case .doubleNum(let n): return n
    case .bool(let b): return b
    case .arr(let items): return items.map(detailValueToJson)
    case .obj(let entries):
        var out: [String: Any] = [:]
        for e in entries { out[e.key] = detailValueToJson(e.value) }
        return out
    }
}

private func asLogEntry(_ any: Any) -> LogEntry {
    let d = any as! [String: Any]
    let detailAny = d["detail"]
    return LogEntry(
        at: (d["at"] as! NSNumber).int64Value,
        level: d["level"] as! String,
        scope: d["scope"] as! String,
        message: d["message"] as! String,
        route: d["route"] as? String,
        detail: (detailAny != nil && !(detailAny is NSNull)) ? asDetailValue(detailAny!) : nil
    )
}

/// LogEntry.route/detail are OPTIONAL TS fields, omitted from the JSON
/// entirely when absent -- same convention as ReceiptDraft.rawText (P1.5)
/// and UpiTarget's optional fields (P1.6b, this session).
private func logEntryToJson(_ e: LogEntry) -> [String: Any] {
    var out: [String: Any] = [
        "at": e.at,
        "level": e.level,
        "scope": e.scope,
        "message": e.message,
    ]
    if let route = e.route { out["route"] = route }
    if let detail = e.detail { out["detail"] = detailValueToJson(detail) }
    return out
}

func registerDiagnosticsVectors() {
    let domain = "diagnostics"

    FunctionRegistry.register(domain: domain, fn: "redactSecrets") { input in
        let d = input as! [String: Any]
        return redactSecrets(d["input"] as! String)
    }
    FunctionRegistry.register(domain: domain, fn: "redactText") { input in
        let d = input as! [String: Any]
        return redactText(d["input"] as! String)
    }
    FunctionRegistry.register(domain: domain, fn: "redactDetail") { input in
        let d = input as! [String: Any]
        return detailValueToJson(redactDetail(asDetailValue(d["input"]!)))
    }
    FunctionRegistry.register(domain: domain, fn: "makeEntry") { input in
        let d = input as! [String: Any]
        let opts = d["opts"] as? [String: Any]
        let detailAny = opts?["detail"]
        let entry = makeEntry(
            level: d["level"] as! String,
            scope: d["scope"] as! String,
            message: d["message"] as! String,
            route: opts?["route"] as? String,
            detail: (detailAny != nil && !(detailAny is NSNull)) ? asDetailValue(detailAny!) : nil,
            at: (opts?["at"] as? NSNumber)?.int64Value
        )
        return logEntryToJson(entry)
    }
    FunctionRegistry.register(domain: domain, fn: "formatLog") { input in
        let d = input as! [String: Any]
        let entries = (d["entries"] as! [Any]).map(asLogEntry)
        let contextDict = (d["context"] as? [String: Any]) ?? [:]
        // Same order caveat as asDetailValue's object case: [String: Any]
        // has no defined order. No golden vector currently exercises more
        // than one context key, so this doesn't affect correctness today.
        let context: [(key: String, value: String?)] = contextDict.map { (key: $0.key, value: $0.value as? String) }
        return formatLog(entries, context)
    }
}
