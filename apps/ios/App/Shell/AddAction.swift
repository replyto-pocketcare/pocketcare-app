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
        var tab: NavTab?
        /// Shows a lock rather than a tier name — see `defaultAddAction`.
        var locked: Bool = false
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
        label: "Add",
        items: [
            AddAction.Item(id: "transaction", label: "Add transaction", glyph: SanvyaIcons.add, tab: .transactions),
            AddAction.Item(id: "receipt", label: "Scan bill / receipt", glyph: SanvyaIcons.receipt, tab: nil, locked: !canScan),
        ]
    )
}

/// Set by the shell; screens register through `registerAddAction`.
private struct AddActionSetterKey: EnvironmentKey {
    static let defaultValue: (AddAction?) -> Void = { _ in }
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
