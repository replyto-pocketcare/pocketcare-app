import Foundation

/// The Help page's search, ported from apps/web/app/help/page.tsx's `useMemo`.
///
/// An item matches when the needle appears anywhere in its question OR its
/// answer — web concatenates the two with a space before testing, so a needle
/// spanning the join ("Sanvya? An") matches there and matches here. Preserved
/// rather than corrected: it is invisible in practice and diverging over it
/// would be worse than the quirk.
///
/// A section with no surviving items is dropped entirely; a blank query returns
/// everything untouched.
///
/// Mirrors apps/android/domain/.../help/HelpSearch.kt.
public func filterHelp(_ sections: [HelpSection], query: String) -> [HelpSection] {
    // `trimmed` here where the taxonomy screens deliberately do NOT: web trims
    // this one (`query.trim().toLowerCase()`) and does not trim those.
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if needle.isEmpty { return sections }
    return sections.compactMap { section in
        let items = section.items.filter {
            ($0.question + " " + $0.answer).lowercased().contains(needle)
        }
        return items.isEmpty
            ? nil
            : HelpSection(icon: section.icon, color: section.color, title: section.title, items: items)
    }
}
