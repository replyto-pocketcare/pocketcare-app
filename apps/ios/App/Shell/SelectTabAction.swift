import SwiftUI

/**
 Navigate to another top-level destination from anywhere inside the shell.

 **Why this exists.** Web routes with a router, so any component can call
 `router.push("/cards")`. Native holds the current destination in the shell's
 own state, which a screen — and especially a SHEET presented by a screen —
 cannot reach. The first place that hurt was New account: web sends you to
 Cards after you add a credit card and to Investments after a demat, because
 that is where the thing you just made actually lives. Without this, the sheet
 dismissed and left you on Accounts, where a credit card does not appear.

 It is deliberately the same shape as `backActionSetter` and `addActionSetter`:
 the shell injects the real implementation, and a view rendered outside one
 (previews, tests) gets a no-op rather than a crash.

 Mirrors what Android gets for free from `NavController`.
 */
private struct SelectTabActionKey: EnvironmentKey {
    // `nonisolated(unsafe)` is load-bearing and honest — same reasoning as
    // BackAction.swift's: a closure type is never Sendable, and what is stored
    // here is a `let` holding a closure that captures nothing and does nothing.
    nonisolated(unsafe) static let defaultValue: (NavTab) -> Void = { _ in }
}

extension EnvironmentValues {
    var selectTab: (NavTab) -> Void {
        get { self[SelectTabActionKey.self] }
        set { self[SelectTabActionKey.self] = newValue }
    }
}
