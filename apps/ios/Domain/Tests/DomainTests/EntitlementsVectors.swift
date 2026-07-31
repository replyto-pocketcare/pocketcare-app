import Foundation
@testable import Domain

// P1.7b: wires the real Entitlements.swift port into FunctionRegistry so
// entitlements.json's vectors un-skip. Mirrors Android's
// EntitlementsVectors.kt.

func registerEntitlementsVectors() {
    let domain = "entitlements"

    FunctionRegistry.register(domain: domain, fn: "canUse") { input in
        let d = input as! [String: Any]
        return canUse(d["feature"] as! String, d["tier"] as! String)
    }
    FunctionRegistry.register(domain: domain, fn: "isPremiumFeature") { input in
        let d = input as! [String: Any]
        return isPremiumFeature(d["feature"] as! String)
    }
}
