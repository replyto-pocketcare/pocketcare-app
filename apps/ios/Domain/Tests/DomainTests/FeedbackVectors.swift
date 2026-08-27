import Foundation
@testable import Domain

// Wires Feedback.swift's key derivation into FunctionRegistry.
//
// The expectations are hand-written from web's own AREAS list, because web has
// no such function to run: it renders the raw English into its picker. That is
// exactly why these vectors exist. The two sides of this port must agree on the
// mapping from a STORED value ("Accounts & Cards", which goes into the column
// and must not be translated) to an i18n KEY (`areaAccountsCards`, which is
// what the user reads) — and the derivation is string surgery, which is where
// Swift and Kotlin are most likely to differ quietly.
//
// The whole point is caught by two cases: "Accounts & Cards" (an ampersand
// surrounded by spaces, so a naive camel-case leaves a stray capital) and
// "Sync / Offline" (a slash, likewise).

func registerFeedbackVectors() {
    FunctionRegistry.register(domain: "feedback", fn: "feedbackAreaKey") { input in
        let d = input as! [String: Any]
        return feedbackAreaKey(d["area"] as! String)
    }

    FunctionRegistry.register(domain: "feedback", fn: "feedbackSeverityKey") { input in
        let d = input as! [String: Any]
        return feedbackSeverityKey(d["severity"] as! String)
    }
}
