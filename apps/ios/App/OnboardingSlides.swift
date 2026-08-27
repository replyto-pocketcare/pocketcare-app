import SwiftUI

// GENERATED FILE - do not hand-edit.
// Source: apps/web/app/onboarding/page.tsx (SLIDES)
// Regenerate with: node tools/parity/generate-onboarding-slides.mjs

/// The pre-auth onboarding deck's visual identity, exactly as web writes it.
/// 
/// Glyph and gradient only: each slide's title and body are i18n keys
/// (onboarding:slides.N.title / .body) and arrive through the generated
/// strings, so this file has no copy in it and needs no translation.
/// 
/// The gradient stops are stored as the #rrggbb strings web writes and
/// converted by the platform's own hex parser -- the one every account and
/// chart colour already goes through. A second colour constructor here would
/// be a second place for #RGB shorthand or a bad digit to behave differently.
public struct OnboardingSlide: Identifiable, Equatable, Sendable {
    public let id: Int
    public let glyph: String
    public let gradientStartHex: String
    public let gradientEndHex: String

    /// A gray fallback on a malformed stop rather than a crash -- the same rule
    /// accountColor(explicit:id:) uses, reading a free-form database column.
    public var gradientStart: Color { Color(hex: gradientStartHex) ?? .gray }
    public var gradientEnd: Color { Color(hex: gradientEndHex) ?? .gray }
}

public enum OnboardingSlides {
    /// Every slide's title, in order, resolved through the generated strings.
    ///
    /// Emitted rather than hand-written because S.Onboarding's accessors are
    /// flat (slides0Title, slides1Title, ...) with no way to index them: a
    /// hand-written switch would be the one place an eighth slide gets
    /// forgotten. The generator has already failed if a key is missing.
    public static var titles: [String] {
        [
            S.Onboarding.slides0Title,
            S.Onboarding.slides1Title,
            S.Onboarding.slides2Title,
            S.Onboarding.slides3Title,
            S.Onboarding.slides4Title,
            S.Onboarding.slides5Title,
            S.Onboarding.slides6Title,
        ]
    }

    public static var bodies: [String] {
        [
            S.Onboarding.slides0Body,
            S.Onboarding.slides1Body,
            S.Onboarding.slides2Body,
            S.Onboarding.slides3Body,
            S.Onboarding.slides4Body,
            S.Onboarding.slides5Body,
            S.Onboarding.slides6Body,
        ]
    }

    public static let slides: [OnboardingSlide] = [
        OnboardingSlide(id: 0, glyph: "\u{2764}", gradientStartHex: "#b06a4f", gradientEndHex: "#8f533c"),
        OnboardingSlide(id: 1, glyph: "\u{2302}", gradientStartHex: "#3e4a38", gradientEndHex: "#2f6f6a"),
        OnboardingSlide(id: 2, glyph: "\u{21C5}", gradientStartHex: "#7a4a6b", gradientEndHex: "#4f3a54"),
        OnboardingSlide(id: 3, glyph: "\u{25D4}", gradientStartHex: "#c08a3e", gradientEndHex: "#a8503a"),
        OnboardingSlide(id: 4, glyph: "\u{21CC}", gradientStartHex: "#b06a4f", gradientEndHex: "#5f6647"),
        OnboardingSlide(id: 5, glyph: "\u{25CE}", gradientStartHex: "#2f6f6a", gradientEndHex: "#3e4a38"),
        OnboardingSlide(id: 6, glyph: "\u{2726}", gradientStartHex: "#7c4a3a", gradientEndHex: "#b06a4f"),
    ]
}
