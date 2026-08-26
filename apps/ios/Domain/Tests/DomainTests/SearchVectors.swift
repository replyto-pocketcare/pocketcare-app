import Foundation
@testable import Domain

// Wires Search.swift into FunctionRegistry.
//
// Web's filter lives inside a `useMemo` in app/search/page.tsx and cannot be
// imported, so these vectors come from a reference implementation of the PORT
// that was diffed, case by case, against a literal transcription of web's
// component. The two agree everywhere except three min/max cases involving a
// JPY row — web's hardcoded `* 100` makes a "1000" bound mean 100000 minor
// units in every currency. Those three are the deliberate divergence, and they
// are in here so that it stays deliberate.

/// Absent and null both mean "no value" — the fixtures omit null fields.
private func optionalString(_ any: Any?) -> String? {
    guard let any, !(any is NSNull) else { return nil }
    return any as? String
}

private func searchRows(_ arr: [Any]) -> [SearchRow] {
    arr.map { entry in
        let o = entry as! [String: Any]
        return SearchRow(
            id: o["id"] as! String,
            type: o["type"] as! String,
            accountId: o["accountId"] as! String,
            toAccountId: optionalString(o["toAccountId"]),
            occurredAt: o["occurredAt"] as! String,
            amountMinor: (o["amountMinor"] as! NSNumber).int64Value,
            currency: o["currency"] as! String,
            labels: optionalString(o["labels"]),
            note: optionalString(o["note"]),
            description: optionalString(o["description"]),
            methodLabel: optionalString(o["methodLabel"]),
            categoryName: optionalString(o["categoryName"]),
            accountName: optionalString(o["accountName"]),
            accountType: optionalString(o["accountType"])
        )
    }
}

private func searchCriteria(_ o: [String: Any]) -> SearchCriteria {
    SearchCriteria(
        query: optionalString(o["query"]) ?? "",
        type: optionalString(o["type"]) ?? "all",
        accountId: optionalString(o["accountId"]) ?? "",
        from: optionalString(o["from"]) ?? "",
        to: optionalString(o["to"]) ?? "",
        min: optionalString(o["min"]) ?? "",
        max: optionalString(o["max"]) ?? ""
    )
}

func registerSearchVectors() {
    FunctionRegistry.register(domain: "search", fn: "searchTransactions") { input in
        let d = input as! [String: Any]
        let result = searchTransactions(
            searchRows(d["rows"] as! [Any]),
            searchCriteria(d["criteria"] as! [String: Any])
        )
        // Ids, not whole rows: the vector pins WHICH rows survive and in what
        // order, which is the whole contract. Echoing the inputs back would
        // double the fixture and test nothing extra.
        return result.map(\.id)
    }

    FunctionRegistry.register(domain: "search", fn: "activeFilterCount") { input in
        let d = input as! [String: Any]
        return activeFilterCount(searchCriteria(d["criteria"] as! [String: Any]))
    }
}
