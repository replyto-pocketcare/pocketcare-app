import Foundation
@testable import Domain

// P1.3b: wires the real Budget.swift port into FunctionRegistry so
// budget.json's vectors un-skip. Registered under (domain="budget",
// fn=<name>) to match tools/golden-vectors/vectors/budget.json exactly.
//
// periodBounds/billingCycle's date inputs ("2026-07-31T12:00:00Z") are
// truncated to their first 10 characters and parsed straight into Ymd --
// mirrors the TS source's own utcMidnight() truncation, and sidesteps
// ever parsing a full timestamp/timezone here. Outputs are re-expanded to
// full "YYYY-MM-DDT00:00:00.000Z" strings via Ymd.description to match
// the exported vectors exactly (JS's Date -> JSON.stringify always writes
// milliseconds + "Z").

private func parseUtcDay(_ iso: String) -> Ymd {
    let s = String(iso.prefix(10))
    let parts = s.split(separator: "-").map { Int($0)! }
    return Ymd(year: parts[0], month: parts[1], day: parts[2])
}

private func jsIso(_ ymd: Ymd) -> String {
    "\(ymd.description)T00:00:00.000Z"
}

private func asMoney(_ any: Any) -> Money {
    let d = any as! [String: Any]
    return Money(amount: (d["amount"] as! NSNumber).int64Value, currency: d["currency"] as! String)
}

private func moneyToJson(_ m: Money) -> [String: Any] {
    ["amount": String(m.amount), "currency": m.currency]
}

func registerBudgetVectors() {
    FunctionRegistry.register(domain: "budget", fn: "periodBounds") { input in
        let d = input as! [String: Any]
        let w = periodBounds(d["period"] as! String, parseUtcDay(d["date"] as! String))
        return ["start": jsIso(w.start), "endExclusive": jsIso(w.endExclusive)]
    }

    FunctionRegistry.register(domain: "budget", fn: "budgetProgress") { input in
        let d = input as! [String: Any]
        let p = try budgetProgress(asMoney(d["limit"]!), asMoney(d["spent"]!), (d["thresholdPct"] as! NSNumber).doubleValue)
        return [
            "pct": jsonNumber(p.pct),
            "remaining": moneyToJson(p.remaining),
            "atOrOverThreshold": p.atOrOverThreshold,
            "overLimit": p.overLimit,
        ]
    }

    FunctionRegistry.register(domain: "budget", fn: "crossedThreshold") { input in
        let d = input as! [String: Any]
        return crossedThreshold(
            asMoney(d["previousSpent"]!),
            asMoney(d["newSpent"]!),
            asMoney(d["limit"]!),
            (d["thresholdPct"] as! NSNumber).doubleValue
        )
    }

    FunctionRegistry.register(domain: "budget", fn: "billingCycle") { input in
        let d = input as! [String: Any]
        let c = billingCycle(
            (d["statementDay"] as! NSNumber).intValue,
            (d["dueDay"] as! NSNumber).intValue,
            parseUtcDay(d["asOf"] as! String)
        )
        return [
            "cycleStart": jsIso(c.cycleStart),
            "statementDate": jsIso(c.statementDate),
            "dueDate": jsIso(c.dueDate),
        ]
    }
}
