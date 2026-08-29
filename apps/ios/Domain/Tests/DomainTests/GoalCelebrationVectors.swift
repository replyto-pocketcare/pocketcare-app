import Foundation
@testable import Domain

// Wires GoalCelebration.swift's goalCelebration() into FunctionRegistry.
//
// Vectors as SPEC, like dashboard-trend.json: web's version is a `useEffect`
// over a ref and localStorage, so there is nothing to record FROM. What is
// pinned is the truth table -- above all that a NIL `wasFunded` (the first
// observation of a goal) seeds without celebrating, which is the one rule a
// hand-written port gets wrong in a way no screenshot would reveal.
//
// The persisted set is carried as a SORTED array on both sides of the call: a
// Set has no order, and comparing an unordered structure against JSON would
// make the corpus pass or fail on hash iteration order.
//
// `wasFunded` arrives as NSNull for a JSON null, and `as? Bool` on NSNull is
// nil -- which is exactly the tri-state the function takes.

func registerGoalCelebrationVectors() {
    FunctionRegistry.register(domain: "goal-celebration", fn: "goalCelebration") { input in
        let d = input as! [String: Any]
        let decision = goalCelebration(
            goalId: d["goalId"] as! String,
            wasFunded: d["wasFunded"] as? Bool,
            funded: d["funded"] as! Bool,
            celebrated: Set((d["celebrated"] as! [Any]).map { $0 as! String })
        )
        return ["celebrate": decision.celebrate, "celebrated": decision.celebrated.sorted()] as [String: Any]
    }
}
