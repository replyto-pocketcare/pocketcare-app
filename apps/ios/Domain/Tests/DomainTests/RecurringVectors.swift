import Foundation
@testable import Domain

// Wires Recurring.swift's advance() into FunctionRegistry so
// recurring-advance.json's 23 vectors run instead of being skipped.
// Mirrors apps/android/domain/src/test/.../recurring/RecurringVectors.kt.
//
// The vectors existed before any implementation did -- they were re-pinned to
// CLAMPING semantics on 2026-08-23 after web's setMonth() overflow was found
// (Jan 31 -> Mar 3 -> Apr 3, skipping February and then sticking on the 3rd).
// Nothing consumed them until now, which meant the decision was recorded and
// unenforced.

func registerRecurringAdvanceVectors() {
    FunctionRegistry.register(domain: "recurring-advance", fn: "advance") { input in
        let d = input as! [String: Any]
        return try advance(
            d["date"] as! String,
            // The raw column value, through the same forgiving parse the engine
            // uses -- not a pre-validated enum. If fromDb() ever stopped
            // recognising "monthly", these vectors should fail.
            d["frequency"] as? String,
            (d["n"] as! NSNumber).intValue
        )
    }
}
