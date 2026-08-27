import Foundation
@testable import Domain

// Wires Csv.swift and ImportAdapters.swift into FunctionRegistry.
//
// Unusually for a port of a page's logic, these vectors came from running web's
// REAL exports — csv.ts and adapters.ts are plain modules. The only edit was
// adding a `.ts` extension to adapters.ts's relative import so node could
// resolve it; the copy was diffed against the original to prove that is all
// that changed.
//
// One vector records a WEB BUG on purpose: `"1.234,56"` parses as 1.23456, not
// 1234.56. See PARITY_AUDIT — it is left in so a fix on web makes this vector
// fail rather than passing silently on two of three platforms.

private func optionalString(_ any: Any?) -> String? {
    guard let any, !(any is NSNull) else { return nil }
    return any as? String
}

private func canonToJson(_ r: CanonRow) -> [String: Any] {
    [
        "date": r.date,
        "type": r.type,
        "amount": r.amount,
        "currency": r.currency,
        "account": r.account,
        "toAccount": r.toAccount.map { $0 as Any } ?? NSNull(),
        "toAmount": r.toAmount.map { $0 as Any } ?? NSNull(),
        "category": r.category.map { $0 as Any } ?? NSNull(),
        "labels": r.labels,
        "paymentMethod": r.paymentMethod.map { $0 as Any } ?? NSNull(),
        "note": r.note.map { $0 as Any } ?? NSNull(),
        "description": r.description.map { $0 as Any } ?? NSNull(),
    ]
}

func registerCsvVectors() {
    FunctionRegistry.register(domain: "csv", fn: "parseCsv") { input in
        let d = input as! [String: Any]
        return parseCsv(d["text"] as! String, delimiter: optionalString(d["delimiter"]))
    }

    FunctionRegistry.register(domain: "csv", fn: "parseRecords") { input in
        let d = input as! [String: Any]
        return parseRecords(d["text"] as! String, delimiter: optionalString(d["delimiter"]))
            .map { rec -> [String: Any] in
                var out: [String: Any] = [:]
                for key in rec.keys { out[key] = rec[key] ?? "" }
                return out
            }
    }

    FunctionRegistry.register(domain: "csv", fn: "toCsv") { input in
        let d = input as! [String: Any]
        let rows = (d["rows"] as! [Any]).map { row in
            (row as! [Any]).map { optionalString($0) }
        }
        return toCsv(rows)
    }

    FunctionRegistry.register(domain: "csv", fn: "parseWithAdapter") { input in
        let d = input as! [String: Any]
        return parseWithAdapter(
            d["adapterId"] as! String,
            d["text"] as! String,
            nowIso: d["nowIso"] as! String
        ).map(canonToJson)
    }

    FunctionRegistry.register(domain: "csv", fn: "importDate") { input in
        let d = input as! [String: Any]
        return importDate(d["raw"] as! String, nowIso: d["nowIso"] as! String)
    }

    FunctionRegistry.register(domain: "csv", fn: "guessAccountType") { input in
        let d = input as! [String: Any]
        return guessAccountType(d["name"] as! String)
    }
}
