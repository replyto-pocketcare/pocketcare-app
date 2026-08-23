import SwiftUI

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 One layer of a CSS box-shadow. SwiftUI's `.shadow` takes radius, not blur:
 CSS blur is roughly 2x SwiftUI's radius, so `swiftUIRadius` does that
 conversion in one place rather than at every call site. `spread` has no
 SwiftUI equivalent and is carried through for the component layer.
 */
public struct SanvyaShadowLayer: Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let blur: CGFloat
    public let spread: CGFloat
    public let color: Color

    public var swiftUIRadius: CGFloat { blur / 2 }
}

public struct SanvyaShadow: Sendable {
    public let layers: [SanvyaShadowLayer]
}

public enum SanvyaShadows {
    public static func shadow(dark: Bool) -> SanvyaShadow {
        dark
            ? SanvyaShadow(layers: [
                SanvyaShadowLayer(x: 0, y: 1, blur: 2, spread: 0, color: Color(.sRGB, red: 0.0000, green: 0.0000, blue: 0.0000, opacity: 0.3000)),
                SanvyaShadowLayer(x: 0, y: 8, blur: 24, spread: -12, color: Color(.sRGB, red: 0.0000, green: 0.0000, blue: 0.0000, opacity: 0.5000)),
            ])
            : SanvyaShadow(layers: [
                SanvyaShadowLayer(x: 0, y: 1, blur: 2, spread: 0, color: Color(.sRGB, red: 0.1686, green: 0.1529, blue: 0.1373, opacity: 0.0400)),
                SanvyaShadowLayer(x: 0, y: 12, blur: 30, spread: -20, color: Color(.sRGB, red: 0.1686, green: 0.1529, blue: 0.1373, opacity: 0.1600)),
            ])
    }

    public static func shadowLg(dark: Bool) -> SanvyaShadow {
        dark
            ? SanvyaShadow(layers: [
                SanvyaShadowLayer(x: 0, y: 24, blur: 60, spread: -20, color: Color(.sRGB, red: 0.0000, green: 0.0000, blue: 0.0000, opacity: 0.6000)),
            ])
            : SanvyaShadow(layers: [
                SanvyaShadowLayer(x: 0, y: 22, blur: 48, spread: -22, color: Color(.sRGB, red: 0.1686, green: 0.1529, blue: 0.1373, opacity: 0.3200)),
            ])
    }

    public static func shadowAccent(dark: Bool) -> SanvyaShadow {
        dark
            ? SanvyaShadow(layers: [
                SanvyaShadowLayer(x: 0, y: 10, blur: 24, spread: -12, color: Color(.sRGB, red: 0.6902, green: 0.4157, blue: 0.3098, opacity: 0.9000)),
            ])
            : SanvyaShadow(layers: [
                SanvyaShadowLayer(x: 0, y: 10, blur: 24, spread: -12, color: Color(.sRGB, red: 0.6902, green: 0.4157, blue: 0.3098, opacity: 0.9000)),
            ])
    }
}

public extension View {
    /// Applies every layer of a CSS shadow, outermost last — the same paint
    /// order the browser uses.
    func sanvyaShadow(_ shadow: SanvyaShadow) -> some View {
        shadow.layers.reduce(AnyView(self)) { view, layer in
            AnyView(view.shadow(color: layer.color, radius: layer.swiftUIRadius, x: layer.x, y: layer.y))
        }
    }
}
