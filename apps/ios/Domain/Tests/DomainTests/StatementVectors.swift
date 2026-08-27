import Foundation
@testable import Domain

// Wires the statements domain into FunctionRegistry.
//
// Every `expected` was produced by RUNNING web's real parseCsv.ts / analysis.ts
// / reconcile.ts, not by reading them — so the fixtures carry two of web's own
// defects on purpose:
//
//   * the `semi` case pins web bug #4's SECOND site. "1.234,56" parses as
//     1.23456, so 1,234.56 euros import as 1.23. Reproduced, not fixed, because
//     a silent divergence on an amount is worse than a shared bug.
//   * the `jpy` case is the ONE expectation edited by hand, because the ports
//     deliberately fix web bug #8 (a hardcoded *100) with fromMajor().
//
// Two shape details are load-bearing, and both come from JSON.stringify
// dropping `undefined`:
//   * parseStatementCsv's rows have no `category`/`ref` keys at all (its object
//     literal never sets them), while the analysis fixtures do.
//   * the no-table early return has no `openingBalance`/`closingBalance` keys.

private func asStatementTxn(_ any: Any) -> StatementTxn {
    let d = any as! [String: Any]
    return StatementTxn(
        date: d["date"] as! String,
        description: d["description"] as! String,
        amount: (d["amount"] as! NSNumber).int64Value,
        balance: (d["balance"] as? NSNumber)?.int64Value,
        category: d["category"] as? String,
        ref: d["ref"] as? String
    )
}

private func txnToJson(_ t: StatementTxn, withCategoryRef: Bool) -> [String: Any] {
    var out: [String: Any] = [
        "date": t.date,
        "description": t.description,
        "amount": t.amount,
        "balance": t.balance as Any? ?? NSNull(),
    ]
    if withCategoryRef {
        out["category"] = t.category as Any? ?? NSNull()
        out["ref"] = t.ref as Any? ?? NSNull()
    }
    return out
}

private func mappingToJson(_ m: ColumnMapping) -> [String: Any] {
    [
        "date": m.date as Any? ?? NSNull(),
        "description": m.description as Any? ?? NSNull(),
        "debit": m.debit as Any? ?? NSNull(),
        "credit": m.credit as Any? ?? NSNull(),
        "amount": m.amount as Any? ?? NSNull(),
        "balance": m.balance as Any? ?? NSNull(),
    ]
}

private func parsedToJson(_ p: ParsedStatement) -> [String: Any] {
    var out: [String: Any] = [
        "kind": p.kind,
        "label": p.label,
        "currency": p.currency,
        "period": ["from": p.period.from as Any? ?? NSNull(), "to": p.period.to as Any? ?? NSNull()] as [String: Any],
        "txns": p.txns.map { txnToJson($0, withCategoryRef: false) },
        "warnings": p.warnings,
        "mapping": p.mapping.map(mappingToJson) as Any? ?? NSNull(),
    ]
    // The no-table early return is the only path that never assigns these, and
    // it is identified by the warning it adds.
    if !p.warnings.contains(statementWarnNoTable) {
        out["openingBalance"] = p.openingBalance as Any? ?? NSNull()
        out["closingBalance"] = p.closingBalance as Any? ?? NSNull()
    }
    return out
}

private func asRecordedTxn(_ any: Any) -> RecordedTxn {
    let d = any as! [String: Any]
    return RecordedTxn(
        id: d["id"] as! String,
        amount: (d["amount"] as! NSNumber).int64Value,
        date: d["date"] as! String,
        description: d["description"] as! String
    )
}

private func recordedToJson(_ r: RecordedTxn) -> [String: Any] {
    ["id": r.id, "amount": r.amount, "date": r.date, "description": r.description]
}

func registerStatementVectors() {
    let domain = "statements"

    FunctionRegistry.register(domain: domain, fn: "parseStatementDate") { input in
        let d = input as! [String: Any]
        return parseStatementDate(d["s"] as? String) as Any? ?? NSNull()
    }

    FunctionRegistry.register(domain: domain, fn: "parseStatementCsv") { input in
        let d = input as! [String: Any]
        return parsedToJson(parseStatementCsv(
            d["text"] as! String,
            currency: d["currency"] as! String,
            kind: d["kind"] as! String
        ))
    }

    FunctionRegistry.register(domain: domain, fn: "summarize") { input in
        let d = input as! [String: Any]
        let s = summarize((d["txns"] as! [Any]).map(asStatementTxn))
        return [
            "count": s.count,
            "credits": s.credits,
            "debits": s.debits,
            "net": s.net,
            "from": s.from as Any? ?? NSNull(),
            "to": s.to as Any? ?? NSNull(),
        ] as [String: Any]
    }

    FunctionRegistry.register(domain: domain, fn: "byCategory") { input in
        let d = input as! [String: Any]
        return byCategory((d["txns"] as! [Any]).map(asStatementTxn)).map {
            ["name": $0.name, "total": $0.total, "count": $0.count] as [String: Any]
        }
    }

    FunctionRegistry.register(domain: domain, fn: "byMonth") { input in
        let d = input as! [String: Any]
        return byMonth((d["txns"] as! [Any]).map(asStatementTxn)).map {
            ["ym": $0.ym, "debit": $0.debit, "credit": $0.credit] as [String: Any]
        }
    }

    FunctionRegistry.register(domain: domain, fn: "byDay") { input in
        let d = input as! [String: Any]
        return byDay((d["txns"] as! [Any]).map(asStatementTxn)).map {
            ["date": $0.date, "debit": $0.debit] as [String: Any]
        }
    }

    FunctionRegistry.register(domain: domain, fn: "outliers") { input in
        let d = input as! [String: Any]
        return outliers((d["txns"] as! [Any]).map(asStatementTxn)).map {
            [
                "txn": txnToJson($0.txn, withCategoryRef: true),
                "amount": $0.amount,
                "reason": $0.reason,
            ] as [String: Any]
        }
    }

    FunctionRegistry.register(domain: domain, fn: "normalizeMerchant") { input in
        let d = input as! [String: Any]
        return normalizeMerchant(d["s"] as! String)
    }

    FunctionRegistry.register(domain: domain, fn: "recurringCandidates") { input in
        let d = input as! [String: Any]
        return recurringCandidates((d["txns"] as! [Any]).map(asStatementTxn)).map { c in
            [
                "label": c.label,
                "key": c.key,
                "amount": c.amount,
                "count": c.count,
                "cadence": c.cadence,
                "sample": c.sample.map { txnToJson($0, withCategoryRef: true) },
            ] as [String: Any]
        }
    }

    FunctionRegistry.register(domain: domain, fn: "reconcileStatement") { input in
        let d = input as! [String: Any]
        let r = reconcileStatement(
            (d["parsed"] as! [Any]).map(asStatementTxn),
            (d["recorded"] as! [Any]).map(asRecordedTxn),
            dayWindow: (d["dayWindow"] as! NSNumber).intValue
        )
        return [
            "matched": r.matched.map {
                [
                    "parsed": txnToJson($0.parsed, withCategoryRef: true),
                    "recorded": recordedToJson($0.recorded),
                    "score": $0.score,
                ] as [String: Any]
            },
            "missingOnPlatform": r.missingOnPlatform.map { txnToJson($0, withCategoryRef: true) },
            "onlyOnPlatform": r.onlyOnPlatform.map(recordedToJson),
        ] as [String: Any]
    }
}
