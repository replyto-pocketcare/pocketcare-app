import Foundation
@testable import Domain

// Wires SyncNotice.swift into FunctionRegistry.
//
// Hand-written rather than generated: web's `syncMessage()` returns English
// COPY, and the ports return a decision the screen then translates, so there is
// no single JS value to diff against. What the corpus pins instead is the
// classification — which errors are swallowed as a network wobble and which
// reach the user — because that is the part with a wrong answer in both
// directions (a swallowed schema error is silent data loss; a surfaced
// websocket blip is a strip nobody reads).

/// Absent and `NSNull` both mean "no error".
private func optionalString(_ value: Any?) -> String? {
    guard let value, !(value is NSNull) else { return nil }
    return value as? String
}

func registerSyncStatusVectors() {
    FunctionRegistry.register(domain: "sync-status", fn: "syncNotice") { input in
        let d = input as! [String: Any]
        let notice = syncNotice(
            online: (d["online"] as! NSNumber).boolValue,
            error: optionalString(d["error"])
        )
        // Raw values, so the corpus reads as web's own tone strings rather than
        // as Swift case names.
        return notice.rawValue
    }

    FunctionRegistry.register(domain: "sync-status", fn: "isTransientSyncError") { input in
        let d = input as! [String: Any]
        return isTransientSyncError(optionalString(d["error"]))
    }
}
