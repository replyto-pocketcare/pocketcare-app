import SwiftUI
import UIKit
import CoreText

/**
 The app's typefaces. Hand-written (not generated) because it touches UIKit
 font descriptors, which have no equivalent on the other platforms.

 **Inter is bundled as a VARIABLE font, deliberately.** `globals.css` uses
 font-weight 550 (`.trx-title`, `.pc-seg-btn`) and 650 (`h2`,
 `.side-nav-item.active`). SwiftUI's `Font.Weight` has no value for either, and
 `.weight()` on a custom font asks the system to *synthesise* a heavier face
 rather than interpolate the real one — which looks smeared next to the web
 app. Setting the `wght` variation axis directly gives the true outline.
 */
public enum SanvyaFont {
    /// `name` table ID 1 of the bundled InterVariable.ttf.
    public static let family = "Inter"
    /// The Material Symbols subset — see `SanvyaIcons`.
    public static let iconFamily = "Material Symbols Rounded"

    /// OpenType axis tag 'wght' as its four-character code.
    private static let weightAxis = 0x77676874

    private static let variationKey =
        UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)

    /// A Dynamic-Type-scaling Inter at an exact CSS weight.
    public static func font(size: CGFloat, cssWeight: Int, relativeTo textStyle: Font.TextStyle) -> Font {
        Font(uiFont(size: size, cssWeight: cssWeight, relativeTo: textStyle))
    }

    public static func uiFont(size: CGFloat, cssWeight: Int, relativeTo textStyle: Font.TextStyle) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            variationKey: [weightAxis: cssWeight],
        ])
        let base = UIFont(descriptor: descriptor, size: size)
        // Scales with the user's text-size setting — the accessibility
        // behaviour web gets for free from browser zoom.
        return UIFontMetrics(forTextStyle: uiTextStyle(textStyle)).scaledFont(for: base)
    }

    /// Icons are sized absolutely, not scaled: they sit inside fixed-size
    /// containers (nav items, 40pt utility buttons) that Dynamic Type does not
    /// resize, so growing the glyph alone would overflow them. Web behaves the
    /// same way — `.msym` takes an explicit pixel size.
    public static func icon(size: CGFloat) -> Font {
        .custom(iconFamily, fixedSize: size)
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}
