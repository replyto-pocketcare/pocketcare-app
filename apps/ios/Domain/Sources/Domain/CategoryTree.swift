import Foundation

/// The Manage-categories tree, ported from apps/web/app/settings/categories/page.tsx.
///
/// Web computes this inline in its render. It is branchy enough that two
/// platforms would drift on it — three of the four branches only appear while
/// something is typed in the search box — so it lives here with vectors.
/// Mirrors apps/android/domain/.../taxonomy/CategoryTree.kt.

/// One `categories` row, as the taxonomy screen reads it.
public struct TaxonomyCategory: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let parentId: String?

    public init(id: String, name: String, kind: String, parentId: String?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.parentId = parentId
    }
}

/// One top-level row plus the children that should be drawn under it.
public struct CategoryTreeNode: Equatable, Sendable, Identifiable {
    public let category: TaxonomyCategory
    /// ALL children, for the "· N" badge — not just the visible ones.
    public let childCount: Int
    public let isOpen: Bool
    public let children: [TaxonomyCategory]

    public var id: String { category.id }
}

/// Web's four rules, in web's order:
///
/// 1. A parent is hidden entirely when a search matches neither it nor any of
///    its children.
/// 2. While searching, every surviving parent is FORCED open — otherwise a
///    match inside a collapsed parent would be invisible and the search would
///    look broken.
/// 3. A parent that matches the search itself shows all its children, not just
///    the matching ones: you searched for the group, so you get the group.
/// 4. A parent that does NOT match but has matching children shows only those.
///
/// `search` is compared case-insensitively, as a substring, and an
/// all-whitespace search is a real search — web tests `!search`, so only the
/// empty string turns filtering off. Copied deliberately; trimming here would
/// make the two platforms disagree with the browser about a space.
public func categoryTree(
    _ categories: [TaxonomyCategory],
    search: String,
    expanded: Set<String>
) -> [CategoryTreeNode] {
    let needle = search.lowercased()
    let searching = !search.isEmpty
    func matches(_ name: String) -> Bool {
        !searching || name.lowercased().contains(needle)
    }

    var childrenByParent: [String: [TaxonomyCategory]] = [:]
    for category in categories {
        guard let parentId = category.parentId else { continue }
        childrenByParent[parentId, default: []].append(category)
    }

    return categories.filter { $0.parentId == nil }.compactMap { parent in
        let kids = childrenByParent[parent.id] ?? []
        let parentMatch = matches(parent.name)
        let matchingKids = kids.filter { matches($0.name) }
        if searching && !parentMatch && matchingKids.isEmpty { return nil }
        return CategoryTreeNode(
            category: parent,
            childCount: kids.count,
            isOpen: searching ? true : expanded.contains(parent.id),
            children: (searching && !parentMatch) ? matchingKids : kids
        )
    }
}
