import Foundation
@testable import Domain

// Wires Categorize.swift into FunctionRegistry.
//
// Every `expected` was produced by RUNNING web's real normalize.ts and seeds.ts
// against the same nineteen bank-statement descriptions — UPI strings, POS
// dumps, NEFT lines, a mangled "swiggylimited", an accented merchant, a bare
// reference number.
//
// The ORDER of `tokens` is part of the expectation, not incidental: it decides
// which category is scored first, and `scoreTokens` breaks a tie by keeping the
// first. A hash-ordered set on either platform would make an equal-score tie a
// coin flip that differs between phones and between runs.

private func asCategories(_ any: Any) -> [CategoryData] {
    (any as! [Any]).map { row in
        let d = row as! [String: Any]
        return CategoryData(id: d["id"] as! String, name: d["name"] as! String)
    }
}

private func asRules(_ any: Any) -> [CategoryRule] {
    (any as! [Any]).map { row in
        let d = row as! [String: Any]
        return CategoryRule(
            kind: d["kind"] as! String,
            key: d["key"] as! String,
            categoryId: d["categoryId"] as! String,
            weight: (d["weight"] as! NSNumber).int64Value,
            corrections: (d["corrections"] as! NSNumber).int64Value
        )
    }
}

func registerCategorizeVectors() {
    let domain = "categorize"

    FunctionRegistry.register(domain: domain, fn: "normalizeText") { input in
        let d = input as! [String: Any]
        let n = normalizeText(d["text"] as! String)
        return ["phrase": n.phrase, "tokens": n.tokens, "merchant": n.merchant] as [String: Any]
    }

    FunctionRegistry.register(domain: domain, fn: "buildSeedMap") { input in
        let d = input as! [String: Any]
        return buildSeedMap(asCategories(d["categories"]!)).map {
            ["keyword": $0.keyword, "categoryId": $0.categoryId] as [String: Any]
        }
    }

    FunctionRegistry.register(domain: domain, fn: "buildSeedList") { input in
        let d = input as! [String: Any]
        return buildSeedList(asCategories(d["categories"]!)).map {
            ["keyword": $0.keyword, "categoryId": $0.categoryId] as [String: Any]
        }
    }

    FunctionRegistry.register(domain: domain, fn: "classify") { input in
        let d = input as! [String: Any]
        let classifier = BulkClassifier(
            rules: asRules(d["rules"]!),
            categories: asCategories(d["categories"]!)
        )
        return classifier.classify(d["text"] as! String) as Any? ?? NSNull()
    }
}
