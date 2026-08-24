import SwiftUI

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

public enum SanvyaMotion {
    /// Web's `cubic-bezier(0.2, 0, 0, 1)`, used for essentially every
    /// meaningful transition in globals.css.
    public static func standard(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0, 0, 1, duration: duration)
    }

    public static let pressScale: CGFloat = 0.97
    public static let pressDuration: Double = 0.12

    public static let liftPressScale: CGFloat = 0.985
    public static let liftPressDuration: Double = 0.08

    public static let pageInDuration: Double = 0.34
    public static let pageInTranslateY: CGFloat = 10

    public static let fadeUpDuration: Double = 0.4
    public static let fadeUpTranslateY: CGFloat = 8

    public static let shimmerDuration: Double = 1.4
    public static let colorFadeDuration: Double = 0.15
}
