import Foundation
@testable import Domain

// Wires Walkthrough.swift into FunctionRegistry.
//
// The whole truth table — 96 combinations — because the four guards exist to
// stop the dialog appearing at the wrong moment, and "does not appear" is the
// case nobody notices is broken until a returning user is told to set up from
// scratch.

func registerWalkthroughVectors() {
    FunctionRegistry.register(domain: "walkthrough", fn: "shouldShowWalkthrough") { input in
        let d = input as! [String: Any]
        func flag(_ key: String) -> Bool { (d[key] as! NSNumber).boolValue }
        return shouldShowWalkthrough(
            done: flag("done"),
            skipped: flag("skipped"),
            syncPending: flag("syncPending"),
            accountCountLoaded: flag("accountCountLoaded"),
            realAccountCount: (d["realAccountCount"] as! NSNumber).intValue,
            signedIn: flag("signedIn")
        )
    }

    FunctionRegistry.register(domain: "walkthrough", fn: "walkthroughProgress") { input in
        let d = input as! [String: Any]
        let p = walkthroughProgress((d["step"] as! NSNumber).intValue)
        return ["step": p.step, "of": p.of] as [String: Any]
    }
}
