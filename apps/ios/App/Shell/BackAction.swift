import SwiftUI

/**
 A screen's own "go back", surfaced in the shell's utility row.

 **A screen gets at most one back affordance, and it is the util row's.** Web
 deleted every page-local "back to X" link to guarantee that, and native must
 not reintroduce them as navigation-bar buttons — which is exactly what three
 screens were doing before this existed.

 The screens that need it (Splits, Loans, Investments) hold their drill-down in
 their own state rather than in a route, so the shell cannot infer it. They say
 so instead, the same way they say what the "+" does.

 Registering `nil` — or leaving the screen — clears it, so a screen can never
 hand its Back to the next one.
 */
private struct BackActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct BackActionSetterKey: EnvironmentKey {
    static let defaultValue: ((() -> Void)?) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Read by the shell to decide whether the util row shows Back.
    var backAction: (() -> Void)? {
        get { self[BackActionKey.self] }
        set { self[BackActionKey.self] = newValue }
    }

    var backActionSetter: ((() -> Void)?) -> Void {
        get { self[BackActionSetterKey.self] }
        set { self[BackActionSetterKey.self] = newValue }
    }
}

extension View {
    /**
     Puts Back in the util row while `isActive`, running `action` when tapped.

     Takes a flag rather than an optional closure so the call site reads as the
     condition it is: `.registerBack(selectedLoanId != nil) { selectedLoanId = nil }`.
     */
    func registerBack(_ isActive: Bool, action: @escaping () -> Void) -> some View {
        modifier(RegisterBackAction(isActive: isActive, action: action))
    }
}

private struct RegisterBackAction: ViewModifier {
    @Environment(\.backActionSetter) private var setter
    let isActive: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { setter(isActive ? action : nil) }
            // The drill-down changes while the screen stays on screen, so
            // `onAppear` alone would show Back once and never take it away.
            .onChange(of: isActive) { _, active in setter(active ? action : nil) }
            .onDisappear { setter(nil) }
    }
}
