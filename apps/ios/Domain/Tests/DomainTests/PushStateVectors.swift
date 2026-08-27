import Foundation
@testable import Domain

// Wires PushState.swift into FunctionRegistry.
//
// The whole cross-product of the three inputs, because the one that matters —
// blocked vs off — looks identical on screen and only one of them can be fixed
// by tapping the switch.

func registerPushStateVectors() {
    let domain = "push-state"

    FunctionRegistry.register(domain: domain, fn: "pushState") { input in
        let d = input as! [String: Any]
        return pushState(
            supported: (d["supported"] as! NSNumber).boolValue,
            permission: d["permission"] as! String,
            prefEnabled: (d["prefEnabled"] as! NSNumber).boolValue
        ).rawValue
    }

    FunctionRegistry.register(domain: domain, fn: "shouldRegisterAtLaunch") { input in
        let d = input as! [String: Any]
        return shouldRegisterAtLaunch(
            permission: d["permission"] as! String,
            prefEnabled: (d["prefEnabled"] as! NSNumber).boolValue
        )
    }
}
