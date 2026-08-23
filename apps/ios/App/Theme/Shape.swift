import SwiftUI

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

public enum SanvyaRadius {
    public static let radius: CGFloat = 22
    public static let radiusLg: CGFloat = 24
    public static let radiusSm: CGFloat = 12
    public static let row: CGFloat = 10
    public static let popover: CGFloat = 18
    public static let popoverItem: CGFloat = 12
    public static let checkbox: CGFloat = 6
}

public extension View {
    /// CSS `border-radius: 999px` — a capsule, not a very large radius.
    func sanvyaPill() -> some View { clipShape(Capsule()) }
}
