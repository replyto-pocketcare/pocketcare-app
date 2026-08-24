import SwiftUI

/**
 Text at a design-system style.

 Screens go through these rather than `.font(.system(size: 18))`, for the same
 reason web has `h2` and `.eyebrow` instead of inline styles: when the scale
 moves, it moves in the CSS and regenerates into `SanvyaType`.
 */

public struct SanvyaH1: View {
    private let text: String
    private let compact: Bool
    /// Phones sit below web's 860px breakpoint, where `h1` is 22, not 26.
    public init(_ text: String, compact: Bool = true) {
        self.text = text
        self.compact = compact
    }
    public var body: some View {
        Text(text)
            .sanvyaStyle(compact ? SanvyaType.h1Compact : SanvyaType.h1)
            .foregroundStyle(Color.text)
            .accessibilityAddTraits(.isHeader)
    }
}

public struct SanvyaH2: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .sanvyaStyle(SanvyaType.h2)
            .foregroundStyle(Color.text)
            .accessibilityAddTraits(.isHeader)
    }
}

/**
 `.eyebrow` — the uppercase, tracked section label.

 Uppercasing happens here, not in the string catalog: web does it with
 `text-transform`, so the stored translation stays sentence case and a locale
 where uppercasing is wrong or lossy can opt out in one place.
 */
public struct SanvyaEyebrow: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .sanvyaStyle(SanvyaType.eyebrow)
            .foregroundStyle(Color.text3)
    }
}

/// `.muted` — secondary body copy.
public struct SanvyaMuted: View {
    private let text: String
    private let style: SanvyaTextStyle
    public init(_ text: String, style: SanvyaTextStyle = SanvyaType.body) {
        self.text = text
        self.style = style
    }
    public var body: some View {
        Text(text)
            .sanvyaStyle(style)
            .foregroundStyle(Color.text2)
    }
}
