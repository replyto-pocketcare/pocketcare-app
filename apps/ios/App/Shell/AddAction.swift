import SwiftUI

/**
 The bottom bar's "+" is contextual: each screen decides what it does.

 Mirrors `apps/web/src/ui/AddAction.tsx`. The three shapes matter — a screen
 with one sensible add action fires immediately, and only a screen with a
 genuine choice opens a menu. A popover-for-everything version would feel
 slower on every screen in the app.
 */
enum AddAction: Equatable {
    case link(label: String, tab: NavTab)
    case button(label: String, id: String)
    case menu(label: String, items: [Item])

    struct Item: Identifiable, Equatable {
        let id: String
        let label: String
        let glyph: String
        /// Where this item goes, as a NavTab. Mutually exclusive with `flow`.
        var tab: NavTab?
        /**
         A form this item opens, for the destinations that are not tabs.

         Web's two default items are `href: "/transactions/new"` and
         `href: "/receipts/new"` — real routes. This shell has no route for
         either: both are presented forms owned by whatever screen is showing.
         Carrying only a `tab` meant "Scan bill / receipt" selected `nil` and
         **did nothing at all**, while "Add transaction" opened the transactions
         LIST rather than the form. One dead control and one wrong one, from the
         same missing case.
         */
        var flow: Flow?
        /// Shows a lock rather than a tier name — see `defaultAddAction`.
        var locked: Bool = false
    }

    /// A destination the shell presents rather than navigates to.
    enum Flow: String, Equatable {
        case newTransaction
        case scanReceipt
    }

    var label: String {
        switch self {
        case let .link(label, _): return label
        case let .button(label, _): return label
        case let .menu(label, _): return label
        }
    }
}

/**
 What the "+" does on a screen that has registered nothing.

 A transaction — or a scanned receipt, which becomes one — is the thing that is
 always relevant in a money app. Receipt scanning shows a **lock**, not a tier
 name: the plans are Lite and Pro, so naming one would be either wrong or only
 half the answer.
 */
func defaultAddAction(canScan: Bool) -> AddAction {
    .menu(
        label: S.Translation.commonAdd,
        items: [
            AddAction.Item(id: "transaction", label: S.Translation.fabAddTransaction, glyph: SanvyaIcons.add, flow: .newTransaction),
            AddAction.Item(id: "receipt", label: S.Translation.fabScanReceipt, glyph: SanvyaIcons.receipt, flow: .scanReceipt, locked: !canScan),
        ]
    )
}

/// Set by the shell; screens register through `registerAddAction`.
private struct AddActionSetterKey: EnvironmentKey {
    // `nonisolated(unsafe)` is load-bearing and honest. Swift 6 flags any
    // static property whose type is not Sendable, and a closure type never is.
    // What is actually stored here is a `let` holding a closure that captures
    // nothing and does nothing, so there is no shared mutable state to race on
    // — the compiler simply has no way to express that. The real setter is
    // injected by the shell per-view through the environment; this is only the
    // no-op fallback for a view rendered outside it (previews, tests).
    nonisolated(unsafe) static let defaultValue: (AddAction?) -> Void = { _ in }
}

extension EnvironmentValues {
    var addActionSetter: (AddAction?) -> Void {
        get { self[AddActionSetterKey.self] }
        set { self[AddActionSetterKey.self] = newValue }
    }
}

extension View {
    /// Registers this screen's add action while it is on screen, and clears it
    /// on the way out so the next screen does not inherit it.
    func registerAddAction(_ action: AddAction) -> some View {
        modifier(RegisterAddAction(action: action))
    }
}

private struct RegisterAddAction: ViewModifier {
    @Environment(\.addActionSetter) private var setter
    let action: AddAction

    func body(content: Content) -> some View {
        content
            .onAppear { setter(action) }
            .onDisappear { setter(nil) }
    }
}
