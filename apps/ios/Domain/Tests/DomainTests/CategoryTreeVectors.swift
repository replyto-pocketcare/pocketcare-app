import Foundation
@testable import Domain

// Wires CategoryTree.swift into FunctionRegistry.
//
// The logic lives inside a React component on web and cannot be imported, so
// these vectors were generated from a transcription of that render, diffed
// against it line by line. The expected value is ids only — the rows themselves
// are echoed back unchanged, so comparing them would double the fixture and
// test nothing.

private func optionalString(_ any: Any?) -> String? {
    guard let any, !(any is NSNull) else { return nil }
    return any as? String
}

func registerCategoryTreeVectors() {
    FunctionRegistry.register(domain: "category-tree", fn: "categoryTree") { input in
        let d = input as! [String: Any]
        let categories = (d["categories"] as! [Any]).map { entry -> TaxonomyCategory in
            let c = entry as! [String: Any]
            return TaxonomyCategory(
                id: c["id"] as! String,
                name: c["name"] as! String,
                kind: c["kind"] as! String,
                parentId: optionalString(c["parentId"])
            )
        }
        let search = d["search"] as! String
        let expanded = Set((d["expanded"] as! [Any]).map { $0 as! String })
        return categoryTree(categories, search: search, expanded: expanded).map { node in
            [
                "id": node.category.id,
                "childCount": node.childCount,
                "isOpen": node.isOpen,
                "children": node.children.map(\.id),
            ] as [String: Any]
        }
    }
}
