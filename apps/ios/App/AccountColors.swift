import SwiftUI

/// ACCOUNT_COLORS + colorForId, ported byte-for-byte from
/// apps/web/src/colors.ts. Deliberately distinct from the earthy design
/// tokens in Theme.swift -- includes jewel tones (indigo/violet/denim) --
/// used only for per-account chip coloring.
///
/// Extracted 2026-08-05 (was inlined in DashboardView.swift; the Accounts
/// screen needs the same palette -- see docs/mobile/screen-specs/accounts.md
/// "Shared: colorForId" and the Phase B checklist's "component reuse, no
/// inline re-implementation" rule).
let accountColors: [Color] = [
    Color(red: 0x3E / 255, green: 0x4A / 255, blue: 0x38 / 255),
    Color(red: 0x5F / 255, green: 0x66 / 255, blue: 0x47 / 255),
    Color(red: 0x6B / 255, green: 0x7A / 255, blue: 0x4F / 255),
    Color(red: 0x9C / 255, green: 0xAE / 255, blue: 0x8E / 255),
    Color(red: 0xB0 / 255, green: 0x6A / 255, blue: 0x4F / 255),
    Color(red: 0xC9 / 255, green: 0x8A / 255, blue: 0x72 / 255),
    Color(red: 0xA8 / 255, green: 0x50 / 255, blue: 0x3A / 255),
    Color(red: 0x7C / 255, green: 0x4A / 255, blue: 0x3A / 255),
    Color(red: 0x5F / 255, green: 0x46 / 255, blue: 0x36 / 255),
    Color(red: 0xC9 / 255, green: 0xB7 / 255, blue: 0x9C / 255),
    Color(red: 0xC0 / 255, green: 0x8A / 255, blue: 0x3E / 255),
    Color(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255),
    Color(red: 0x6D / 255, green: 0x5A / 255, blue: 0xCF / 255),
    Color(red: 0x3F / 255, green: 0x5A / 255, blue: 0x8A / 255),
    Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0x6A / 255),
    Color(red: 0x7A / 255, green: 0x4A / 255, blue: 0x6B / 255),
    Color(red: 0x4B / 255, green: 0x55 / 255, blue: 0x63 / 255),
    Color(red: 0x2B / 255, green: 0x27 / 255, blue: 0x23 / 255),
]

func colorForId(_ id: String?) -> Color {
    guard let id, !id.isEmpty else { return Color(red: 0x7C / 255, green: 0x72 / 255, blue: 0x64 / 255) }
    var h: UInt32 = 0
    for scalar in id.unicodeScalars {
        h = h &* 31 &+ scalar.value
    }
    return accountColors[Int(h % UInt32(accountColors.count))]
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
