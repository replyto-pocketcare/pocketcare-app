import SwiftUI

/**
 Per-account chip colours, derived from the generated palette.

 Deliberately distinct from the earthy design tokens in Theme.swift — this
 includes jewel tones (indigo/violet/denim) and is used only for colouring one
 account against another.

 The palette itself is NOT declared here. It lives once, in
 `packages/core/catalog`, and reaches this target as `FormOptions.accountColors`
 — hex strings, because hex is what gets written to `accounts.color` and all
 three apps must agree on the string. This file only converts.
 */
// Parsing goes through the validated `Color(hex:)` below rather than a second
// scanner — the catalog's values are known-good, but a private duplicate that
// skipped validation would be the third hex parser in this app.
private func paletteColor(_ hex: String) -> Color { Color(hex: hex) ?? .gray }

let accountColors: [Color] = FormOptions.accountColors.map(paletteColor)

private let fallbackAccountColor = paletteColor(FormOptions.fallbackAccountColor)

/**
 A stable colour for an account with none set.

 Delegates to the generated `colorForId` rather than re-deriving the hash: this
 has to agree with web and Android about a colour the user has already seen.
 */
func colorForId(_ id: String?) -> Color {
    guard let id, !id.isEmpty else { return fallbackAccountColor }
    return paletteColor(FormOptions.colorForId(id))
}


func accountColor(explicit: String?, id: String) -> Color {
    if let explicit, !explicit.isEmpty, let parsed = Color(hex: explicit) {
        return parsed
    }
    return colorForId(id)
}

extension Color {
    /// Parses a "#RRGGBB" hex string (account.color as stored). Returns nil
    /// on any malformed input so callers can fall back to colorForId.
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
