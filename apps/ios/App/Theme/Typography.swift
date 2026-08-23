import SwiftUI

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

/**
 Type scale. Sizes go through `relativeTo:` so Dynamic Type scales them (the
 accessibility behaviour web gets from browser zoom); tracking is converted
 from CSS `em` to points at the style's own size, which is what `em` means.

 Weight is carried as the raw CSS number, not a `Font.Weight`: the design uses
 550 and 650, which have no SwiftUI constant. `SanvyaFont` resolves them on
 Inter's variable `wght` axis instead of rounding to the nearest constant.
 */
public enum SanvyaType {
    public static let h1 = SanvyaTextStyle(
        size: 26,
        cssWeight: 700,
        trackingEm: -0.02,
        uppercase: false,
        relativeTo: .largeTitle
    )

    public static let h1Compact = SanvyaTextStyle(
        size: 22,
        cssWeight: 700,
        trackingEm: -0.02,
        uppercase: false,
        relativeTo: .title
    )

    public static let h2 = SanvyaTextStyle(
        size: 18,
        cssWeight: 650,
        trackingEm: -0.01,
        uppercase: false,
        relativeTo: .title3
    )

    public static let eyebrow = SanvyaTextStyle(
        size: 11,
        cssWeight: 600,
        trackingEm: 0.09,
        uppercase: true,
        relativeTo: .caption2
    )

    public static let body = SanvyaTextStyle(
        size: 15,
        cssWeight: 400,
        trackingEm: 0,
        uppercase: false,
        relativeTo: .body
    )

    public static let chip = SanvyaTextStyle(
        size: 14,
        cssWeight: 400,
        trackingEm: 0,
        uppercase: false,
        relativeTo: .subheadline
    )

    public static let button = SanvyaTextStyle(
        size: 15,
        cssWeight: 600,
        trackingEm: 0,
        uppercase: false,
        relativeTo: .body
    )

    public static let navLabel = SanvyaTextStyle(
        size: 10,
        cssWeight: 600,
        trackingEm: 0,
        uppercase: false,
        relativeTo: .caption2
    )

    public static let statValue = SanvyaTextStyle(
        size: 26,
        cssWeight: 700,
        trackingEm: -0.02,
        uppercase: false,
        relativeTo: .largeTitle
    )

    public static let statLabel = SanvyaTextStyle(
        size: 13,
        cssWeight: 600,
        trackingEm: 0,
        uppercase: false,
        relativeTo: .subheadline
    )

    public static let sectionTitle = SanvyaTextStyle(
        size: 10.5,
        cssWeight: 600,
        trackingEm: 0.07,
        uppercase: true,
        relativeTo: .caption2
    )
}

public struct SanvyaTextStyle: Sendable {
    public let size: CGFloat
    public let cssWeight: Int
    public let trackingEm: CGFloat
    public let uppercase: Bool
    public let relativeTo: Font.TextStyle

    public var font: Font {
        SanvyaFont.font(size: size, cssWeight: cssWeight, relativeTo: relativeTo)
    }

    /// CSS letter-spacing is in `em` — a fraction of the font size.
    public var tracking: CGFloat { trackingEm * size }
}

public extension Text {
    func sanvyaStyle(_ s: SanvyaTextStyle) -> Text {
        font(s.font).tracking(s.tracking)
    }
}

public extension View {
    func sanvyaStyle(_ s: SanvyaTextStyle) -> some View {
        font(s.font).tracking(s.tracking)
    }
}
