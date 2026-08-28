import Foundation
@testable import Domain

// Wires CardCycle.swift into FunctionRegistry.
//
// A SPEC, not a capture: `cardDueDate` lives inside a page module in
// `apps/web/app/accounts/new/page.tsx` and cannot be imported. It was
// transcribed and the transcription was run.
//
// ONE fixture family deliberately does NOT match what a browser would produce.
// Web builds the due date as LOCAL midnight and stores
// `.toISOString().slice(0, 10)`, which is UTC — so every user east of
// Greenwich is given a due date one day EARLY. These fixtures carry the
// calendar date the user was actually shown. See CardCycle.swift.
//
// `clampCardDay` is the boring half and is here anyway: it is the only thing
// standing between a typed "31" and a due date of 31 February, and its
// `Number(v) || fallback` reads "0" as "unset", which is not obvious and is
// worth a fixture.

func registerCardCycleVectors() {
    let domain = "card-cycle"

    FunctionRegistry.register(domain: domain, fn: "cardDueDate") { input in
        let d = input as! [String: Any]
        let due = cardDueDate(
            createdIso: d["createdIso"] as! String,
            statementDay: (d["statementDay"] as! NSNumber).intValue,
            dueDay: (d["dueDay"] as! NSNumber).intValue
        )
        return ["dueOn": due.dueOn, "thisCycle": due.thisCycle]
    }

    FunctionRegistry.register(domain: domain, fn: "clampCardDay") { input in
        let d = input as! [String: Any]
        return clampCardDay(d["raw"] as! String, fallback: (d["fallback"] as! NSNumber).intValue)
    }
}
