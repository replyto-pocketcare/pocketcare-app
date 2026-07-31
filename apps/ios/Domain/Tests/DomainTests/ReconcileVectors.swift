import Foundation
@testable import Domain

// P1.6b: wires the real Reconcile.swift port into FunctionRegistry so
// reconcile.json's vectors un-skip. Row is a fully dynamic
// `Record<string, unknown>` in the TS source (unlike every earlier
// domain's fixed-shape inputs), so unlike ReceiptsVectors.swift this
// adapter has to do real dynamic JSON->RowValue conversion rather than
// pull named fields off a known shape. Mirrors Android's
// ReconcileVectors.kt.

/// True only for an NSNumber that's actually CFBoolean-backed -- same
/// check as VectorRunnerTests.swift's isBoolNSNumber, duplicated here
/// rather than shared because Swift's `private` is file-scoped (a real
/// bug caught during the receipts port, P1.5b: see ReceiptsMoneyText.swift).
/// This one is `fileprivate` rather than exported since nothing else in
/// this file's target needs it beyond this adapter.
private func isBoolNSNumber(_ n: NSNumber) -> Bool {
    CFGetTypeID(n) == CFBooleanGetTypeID()
}

/// Dynamic Any (from JSONSerialization) -> RowValue conversion. None of
/// reconcile.json's vectors exercise obj/arr/doubleNum row values (every
/// field is a string id/note or an integer amount), but these branches
/// are kept faithful to RowValue's full shape rather than narrowed to
/// just what's tested, mirroring Reconcile.swift's own "kept reasonably
/// faithful, not vector-verified" stance on its own unexercised branches.
private func asRowValue(_ any: Any) -> RowValue {
    if any is NSNull {
        return .null
    }
    if let s = any as? String {
        return .str(s)
    }
    if let n = any as? NSNumber {
        if isBoolNSNumber(n) {
            return .bool(n.boolValue)
        }
        let d = n.doubleValue
        if d == d.rounded(.towardZero) {
            return .intNum(n.int64Value)
        }
        return .doubleNum(d)
    }
    if let arr = any as? [Any] {
        return .arr(arr.map(asRowValue))
    }
    if let obj = any as? [String: Any] {
        return .obj(obj.mapValues(asRowValue))
    }
    fatalError("unsupported RowValue JSON value: \(any)")
}

private func asRow(_ any: Any) -> Row {
    let d = any as! [String: Any]
    var row: Row = [:]
    for (k, v) in d { row[k] = asRowValue(v) }
    return row
}

private func asChecksumOptions(_ any: Any?) -> ChecksumOptions {
    guard let d = any as? [String: Any] else { return ChecksumOptions() }
    let ignore = (d["ignore"] as? [Any])?.compactMap { $0 as? String } ?? []
    return ChecksumOptions(ignore: ignore)
}

private func driftReportToJson(_ r: DriftReport) -> [String: Any] {
    [
        "inSync": r.inSync,
        "missingRemote": r.missingRemote,
        "missingLocal": r.missingLocal,
        "mismatched": r.mismatched,
    ]
}

func registerReconcileVectors() {
    let domain = "reconcile"

    FunctionRegistry.register(domain: domain, fn: "rowChecksum") { input in
        let d = input as! [String: Any]
        let row = asRow(d["row"]!)
        let opts = asChecksumOptions(d["opts"])
        return rowChecksum(row, opts)
    }

    FunctionRegistry.register(domain: domain, fn: "checksum") { input in
        let d = input as! [String: Any]
        let rows = (d["rows"] as! [Any]).map(asRow)
        let opts = asChecksumOptions(d["opts"])
        return checksum(rows, opts)
    }

    FunctionRegistry.register(domain: domain, fn: "reconcile") { input in
        let d = input as! [String: Any]
        let local = (d["local"] as! [Any]).map(asRow)
        let remote = (d["remote"] as! [Any]).map(asRow)
        let opts = asChecksumOptions(d["opts"])
        return driftReportToJson(reconcile(local, remote, opts))
    }
}
