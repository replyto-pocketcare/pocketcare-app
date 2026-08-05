import SwiftUI

/// Ported byte-for-byte from apps/web/src/ui/TransactionTile.tsx's
/// avatarColor/merchantTitle/txTags -- the shared row logic used everywhere
/// a transaction is listed on web. Kept in its own file per the Phase B
/// "component reuse" rule, mirrors Android's TransactionTileLogic.kt (added
/// the same session).

private let avatarColors: [Color] = [
    Color(red: 0xB0 / 255, green: 0x6A / 255, blue: 0x4F / 255),
    Color(red: 0x5F / 255, green: 0x7A / 255, blue: 0x52 / 255),
    Color(red: 0xC0 / 255, green: 0x8A / 255, blue: 0x3E / 255),
    Color(red: 0x7A / 255, green: 0x4A / 255, blue: 0x6B / 255),
    Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0x6A / 255),
    Color(red: 0x7C / 255, green: 0x4A / 255, blue: 0x3A / 255),
    Color(red: 0x9C / 255, green: 0xAE / 255, blue: 0x8E / 255),
]

/// Deterministic per-string color -- matches
/// `[...s].reduce((a,c) => a + c.charCodeAt(0), 0) % AV.length`.
func avatarColor(_ s: String) -> Color {
    guard !s.isEmpty else { return avatarColors[0] }
    let sum = s.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return avatarColors[sum % avatarColors.count]
}

private let narrationPrefix = try! NSRegularExpression(pattern: "^(upi|imps|neft|ach|bil|inft|rtgs|nach|pos)$", options: .caseInsensitive)
private let hasLetters = try! NSRegularExpression(pattern: "[a-z]{3,}", options: .caseInsensitive)
private let allDigits = try! NSRegularExpression(pattern: "^\\d+$")

private func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
    regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
}

/// "UPI/ASHISH ALA/1234/Payment" -> "ASHISH ALA". Falls back to the raw
/// string (capped at 40 chars). Matches merchantTitle() exactly.
func merchantTitle(_ desc: String) -> String {
    let parts = desc.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    if parts.count >= 2, matches(narrationPrefix, parts[0]) {
        let name = parts.dropFirst().first { matches(hasLetters, $0) && !matches(allDigits, $0) }
        return String((name ?? parts[1]).prefix(34))
    }
    return String(desc.prefix(40))
}

struct TxTag: Hashable { let icon: String; let text: String }

/// Category first (skipped if "Uncategorised" and there are labels), then
/// each label. Matches txTags() exactly.
func txTags(_ categoryName: String?, _ labels: [String]?) -> [TxTag] {
    var out: [TxTag] = []
    let names = (labels ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    if let categoryName, !(names.count > 0 && categoryName.caseInsensitiveCompare("uncategorised") == .orderedSame) {
        out.append(TxTag(icon: "category", text: categoryName))
    }
    for n in names { out.append(TxTag(icon: "label", text: n)) }
    return out
}
